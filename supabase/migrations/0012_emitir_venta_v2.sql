-- ============================================================
-- Konversa · emitir_venta v2 (reemplaza 0009)
-- Corrige de raíz:
--   • Correlativo que se "quemaba" en carreras de idempotencia
--     → lock advisory por (empresa, llave) serializa; ya no salta la numeración.
--   • IGV falso en exonerado/inafecto → respeta tipo_afectacion por ítem.
--   • Receptor "varios" que se perdía → se persiste en documents.receptor_*.
--   • Factura sin RUC válido → valida receptor vs tipo de comprobante.
--   • Kardex omitido si no había fila de stock → crea almacén/fila y SIEMPRE mueve kardex.
--   • Moneda fija PEN → moneda + tipo de cambio; condición de pago (contado/crédito → CxC).
-- Idempotente. Supabase → SQL Editor → pega TODO → Run
-- ============================================================

drop function if exists emitir_venta(uuid, text, text, jsonb, jsonb, text, numeric, numeric, uuid, text, numeric);

create or replace function emitir_venta(
  p_company_id       uuid,
  p_tipo_doc         text,
  p_serie            text,
  p_cliente          jsonb,          -- { customer_id?, tipo_doc, num_doc?, denominacion, direccion? }
  p_items            jsonb,          -- [ { product_id?, descripcion, cantidad, precio_unitario, tipo_afectacion?, unidad_medida? } ]
  p_forma_pago       text    default 'efectivo',
  p_monto_recibido   numeric default null,
  p_vuelto           numeric default null,
  p_cash_session_id  uuid    default null,
  p_idempotency_key  text    default null,
  p_igv_rate         numeric default 0.18,
  p_moneda           text    default 'PEN',
  p_tipo_cambio      numeric default 1,
  p_condicion_pago   text    default 'contado',
  p_fecha_vencimiento date   default null,
  p_establishment_id uuid    default null
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
  v_afect        text;
  v_price        numeric;
  v_line_total   numeric(12,2);
  v_line_base    numeric(12,2);
  v_line_igv     numeric(12,2);
  v_total        numeric(12,2) := 0;
  v_gravado      numeric(12,2) := 0;
  v_igv          numeric(12,2) := 0;
  v_exonerado    numeric(12,2) := 0;
  v_inafecto     numeric(12,2) := 0;
  v_gratuito     numeric(12,2) := 0;
  v_wh           uuid;
  v_numero       text;
  v_attempts     int := 0;
  v_estado_pago  text;
  v_saldo        numeric(12,2);
  -- receptor
  v_r_tipo       text := coalesce(nullif(p_cliente->>'tipo_doc',''), '0');
  v_r_num        text := nullif(p_cliente->>'num_doc','');
  v_r_den        text := coalesce(nullif(p_cliente->>'denominacion',''), 'Cliente varios');
  v_r_dir        text := nullif(p_cliente->>'direccion','');
begin
  -- 0) Seguridad multiempresa
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no tiene ítems';
  end if;

  -- 0.1) Validación receptor vs tipo de comprobante (SUNAT)
  --      Factura (01) exige RUC (tipo 6, 11 dígitos). ND/NC heredan del original en emitir_nota.
  if p_tipo_doc = '01' then
    if v_r_tipo <> '6' or v_r_num is null or v_r_num !~ '^\d{11}$' then
      raise exception 'Una factura (01) requiere un cliente con RUC válido de 11 dígitos';
    end if;
  end if;

  -- 0.2) Idempotencia con lock advisory por (empresa, llave):
  --      dos requests con la MISMA llave se serializan; el segundo encuentra el doc ya
  --      creado y retorna SIN consumir correlativo (no hay salto de numeración).
  if p_idempotency_key is not null then
    perform pg_advisory_xact_lock(hashtextextended(p_company_id::text || ':' || p_idempotency_key, 0));
    select * into v_existing from documents
      where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
    if found then
      return jsonb_build_object(
        'id', v_existing.id, 'serie', v_existing.serie, 'correlativo', v_existing.correlativo,
        'tipo_doc', v_existing.tipo_doc, 'total_gravado', v_existing.total_gravado,
        'total_igv', v_existing.total_igv, 'total', v_existing.total,
        'estado_sunat', v_existing.estado_sunat, 'reused', true);
    end if;
  end if;

  -- 1) Caja abierta (flujo POS)
  if p_cash_session_id is not null then
    perform 1 from cash_sessions
      where id = p_cash_session_id and company_id = p_company_id and estado = 'abierta';
    if not found then
      raise exception 'No hay una caja abierta para registrar la venta';
    end if;
  end if;

  -- 2) Totales respetando el tipo de afectación por ítem
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid   := nullif(v_item->>'product_id','')::uuid;
    v_qty   := (v_item->>'cantidad')::numeric;
    v_price := (v_item->>'precio_unitario')::numeric;
    v_afect := coalesce(
      nullif(v_item->>'tipo_afectacion',''),
      (select tipo_afectacion from products where id = v_pid and company_id = p_company_id),
      '10');
    v_line_total := round(v_qty * v_price, 2);

    if v_afect = '10' then                                  -- gravado (precio incluye IGV)
      v_line_base := round(v_line_total / (1 + p_igv_rate), 2);
      v_line_igv  := v_line_total - v_line_base;
      v_gravado   := v_gravado + v_line_base;
      v_igv       := v_igv + v_line_igv;
      v_total     := v_total + v_line_total;
    elsif v_afect = '20' then                               -- exonerado (sin IGV)
      v_exonerado := v_exonerado + v_line_total;
      v_total     := v_total + v_line_total;
    elsif v_afect = '30' then                               -- inafecto (sin IGV)
      v_inafecto  := v_inafecto + v_line_total;
      v_total     := v_total + v_line_total;
    elsif left(v_afect, 1) = '2' or left(v_afect, 1) = '3' then  -- gratuito (21,31..) no suma a pagar
      v_gratuito  := v_gratuito + v_line_total;
    else
      v_line_base := round(v_line_total / (1 + p_igv_rate), 2);
      v_line_igv  := v_line_total - v_line_base;
      v_gravado   := v_gravado + v_line_base;
      v_igv       := v_igv + v_line_igv;
      v_total     := v_total + v_line_total;
    end if;
  end loop;

  -- Vínculo de cliente registrado (opcional). El receptor SIEMPRE se persiste aparte.
  v_customer_id := nullif(p_cliente->>'customer_id', '')::uuid;
  if v_customer_id is not null
     and not exists (select 1 from customers where id = v_customer_id and company_id = p_company_id) then
    v_customer_id := null;
  end if;

  -- Condición de pago → cuentas por cobrar
  if p_condicion_pago = 'credito' then
    v_estado_pago := 'pendiente';
    v_saldo := v_total;
  else
    v_estado_pago := 'pagado';
    v_saldo := 0;
  end if;

  -- 3) Reserva de correlativo + INSERT atómico, con reintento ante colisión de correlativo.
  loop
    v_attempts := v_attempts + 1;
    insert into series (company_id, tipo_doc, serie, correlativo, establishment_id)
      values (p_company_id, p_tipo_doc, p_serie, 0, p_establishment_id)
      on conflict (company_id, tipo_doc, serie) do nothing;
    update series set correlativo = correlativo + 1
      where company_id = p_company_id and tipo_doc = p_tipo_doc and serie = p_serie
      returning correlativo into v_correlativo;
    v_numero := p_serie || '-' || lpad(v_correlativo::text, 8, '0');

    begin
      insert into documents (
        company_id, establishment_id, customer_id, tipo_doc, serie, correlativo,
        moneda, tipo_cambio, total_gravado, total_igv, total_exonerado, total_inafecto,
        total_gratuito, total, estado_sunat, user_id, cash_session_id, forma_pago,
        monto_recibido, vuelto, condicion_pago, estado_pago, saldo, fecha_vencimiento,
        receptor_tipo_doc, receptor_num_doc, receptor_denominacion, receptor_direccion,
        idempotency_key
      ) values (
        p_company_id, p_establishment_id, v_customer_id, p_tipo_doc, p_serie, v_correlativo,
        p_moneda, p_tipo_cambio, v_gravado, v_igv, v_exonerado, v_inafecto,
        v_gratuito, v_total, 'pendiente', v_user_id, p_cash_session_id, p_forma_pago,
        p_monto_recibido, p_vuelto, p_condicion_pago, v_estado_pago, v_saldo, p_fecha_vencimiento,
        v_r_tipo, v_r_num, v_r_den, v_r_dir,
        coalesce(p_idempotency_key, gen_random_uuid()::text)
      ) returning id into v_doc_id;
      exit;                                                 -- éxito
    exception when unique_violation then
      -- Si chocó por idempotencia (carrera muy rara pese al lock), devolver el existente.
      if p_idempotency_key is not null then
        select * into v_existing from documents
          where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
        if found then
          return jsonb_build_object(
            'id', v_existing.id, 'serie', v_existing.serie, 'correlativo', v_existing.correlativo,
            'tipo_doc', v_existing.tipo_doc, 'total_gravado', v_existing.total_gravado,
            'total_igv', v_existing.total_igv, 'total', v_existing.total,
            'estado_sunat', v_existing.estado_sunat, 'reused', true);
        end if;
      end if;
      if v_attempts >= 5 then raise; end if;                -- colisión de correlativo: reintenta
    end;
  end loop;

  -- 4) Ítems + kardex robusto
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid := nullif(v_item->>'product_id','')::uuid;
    if v_pid is not null
       and not exists (select 1 from products where id = v_pid and company_id = p_company_id) then
      v_pid := null;
    end if;
    v_qty   := (v_item->>'cantidad')::numeric;
    v_price := (v_item->>'precio_unitario')::numeric;
    v_afect := coalesce(
      nullif(v_item->>'tipo_afectacion',''),
      (select tipo_afectacion from products where id = v_pid), '10');
    v_line_total := round(v_qty * v_price, 2);
    if v_afect = '10' then
      v_line_base := round(v_line_total / (1 + p_igv_rate), 2);
      v_line_igv  := v_line_total - v_line_base;
    else
      v_line_base := v_line_total;
      v_line_igv  := 0;
    end if;

    insert into document_items (
      document_id, product_id, descripcion, cantidad, valor_unitario,
      precio_unitario, igv, total, tipo_afectacion, unidad_medida
    ) values (
      v_doc_id, v_pid, v_item->>'descripcion', v_qty,
      case when v_qty <> 0 then round(v_line_base / v_qty, 2) else 0 end,
      v_price, v_line_igv, v_line_total, v_afect,
      coalesce(nullif(v_item->>'unidad_medida',''), 'NIU')
    );

    -- Kardex: si el producto controla stock, garantiza almacén + fila y SIEMPRE registra salida.
    if v_pid is not null
       and exists (select 1 from products where id = v_pid and controla_stock) then
      -- almacén con más stock; si no hay fila, cualquiera de la empresa; si no hay almacén, crea 'Principal'.
      select warehouse_id into v_wh from stock where product_id = v_pid
        order by cantidad desc limit 1 for update;
      if v_wh is null then
        select id into v_wh from warehouses where company_id = p_company_id order by created_at limit 1;
      end if;
      if v_wh is null then
        insert into warehouses (company_id, nombre) values (p_company_id, 'Principal') returning id into v_wh;
      end if;
      insert into stock (product_id, warehouse_id, cantidad) values (v_pid, v_wh, 0)
        on conflict (product_id, warehouse_id) do nothing;
      update stock set cantidad = cantidad - v_qty where product_id = v_pid and warehouse_id = v_wh;
      insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
        values (p_company_id, v_pid, v_wh, 'salida', v_qty, 'Venta ' || v_numero);
    end if;
  end loop;

  -- 5) Pago: ledger de pagos (para contado) + efectivo al arqueo de caja.
  if p_condicion_pago = 'contado' then
    insert into payments (company_id, tipo, document_id, cash_session_id, medio, monto, fecha)
      values (p_company_id, 'cobro', v_doc_id, p_cash_session_id, p_forma_pago, v_total, current_date);
    if p_cash_session_id is not null and p_forma_pago = 'efectivo' then
      insert into cash_movements (cash_session_id, tipo, monto, motivo, document_id)
        values (p_cash_session_id, 'ingreso', v_total, 'Venta ' || v_numero, v_doc_id);
    end if;
  end if;

  return jsonb_build_object(
    'id', v_doc_id, 'serie', p_serie, 'correlativo', v_correlativo, 'numero', v_numero,
    'tipo_doc', p_tipo_doc, 'total_gravado', v_gravado, 'total_igv', v_igv,
    'total_exonerado', v_exonerado, 'total_inafecto', v_inafecto, 'total_gratuito', v_gratuito,
    'total', v_total, 'estado_sunat', 'pendiente', 'reused', false
  );
end $$;

grant execute on function emitir_venta(uuid, text, text, jsonb, jsonb, text, numeric, numeric, uuid, text, numeric, text, numeric, text, date, uuid)
  to authenticated, service_role;
