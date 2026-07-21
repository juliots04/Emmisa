-- ============================================================
-- Konversa · Venta transaccional (POS)
-- Resuelve de raíz 3 huecos del flujo de venta:
--   (2) descuento de stock automático,
--   (3) registro del efectivo en caja + exigir caja abierta,
--   (4) correlativo transaccional desde la tabla `series` (sin race conditions).
-- Todo ocurre en UNA transacción atómica dentro de emitir_venta().
-- Cómo usarlo: Supabase → SQL Editor → pega todo → Run
-- ============================================================

-- ==================== Columnas nuevas ====================
-- documents: quién vendió, en qué caja, cómo pagó y el efectivo/vuelto.
alter table documents add column if not exists user_id         uuid references auth.users(id);
alter table documents add column if not exists cash_session_id uuid references cash_sessions(id) on delete set null;
alter table documents add column if not exists forma_pago      text;
alter table documents add column if not exists monto_recibido  numeric(12,2);
alter table documents add column if not exists vuelto          numeric(12,2);

-- cash_movements: liga el ingreso de caja con la venta que lo generó.
alter table cash_movements add column if not exists document_id uuid references documents(id) on delete set null;

-- Idempotencia real: evita duplicar la venta ante reintentos/doble clic.
create unique index if not exists ux_documents_idempotency
  on documents (company_id, idempotency_key)
  where idempotency_key is not null;

-- ==================== Función de venta atómica ====================
create or replace function emitir_venta(
  p_company_id      uuid,
  p_tipo_doc        text,
  p_serie           text,
  p_cliente         jsonb,          -- { customer_id?, tipo_doc, num_doc?, denominacion }
  p_items           jsonb,          -- [ { product_id?, descripcion, cantidad, precio_unitario } ]
  p_forma_pago      text    default 'efectivo',
  p_monto_recibido  numeric default null,
  p_vuelto          numeric default null,
  p_cash_session_id uuid    default null,
  p_idempotency_key text    default null,
  p_igv_rate        numeric default 0.18
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id      uuid := auth.uid();
  v_correlativo  int;
  v_doc_id       uuid;
  v_customer_id  uuid;
  v_existing     documents%rowtype;
  v_item         jsonb;
  v_pid          uuid;
  v_qty          numeric;
  v_line_total   numeric(12,2);
  v_line_gravado numeric(12,2);
  v_line_igv     numeric(12,2);
  v_total        numeric(12,2) := 0;
  v_gravado      numeric(12,2) := 0;
  v_igv          numeric(12,2) := 0;
  v_wh           uuid;
  v_numero       text;
begin
  -- 0) Seguridad: la empresa debe pertenecer al usuario (SECURITY DEFINER salta RLS).
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no tiene ítems';
  end if;

  -- 0.1) Idempotencia: si ya existe una venta con esta llave, devolverla (no duplica).
  if p_idempotency_key is not null then
    select * into v_existing from documents
      where company_id = p_company_id and idempotency_key = p_idempotency_key
      limit 1;
    if found then
      return jsonb_build_object(
        'id', v_existing.id, 'serie', v_existing.serie, 'correlativo', v_existing.correlativo,
        'tipo_doc', v_existing.tipo_doc, 'total_gravado', v_existing.total_gravado,
        'total_igv', v_existing.total_igv, 'total', v_existing.total,
        'estado_sunat', v_existing.estado_sunat, 'reused', true
      );
    end if;
  end if;

  -- 1) (3) Exigir caja abierta cuando se indica sesión (flujo POS).
  if p_cash_session_id is not null then
    perform 1 from cash_sessions
      where id = p_cash_session_id and company_id = p_company_id and estado = 'abierta';
    if not found then
      raise exception 'No hay una caja abierta para registrar la venta';
    end if;
  end if;

  -- 2) (4) Correlativo transaccional: crea la serie si no existe y la incrementa.
  --    El UPDATE toma lock de la fila -> emisión concurrente se serializa (sin duplicados).
  insert into series (company_id, tipo_doc, serie, correlativo)
    values (p_company_id, p_tipo_doc, p_serie, 0)
    on conflict (company_id, tipo_doc, serie) do nothing;

  update series set correlativo = correlativo + 1
    where company_id = p_company_id and tipo_doc = p_tipo_doc and serie = p_serie
    returning correlativo into v_correlativo;

  v_numero := p_serie || '-' || lpad(v_correlativo::text, 8, '0');

  -- 3) Totales (IGV incluido en precio_unitario, igual que el resto de la app).
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_line_total   := round((v_item->>'cantidad')::numeric * (v_item->>'precio_unitario')::numeric, 2);
    v_line_gravado := round(v_line_total / (1 + p_igv_rate), 2);
    v_line_igv     := v_line_total - v_line_gravado;
    v_total   := v_total   + v_line_total;
    v_gravado := v_gravado + v_line_gravado;
    v_igv     := v_igv     + v_line_igv;
  end loop;

  v_customer_id := nullif(p_cliente->>'customer_id', '')::uuid;
  -- Seguridad multiempresa: el cliente debe ser de la empresa; si no, se ignora el vínculo.
  if v_customer_id is not null
     and not exists (select 1 from customers where id = v_customer_id and company_id = p_company_id) then
    v_customer_id := null;
  end if;

  -- 4) Cabecera del comprobante (estado 'pendiente'; el motor SUNAT lo actualiza luego).
  --    El INSERT va en un sub-bloque: si dos requests concurrentes usan la MISMA llave de
  --    idempotencia, el perdedor cae en unique_violation y devolvemos la venta ya creada
  --    (en vez de propagar un error crudo al cliente).
  begin
    insert into documents (
      company_id, customer_id, tipo_doc, serie, correlativo, moneda,
      total_gravado, total_igv, total, estado_sunat,
      user_id, cash_session_id, forma_pago, monto_recibido, vuelto, idempotency_key
    ) values (
      p_company_id, v_customer_id, p_tipo_doc, p_serie, v_correlativo, 'PEN',
      v_gravado, v_igv, v_total, 'pendiente',
      v_user_id, p_cash_session_id, p_forma_pago, p_monto_recibido, p_vuelto,
      coalesce(p_idempotency_key, gen_random_uuid()::text)
    ) returning id into v_doc_id;
  exception when unique_violation then
    select * into v_existing from documents
      where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
    return jsonb_build_object(
      'id', v_existing.id, 'serie', v_existing.serie, 'correlativo', v_existing.correlativo,
      'tipo_doc', v_existing.tipo_doc, 'total_gravado', v_existing.total_gravado,
      'total_igv', v_existing.total_igv, 'total', v_existing.total,
      'estado_sunat', v_existing.estado_sunat, 'reused', true);
  end;

  -- 5) Ítems + (2) descuento de stock.
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid := nullif(v_item->>'product_id', '')::uuid;
    -- Seguridad multiempresa: si el producto no es de la empresa, se guarda el ítem sin vínculo.
    if v_pid is not null
       and not exists (select 1 from products where id = v_pid and company_id = p_company_id) then
      v_pid := null;
    end if;
    v_qty := (v_item->>'cantidad')::numeric;
    v_line_total   := round(v_qty * (v_item->>'precio_unitario')::numeric, 2);
    v_line_gravado := round(v_line_total / (1 + p_igv_rate), 2);
    v_line_igv     := v_line_total - v_line_gravado;

    insert into document_items (
      document_id, product_id, descripcion, cantidad, valor_unitario, precio_unitario, igv, total
    ) values (
      v_doc_id, v_pid, v_item->>'descripcion', v_qty,
      case when v_qty <> 0 then round(v_line_gravado / v_qty, 2) else 0 end,
      (v_item->>'precio_unitario')::numeric, v_line_igv, v_line_total
    );

    -- Descuenta stock solo si el producto controla stock y ya tiene existencias registradas
    -- (elige el almacén con más stock). El FOR UPDATE serializa decrementos concurrentes del
    -- mismo producto (no se pierden); el stock PUEDE quedar negativo -> sobreventa permitida
    -- (el POS ya avisa antes de vender sin stock). Cambiar a bloqueo = negocio, no técnico.
    if v_pid is not null
       and exists (select 1 from products where id = v_pid and controla_stock) then
      select warehouse_id into v_wh
        from stock where product_id = v_pid
        order by cantidad desc limit 1
        for update;
      if found then
        update stock set cantidad = cantidad - v_qty
          where product_id = v_pid and warehouse_id = v_wh;
        insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
          values (p_company_id, v_pid, v_wh, 'salida', v_qty, 'Venta ' || v_numero);
      end if;
    end if;
  end loop;

  -- 6) (3) Caja: solo el EFECTIVO afecta el arqueo físico (Yape/tarjeta/transf. no).
  if p_cash_session_id is not null and p_forma_pago = 'efectivo' then
    insert into cash_movements (cash_session_id, tipo, monto, motivo, document_id)
      values (p_cash_session_id, 'ingreso', v_total, 'Venta ' || v_numero, v_doc_id);
  end if;

  return jsonb_build_object(
    'id', v_doc_id, 'serie', p_serie, 'correlativo', v_correlativo,
    'tipo_doc', p_tipo_doc, 'total_gravado', v_gravado, 'total_igv', v_igv,
    'total', v_total, 'estado_sunat', 'pendiente', 'reused', false
  );
end $$;

-- La Data API (PostgREST) necesita permiso de ejecución explícito.
grant execute on function emitir_venta(uuid, text, text, jsonb, jsonb, text, numeric, numeric, uuid, text, numeric)
  to authenticated, service_role;
