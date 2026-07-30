-- ============================================================
-- Emmisa · 0027 Fixes de auditoría de núcleos (CxC + Compras)
--   (HIGH) registrar_abono: bloquea la fila (FOR UPDATE) antes de calcular el
--          abono → elimina la carrera que dejaba saldo negativo y pagos/caja
--          duplicados bajo concurrencia (doble clic / dos cajeros).
--   (HIGH) registrar_compra: el IGV/crédito fiscal SOLO se separa en FACTURA (01);
--          boleta/recibo por honorarios (02)/otros → sin IGV recuperable (todo es
--          costo/gasto). Evita crédito fiscal ficticio en el Registro de Compras.
--   (MED)  el costo del producto en compra sin crédito fiscal conserva el IGV.
--   (LOW)  reporte_cuentas_por_cobrar incluye créditos PENDIENTES ante SUNAT.
--   (LOW)  índice único de proveedores por (empresa, RUC).
-- Rebasado sobre 0023/0024 (versiones vivas). Aplicar DESPUÉS de 0026. Idempotente.
-- ============================================================

-- (1) registrar_abono = 0023 + SELECT ... FOR UPDATE (anti-carrera)
create or replace function registrar_abono(
  p_company_id uuid, p_monto numeric, p_document_id uuid default null,
  p_purchase_id uuid default null, p_medio text default 'efectivo',
  p_referencia text default null, p_cash_session_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_saldo numeric(12,2); v_aplicado numeric(12,2); v_tipo text;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_monto is null or p_monto <= 0 then raise exception 'Monto inválido'; end if;
  if p_cash_session_id is not null then
    perform 1 from cash_sessions where id = p_cash_session_id and company_id = p_company_id and estado = 'abierta';
    if not found then raise exception 'La caja indicada no es de esta empresa o no está abierta'; end if;
  end if;

  if p_document_id is not null then
    v_tipo := 'cobro';
    -- FIX carrera: bloquea la fila ANTES de calcular (dos abonos concurrentes se serializan).
    select saldo into v_saldo from documents where id = p_document_id and company_id = p_company_id for update;
    if not found then raise exception 'Comprobante no encontrado'; end if;
    v_aplicado := least(p_monto, greatest(coalesce(v_saldo, 0), 0));
    if v_aplicado <= 0 then raise exception 'El comprobante no tiene saldo pendiente'; end if;
    update documents set saldo = saldo - v_aplicado,
      estado_pago = case when saldo - v_aplicado <= 0 then 'pagado' else 'parcial' end
      where id = p_document_id returning saldo into v_saldo;
    insert into payments (company_id, tipo, document_id, cash_session_id, medio, monto, referencia)
      values (p_company_id, 'cobro', p_document_id, p_cash_session_id, p_medio, v_aplicado, p_referencia);
    if p_cash_session_id is not null and p_medio = 'efectivo' then
      insert into cash_movements (cash_session_id, tipo, monto, motivo, document_id)
        values (p_cash_session_id, 'ingreso', v_aplicado, 'Abono CxC', p_document_id);
    end if;
  elsif p_purchase_id is not null then
    v_tipo := 'pago';
    select saldo into v_saldo from purchases where id = p_purchase_id and company_id = p_company_id for update;
    if not found then raise exception 'Compra no encontrada'; end if;
    v_aplicado := least(p_monto, greatest(coalesce(v_saldo, 0), 0));
    if v_aplicado <= 0 then raise exception 'La compra no tiene saldo pendiente'; end if;
    update purchases set saldo = saldo - v_aplicado,
      estado_pago = case when saldo - v_aplicado <= 0 then 'pagado' else 'parcial' end
      where id = p_purchase_id returning saldo into v_saldo;
    insert into payments (company_id, tipo, purchase_id, cash_session_id, medio, monto, referencia)
      values (p_company_id, 'pago', p_purchase_id, p_cash_session_id, p_medio, v_aplicado, p_referencia);
    if p_cash_session_id is not null and p_medio = 'efectivo' then
      insert into cash_movements (cash_session_id, tipo, monto, motivo, document_id)
        values (p_cash_session_id, 'retiro', v_aplicado, 'Pago CxP', null);
    end if;
  else
    raise exception 'Indica un comprobante (CxC) o una compra (CxP)';
  end if;
  return jsonb_build_object('tipo', v_tipo, 'saldo', v_saldo, 'aplicado', v_aplicado);
end $$;
grant execute on function registrar_abono(uuid, numeric, uuid, uuid, text, text, uuid) to authenticated, service_role;

-- (2) registrar_compra = 0023 + IGV/costo según derecho a crédito fiscal (solo factura 01)
create or replace function registrar_compra(
  p_company_id uuid, p_supplier_id uuid, p_tipo_doc text, p_serie_numero text, p_fecha date,
  p_items jsonb, p_moneda text default 'PEN', p_condicion_pago text default 'contado',
  p_fecha_vencimiento date default null, p_afecta_inventario boolean default true,
  p_warehouse_id uuid default null, p_igv_rate numeric default 0.18
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id uuid; v_item jsonb; v_total numeric(12,2) := 0; v_gravado numeric(12,2) := 0;
  v_igv numeric(12,2) := 0; v_pid uuid; v_qty numeric; v_costo numeric;
  v_saldo numeric(12,2); v_estado text; v_existing uuid; v_credito boolean;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'La compra no tiene ítems'; end if;
  if p_igv_rate < 0 or p_igv_rate > 0.30 then raise exception 'Tasa de IGV inválida'; end if;
  if p_supplier_id is not null and not exists (
       select 1 from suppliers where id = p_supplier_id and company_id = p_company_id) then
    raise exception 'El proveedor no pertenece a la empresa';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_company_id::text || ':compra:' || coalesce(p_serie_numero,''), 0));
  if p_serie_numero is not null then
    select id into v_existing from purchases
      where company_id = p_company_id and coalesce(supplier_id::text,'') = coalesce(p_supplier_id::text,'')
        and tipo_doc = p_tipo_doc and serie_numero = p_serie_numero limit 1;
    if v_existing is not null then
      return jsonb_build_object('id', v_existing, 'reused', true);
    end if;
  end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'cantidad')::numeric; v_costo := (v_item->>'costo')::numeric;
    v_total := v_total + round(v_qty * v_costo, 2);
  end loop;

  -- FIX fiscal: SOLO la factura (01) da crédito fiscal de IGV. Boleta (03), recibo por
  -- honorarios (02) y otros (00) → todo es costo/gasto, IGV recuperable = 0.
  v_credito := (p_tipo_doc = '01');
  if v_credito then
    v_gravado := round(v_total / (1 + p_igv_rate), 2); v_igv := v_total - v_gravado;
  else
    v_gravado := v_total; v_igv := 0;
  end if;

  if p_condicion_pago = 'credito' then v_estado := 'pendiente'; v_saldo := v_total;
  else v_estado := 'pagado'; v_saldo := 0; end if;

  insert into purchases (company_id, supplier_id, tipo_doc, serie_numero, fecha, total,
    moneda, total_gravado, total_igv, condicion_pago, estado_pago, saldo, fecha_vencimiento,
    afecta_inventario, warehouse_id)
  values (p_company_id, p_supplier_id, p_tipo_doc, p_serie_numero, coalesce(p_fecha, current_date), v_total,
    p_moneda, v_gravado, v_igv, p_condicion_pago, v_estado, v_saldo, p_fecha_vencimiento,
    p_afecta_inventario, p_warehouse_id)
  returning id into v_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid := nullif(v_item->>'product_id','')::uuid;
    if v_pid is not null and not exists (select 1 from products where id = v_pid and company_id = p_company_id) then
      v_pid := null;
    end if;
    v_qty := (v_item->>'cantidad')::numeric; v_costo := (v_item->>'costo')::numeric;
    insert into purchase_items (purchase_id, product_id, descripcion, cantidad, costo, total)
      values (v_id, v_pid, v_item->>'descripcion', v_qty, v_costo, round(v_qty * v_costo, 2));
    if p_afecta_inventario and v_pid is not null
       and exists (select 1 from products where id = v_pid and controla_stock) then
      perform ajustar_stock(p_company_id, v_pid, p_warehouse_id, v_qty, 'ingreso', 'Compra ' || coalesce(p_serie_numero, ''));
      -- Costo NETO solo si hay crédito fiscal (factura); si no, el IGV forma parte del costo.
      update products set costo = case when v_credito then round(v_costo / (1 + p_igv_rate), 2) else round(v_costo, 2) end
        where id = v_pid;
    end if;
  end loop;

  return jsonb_build_object('id', v_id, 'total', v_total, 'total_gravado', v_gravado,
    'total_igv', v_igv, 'saldo', v_saldo, 'estado_pago', v_estado, 'reused', false);
end $$;
grant execute on function registrar_compra(uuid, uuid, text, text, date, jsonb, text, text, date, boolean, uuid, numeric)
  to authenticated, service_role;

-- (3) reporte_cuentas_por_cobrar: incluye créditos PENDIENTES ante SUNAT (deuda real);
--     excluye solo rechazado/anulado/baja_pendiente.
create or replace function reporte_cuentas_por_cobrar(p_company_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'numero', serie || '-' || lpad(correlativo::text,8,'0'),
      'cliente', receptor_denominacion, 'total', total, 'saldo', saldo,
      'vencimiento', fecha_vencimiento, 'estado_pago', estado_pago) order by fecha_vencimiento nulls last), '[]'::jsonb)
  from documents
  where company_id = p_company_id and company_id in (select auth_company_ids())
    and tipo_doc in ('01','03') and estado_pago <> 'pagado'
    and estado_sunat not in ('rechazado','anulado','baja_pendiente');
$$;

-- (4) Índice único de proveedores por (empresa, RUC) — evita duplicados que fragmentan CxP/PLE.
create unique index if not exists ux_suppliers_ruc on suppliers (company_id, ruc)
  where ruc is not null and ruc <> '';
