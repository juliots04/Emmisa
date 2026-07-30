-- ============================================================
-- Emmisa · 0023 Hardening (arreglos de la auditoría de backend 2026-07-22)
--   Cierra el CRÍTICO (forja de comprobante) + altas de seguridad, caja,
--   concurrencia e integridad. Aplicar DESPUÉS de 0022. Idempotente.
--   Nota: ejecutar en un proyecto de PRUEBA y validar una emisión antes de prod.
-- ============================================================

-- ===================================================================
-- BLOQUE A · Permisos / superficie de ataque
-- ===================================================================
-- M1: el rol anónimo (anon-key pública del front) no debe poder escribir NADA.
revoke insert, update, delete on all tables in schema public from anon;
-- M13: y no debe poder ejecutar funciones (RPC SECURITY DEFINER) sin sesión.
revoke execute on all functions in schema public from anon;
-- A1: nadie manipula la numeración SUNAT por la Data API (0016 solo revocó UPDATE;
--     DELETE+INSERT permitía resetear el correlativo). emitir_venta es SECURITY
--     DEFINER, así que sigue pudiendo insertar/actualizar series como owner.
revoke insert, update, delete on series from anon, authenticated;

-- ===================================================================
-- BLOQUE B · Anti-forja de comprobantes (CRÍTICO C1 + A16/A17/A22)
--   La simulación por RPC podía marcar 'aceptado' sin pasar por SUNAT cuando el
--   emisor real eran las credenciales GLOBALES (sin fila en emisor_credentials).
--   Solución: la simulación por RPC deja de ser invocable por el cliente
--   (solo service_role) y se blinda contra pisar comprobantes ya resueltos.
-- ===================================================================
create or replace function simular_emision(p_document_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_doc documents%rowtype; v_ruc text; v_num text; v_nombre text;
  v_estado text; v_hash text; v_ticket text; v_cdr text; v_qr text;
begin
  select * into v_doc from documents where id = p_document_id;
  if not found then raise exception 'Comprobante no encontrado'; end if;
  if v_doc.company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  -- A16/A22: nunca sobrescribir un comprobante ya resuelto o con ticket real.
  if v_doc.estado_sunat <> 'pendiente' then
    raise exception 'El comprobante ya está en estado % — no se puede simular', v_doc.estado_sunat;
  end if;
  if v_doc.sunat_ticket is not null and v_doc.sunat_ticket not like 'SIM-%' then
    raise exception 'El comprobante ya fue enviado a SUNAT (ticket real) — no se puede simular';
  end if;
  -- Anti-forja: si hay emisor real por empresa, no se simula.
  if exists (select 1 from emisor_credentials where company_id = v_doc.company_id and activo) then
    raise exception 'Esta empresa tiene un emisor real configurado: usa el motor de emisión';
  end if;

  select ruc into v_ruc from companies where id = v_doc.company_id;
  v_num    := v_doc.serie || '-' || lpad(v_doc.correlativo::text, 8, '0');
  v_nombre := case v_doc.tipo_doc when '01' then 'Factura' when '03' then 'Boleta'
                 when '07' then 'Nota de Crédito' when '08' then 'Nota de Débito' else 'Comprobante' end;
  v_hash   := left(replace(encode(convert_to(v_num || v_doc.total::text, 'UTF8'), 'base64'), E'\n', ''), 27) || '=';
  v_ticket := 'SIM-' || v_doc.serie || '-' || lpad(v_doc.correlativo::text, 8, '0');

  if coalesce(v_doc.receptor_num_doc, '') ~ '99$' then v_estado := 'rechazado';
  elsif coalesce(v_doc.receptor_num_doc, '') ~ '88$' and v_doc.sunat_ticket is null then v_estado := 'pendiente';
  else v_estado := 'aceptado'; end if;

  if v_estado = 'rechazado' then
    update documents set estado_sunat = 'rechazado',
      sunat_error = 'Error 2335: rechazado por SUNAT (SIMULADO)', hash = v_hash, sunat_ticket = v_ticket
      where id = p_document_id;
  elsif v_estado = 'pendiente' then
    update documents set estado_sunat = 'pendiente', sunat_ticket = v_ticket where id = p_document_id;
  else
    v_cdr := 'La ' || v_nombre || ' numero ' || v_num || ', ha sido aceptada';
    v_qr  := concat_ws('|', v_ruc, v_doc.tipo_doc, v_doc.serie, v_doc.correlativo,
                       round(v_doc.total_igv, 2), round(v_doc.total, 2), v_doc.fecha_emision,
                       coalesce(v_doc.receptor_tipo_doc, '-'), coalesce(v_doc.receptor_num_doc, '-'), v_hash);
    update documents set estado_sunat = 'aceptado', cdr = v_cdr, hash = v_hash,
      sunat_ticket = v_ticket, codigo_qr = v_qr, sunat_error = null where id = p_document_id;
  end if;

  return jsonb_build_object('estado', v_estado, 'hash', v_hash, 'ticket', v_ticket,
    'cdr', case when v_estado = 'aceptado' then v_cdr else null end,
    'mensaje', v_nombre || ' ' || v_num || ' — ' || upper(v_estado) || ' (SIMULADO)', 'simulado', true);
end $$;
-- C1: la simulación deja de ser invocable por el cliente (solo el servidor).
revoke execute on function simular_emision(uuid) from anon, authenticated;
grant execute on function simular_emision(uuid) to service_role;

-- ===================================================================
-- BLOQUE C · Abonos: validar la caja y no aceptar sobre-abonos
--   (A10/A12/A14 sesión de caja de la empresa y abierta · A15/M6 clamp al saldo)
-- ===================================================================
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
  -- A12/A14: la caja indicada debe ser de ESTA empresa y estar ABIERTA.
  if p_cash_session_id is not null then
    perform 1 from cash_sessions where id = p_cash_session_id and company_id = p_company_id and estado = 'abierta';
    if not found then raise exception 'La caja indicada no es de esta empresa o no está abierta'; end if;
  end if;

  if p_document_id is not null then
    v_tipo := 'cobro';
    select saldo into v_saldo from documents where id = p_document_id and company_id = p_company_id;
    if not found then raise exception 'Comprobante no encontrado'; end if;
    -- A15/M6: solo se aplica (y registra) hasta el saldo pendiente; el exceso no se cobra.
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
    select saldo into v_saldo from purchases where id = p_purchase_id and company_id = p_company_id;
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

-- ===================================================================
-- BLOQUE D · Compras: idempotencia, proveedor de la empresa, IGV acotado
--   (A11 dedup por documento · M7 supplier valida empresa · M8 rango IGV · M17 unique)
-- ===================================================================
-- M17/A11: no dos compras con el mismo documento del mismo proveedor.
create unique index if not exists ux_purchases_doc
  on purchases (company_id, supplier_id, tipo_doc, serie_numero)
  where serie_numero is not null;

create or replace function registrar_compra(
  p_company_id uuid, p_supplier_id uuid, p_tipo_doc text, p_serie_numero text, p_fecha date,
  p_items jsonb, p_moneda text default 'PEN', p_condicion_pago text default 'contado',
  p_fecha_vencimiento date default null, p_afecta_inventario boolean default true,
  p_warehouse_id uuid default null, p_igv_rate numeric default 0.18
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id uuid; v_item jsonb; v_total numeric(12,2) := 0; v_gravado numeric(12,2) := 0;
  v_igv numeric(12,2) := 0; v_line numeric(12,2); v_pid uuid; v_qty numeric; v_costo numeric;
  v_saldo numeric(12,2); v_estado text; v_existing uuid;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'La compra no tiene ítems'; end if;
  -- M8: tasa de IGV en rango razonable (evita crédito fiscal falseado con 0 o valores absurdos).
  if p_igv_rate < 0 or p_igv_rate > 0.30 then raise exception 'Tasa de IGV inválida'; end if;
  -- M7: el proveedor (si se indica) debe ser de la empresa.
  if p_supplier_id is not null and not exists (
       select 1 from suppliers where id = p_supplier_id and company_id = p_company_id) then
    raise exception 'El proveedor no pertenece a la empresa';
  end if;
  -- A11: idempotencia — si ya existe la compra de ese documento, se devuelve (no se duplica).
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
  v_gravado := round(v_total / (1 + p_igv_rate), 2);
  v_igv := v_total - v_gravado;
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
      update products set costo = round(v_costo / (1 + p_igv_rate), 2) where id = v_pid;
    end if;
  end loop;

  return jsonb_build_object('id', v_id, 'total', v_total, 'total_gravado', v_gravado,
    'total_igv', v_igv, 'saldo', v_saldo, 'estado_pago', v_estado, 'reused', false);
end $$;
grant execute on function registrar_compra(uuid, uuid, text, text, date, jsonb, text, text, date, boolean, uuid, numeric)
  to authenticated, service_role;

-- ===================================================================
-- BLOQUE E · Anulación: lock anti-doble y conservar el historial de pagos
--   (A6 pg_advisory_xact_lock · A9 NO borrar payments, se conservan como rastro)
-- ===================================================================
create or replace function anular_documento(
  p_company_id uuid, p_document_id uuid, p_motivo text default 'Anulación'
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_doc documents%rowtype; v_it record; v_wh uuid; v_efectivo numeric(12,2);
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  -- A6: serializa anulaciones concurrentes del mismo documento (evita doble reversión).
  perform pg_advisory_xact_lock(hashtextextended('anular:' || p_document_id::text, 0));
  select * into v_doc from documents where id = p_document_id and company_id = p_company_id;
  if not found then raise exception 'Comprobante no encontrado'; end if;
  if v_doc.estado_sunat = 'anulado' then
    return jsonb_build_object('id', v_doc.id, 'estado_sunat', 'anulado', 'ya', true);
  end if;

  -- 1) Stock: solo ventas (01/03); las notas no descontaron stock.
  if v_doc.tipo_doc in ('01','03') then
    for v_it in select * from document_items where document_id = p_document_id and product_id is not null loop
      if exists (select 1 from products where id = v_it.product_id and controla_stock) then
        select warehouse_id into v_wh from stock where product_id = v_it.product_id order by cantidad desc limit 1;
        if v_wh is null then select id into v_wh from warehouses where company_id = p_company_id order by created_at limit 1; end if;
        if v_wh is not null then
          insert into stock (product_id, warehouse_id, cantidad) values (v_it.product_id, v_wh, 0)
            on conflict (product_id, warehouse_id) do nothing;
          update stock set cantidad = cantidad + v_it.cantidad where product_id = v_it.product_id and warehouse_id = v_wh;
          insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
            values (p_company_id, v_it.product_id, v_wh, 'ingreso', v_it.cantidad,
                    'Anulación ' || v_doc.serie || '-' || lpad(v_doc.correlativo::text,8,'0'));
        end if;
      end if;
    end loop;
  end if;

  -- 2) Caja: retiro compensatorio del efectivo cobrado (solo si la sesión sigue abierta).
  select coalesce(sum(monto),0) into v_efectivo from cash_movements
    where document_id = p_document_id and tipo = 'ingreso';
  if v_efectivo > 0 and v_doc.cash_session_id is not null
     and exists (select 1 from cash_sessions where id = v_doc.cash_session_id and estado = 'abierta') then
    insert into cash_movements (cash_session_id, tipo, monto, motivo, document_id)
      values (v_doc.cash_session_id, 'retiro', v_efectivo, 'Anulación ' || v_doc.serie, p_document_id);
  end if;

  -- 3) CxC: se cierra el saldo pero se CONSERVAN los payments (rastro contable — A9).
  update documents set estado_sunat = 'anulado', sunat_error = p_motivo, saldo = 0 where id = p_document_id;
  return jsonb_build_object('id', p_document_id, 'estado_sunat', 'anulado', 'ya', false);
end $$;
grant execute on function anular_documento(uuid, uuid, text) to authenticated, service_role;

-- ===================================================================
-- BLOQUE F · emitir_venta: total no negativo + ICBPER filtra por empresa
--   (A5 clamp total>=0 · M3 subconsulta ICBPER con company_id)
--   (A3 prorrateo del descuento global y A4 ISC-en-base quedan para una revisión
--    dedicada con validación de XML; aquí solo se evita el total negativo.)
-- ===================================================================
create or replace function emitir_venta(
  p_company_id uuid, p_tipo_doc text, p_serie text, p_cliente jsonb, p_items jsonb,
  p_forma_pago text default 'efectivo', p_monto_recibido numeric default null, p_vuelto numeric default null,
  p_cash_session_id uuid default null, p_idempotency_key text default null, p_igv_rate numeric default 0.18,
  p_moneda text default 'PEN', p_tipo_cambio numeric default 1, p_condicion_pago text default 'contado',
  p_fecha_vencimiento date default null, p_establishment_id uuid default null,
  p_icbper_rate numeric default 0.50, p_descuento_global numeric default 0
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_user_id uuid := auth.uid(); v_correlativo int; v_doc_id uuid; v_customer_id uuid;
  v_existing documents%rowtype; v_item jsonb; v_pid uuid; v_qty numeric; v_price numeric; v_desc numeric;
  v_code text; v_unidad text; v_line_total numeric(12,2); v_base numeric(12,2); v_ligv numeric(12,2);
  v_bucket text; v_icb numeric(12,2); v_isc numeric(12,2); v_total numeric(12,2) := 0;
  v_gravado numeric(12,2) := 0; v_igv numeric(12,2) := 0; v_exonerado numeric(12,2) := 0;
  v_inafecto numeric(12,2) := 0; v_gratuito numeric(12,2) := 0; v_exportacion numeric(12,2) := 0;
  v_icbper numeric(12,2) := 0; v_isctot numeric(12,2) := 0; v_wh uuid; v_numero text; v_attempts int := 0;
  v_estado_pago text; v_saldo numeric(12,2);
  v_r_tipo text := coalesce(nullif(p_cliente->>'tipo_doc',''), '0');
  v_r_num text := nullif(p_cliente->>'num_doc','');
  v_r_den text := coalesce(nullif(p_cliente->>'denominacion',''), 'Cliente varios');
  v_r_dir text := nullif(p_cliente->>'direccion','');
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'La venta no tiene ítems'; end if;
  if p_tipo_doc = '01' then
    if v_r_tipo <> '6' or v_r_num is null or v_r_num !~ '^\d{11}$' then
      raise exception 'Una factura (01) requiere un cliente con RUC válido de 11 dígitos';
    end if;
  end if;

  if p_idempotency_key is not null then
    perform pg_advisory_xact_lock(hashtextextended(p_company_id::text || ':' || p_idempotency_key, 0));
    select * into v_existing from documents where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
    if found then
      return jsonb_build_object('id', v_existing.id, 'serie', v_existing.serie, 'correlativo', v_existing.correlativo,
        'tipo_doc', v_existing.tipo_doc, 'total', v_existing.total, 'estado_sunat', v_existing.estado_sunat, 'reused', true);
    end if;
  end if;
  if p_cash_session_id is not null then
    perform 1 from cash_sessions where id = p_cash_session_id and company_id = p_company_id and estado = 'abierta';
    if not found then raise exception 'No hay una caja abierta para registrar la venta'; end if;
  end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid   := nullif(v_item->>'product_id','')::uuid;
    v_qty   := (v_item->>'cantidad')::numeric;
    v_price := (v_item->>'precio_unitario')::numeric;
    v_desc  := coalesce((v_item->>'descuento')::numeric, 0);
    v_code  := coalesce(nullif(v_item->>'tipo_afectacion',''),
                        (select tipo_afectacion from products where id = v_pid and company_id = p_company_id), '10');
    v_line_total := round(v_qty * v_price - v_desc, 2);
    select base, igv, bucket into v_base, v_ligv, v_bucket from _clasificar_afectacion(v_code, v_line_total, p_igv_rate);
    if v_bucket = 'gravado' then v_gravado := v_gravado + v_base; v_igv := v_igv + v_ligv; v_total := v_total + v_line_total;
    elsif v_bucket = 'exonerado' then v_exonerado := v_exonerado + v_line_total; v_total := v_total + v_line_total;
    elsif v_bucket = 'inafecto' then v_inafecto := v_inafecto + v_line_total; v_total := v_total + v_line_total;
    elsif v_bucket = 'exportacion' then v_exportacion := v_exportacion + v_line_total; v_total := v_total + v_line_total;
    else v_gratuito := v_gratuito + v_line_total; end if;
    -- M3: la subconsulta de ICBPER también filtra por empresa (no leer producto ajeno).
    v_icb := case when coalesce((v_item->>'icbper')::boolean,
                    (select icbper from products where id = v_pid and company_id = p_company_id), false)
                  then round(v_qty * p_icbper_rate, 2) else 0 end;
    v_isc := coalesce((v_item->>'isc')::numeric, 0);
    v_icbper := v_icbper + v_icb; v_isctot := v_isctot + v_isc; v_total := v_total + v_icb + v_isc;
  end loop;

  -- A5: el total nunca queda negativo por un descuento global excesivo.
  v_total := greatest(round(v_total - coalesce(p_descuento_global, 0), 2), 0);

  v_customer_id := nullif(p_cliente->>'customer_id', '')::uuid;
  if v_customer_id is not null and not exists (select 1 from customers where id = v_customer_id and company_id = p_company_id) then
    v_customer_id := null;
  end if;
  if p_condicion_pago = 'credito' then v_estado_pago := 'pendiente'; v_saldo := v_total;
  else v_estado_pago := 'pagado'; v_saldo := 0; end if;

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
        total_gratuito, total_exportacion, total_icbper, total_isc, descuento_global, total,
        estado_sunat, user_id, cash_session_id, forma_pago, monto_recibido, vuelto,
        condicion_pago, estado_pago, saldo, fecha_vencimiento,
        receptor_tipo_doc, receptor_num_doc, receptor_denominacion, receptor_direccion, idempotency_key
      ) values (
        p_company_id, p_establishment_id, v_customer_id, p_tipo_doc, p_serie, v_correlativo,
        p_moneda, p_tipo_cambio, v_gravado, v_igv, v_exonerado, v_inafecto,
        v_gratuito, v_exportacion, v_icbper, v_isctot, coalesce(p_descuento_global,0), v_total,
        'pendiente', v_user_id, p_cash_session_id, p_forma_pago, p_monto_recibido, p_vuelto,
        p_condicion_pago, v_estado_pago, v_saldo, p_fecha_vencimiento,
        v_r_tipo, v_r_num, v_r_den, v_r_dir, coalesce(p_idempotency_key, gen_random_uuid()::text)
      ) returning id into v_doc_id;
      exit;
    exception when unique_violation then
      if p_idempotency_key is not null then
        select * into v_existing from documents where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
        if found then
          return jsonb_build_object('id', v_existing.id, 'serie', v_existing.serie, 'correlativo', v_existing.correlativo,
            'tipo_doc', v_existing.tipo_doc, 'total', v_existing.total, 'estado_sunat', v_existing.estado_sunat, 'reused', true);
        end if;
      end if;
      if v_attempts >= 5 then raise; end if;
    end;
  end loop;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid := nullif(v_item->>'product_id','')::uuid;
    if v_pid is not null and not exists (select 1 from products where id = v_pid and company_id = p_company_id) then v_pid := null; end if;
    v_qty := (v_item->>'cantidad')::numeric; v_price := (v_item->>'precio_unitario')::numeric;
    v_desc := coalesce((v_item->>'descuento')::numeric, 0);
    v_code := coalesce(nullif(v_item->>'tipo_afectacion',''), (select tipo_afectacion from products where id = v_pid), '10');
    v_unidad := coalesce(nullif(v_item->>'unidad_medida',''), (select unidad_medida from products where id = v_pid), 'NIU');
    v_line_total := round(v_qty * v_price - v_desc, 2);
    select base, igv, bucket into v_base, v_ligv, v_bucket from _clasificar_afectacion(v_code, v_line_total, p_igv_rate);
    v_icb := case when coalesce((v_item->>'icbper')::boolean, (select icbper from products where id = v_pid and company_id = p_company_id), false)
                  then round(v_qty * p_icbper_rate, 2) else 0 end;
    v_isc := coalesce((v_item->>'isc')::numeric, 0);
    insert into document_items (
      document_id, product_id, descripcion, cantidad, valor_unitario,
      precio_unitario, igv, total, tipo_afectacion, unidad_medida, descuento, icbper, isc
    ) values (
      v_doc_id, v_pid, v_item->>'descripcion', v_qty,
      case when v_qty <> 0 then round(v_base / v_qty, 2) else 0 end,
      v_price, v_ligv, v_line_total, v_code, v_unidad, v_desc, v_icb, v_isc
    );
    if v_pid is not null and exists (select 1 from products where id = v_pid and controla_stock) then
      select warehouse_id into v_wh from stock where product_id = v_pid order by cantidad desc limit 1 for update;
      if v_wh is not null then
        update stock set cantidad = cantidad - v_qty where product_id = v_pid and warehouse_id = v_wh;
        insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
          values (p_company_id, v_pid, v_wh, 'salida', v_qty, 'Venta ' || v_numero);
      end if;
    end if;
  end loop;

  if p_condicion_pago = 'contado' and v_total > 0 then
    insert into payments (company_id, tipo, document_id, cash_session_id, medio, monto, fecha)
      values (p_company_id, 'cobro', v_doc_id, p_cash_session_id, p_forma_pago, v_total, current_date);
    if p_cash_session_id is not null and p_forma_pago = 'efectivo' then
      insert into cash_movements (cash_session_id, tipo, monto, motivo, document_id)
        values (p_cash_session_id, 'ingreso', v_total, 'Venta ' || v_numero, v_doc_id);
    end if;
  end if;

  return jsonb_build_object('id', v_doc_id, 'serie', p_serie, 'correlativo', v_correlativo, 'numero', v_numero,
    'tipo_doc', p_tipo_doc, 'total_gravado', v_gravado, 'total_igv', v_igv, 'total_exonerado', v_exonerado,
    'total_inafecto', v_inafecto, 'total_exportacion', v_exportacion, 'total_gratuito', v_gratuito,
    'total_icbper', v_icbper, 'total_isc', v_isctot, 'total', v_total, 'estado_sunat', 'pendiente', 'reused', false);
end $$;
grant execute on function emitir_venta(uuid, text, text, jsonb, jsonb, text, numeric, numeric, uuid, text, numeric, text, numeric, text, date, uuid, numeric, numeric)
  to authenticated, service_role;

-- ===================================================================
-- BLOQUE G · Notas: afectación real (no forzar gravado) + autor (user_id)
--   (A7 copia con la afectación del original · A8 export/gratuitas sin IGV · M5 user_id)
-- ===================================================================
create or replace function emitir_nota(
  p_company_id uuid, p_ref_document_id uuid, p_tipo_nota text, p_motivo_codigo text, p_motivo_desc text,
  p_items jsonb default null, p_idempotency_key text default null, p_igv_rate numeric default 0.18
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_ref documents%rowtype; v_serie text; v_correlativo int; v_doc_id uuid; v_existing documents%rowtype;
  v_item jsonb; v_qty numeric; v_price numeric; v_afect text; v_line_total numeric(12,2);
  v_line_base numeric(12,2); v_line_igv numeric(12,2); v_total numeric(12,2) := 0;
  v_gravado numeric(12,2) := 0; v_igv numeric(12,2) := 0; v_exonerado numeric(12,2) := 0;
  v_inafecto numeric(12,2) := 0; v_exportacion numeric(12,2) := 0; v_attempts int := 0;
  v_numero_ref text; v_afect_copia text; v_uid uuid := auth.uid();
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_tipo_nota not in ('07','08') then raise exception 'Tipo de nota inválido (use 07 o 08)'; end if;
  select * into v_ref from documents where id = p_ref_document_id and company_id = p_company_id;
  if not found then raise exception 'Comprobante original no encontrado'; end if;
  if v_ref.tipo_doc not in ('01','03') then raise exception 'Solo se emiten notas sobre facturas (01) o boletas (03)'; end if;

  if p_tipo_nota = '07' then v_serie := case when v_ref.tipo_doc = '01' then 'FC01' else 'BC01' end;
  else v_serie := case when v_ref.tipo_doc = '01' then 'FD01' else 'BD01' end; end if;
  v_numero_ref := v_ref.serie || '-' || lpad(v_ref.correlativo::text, 8, '0');

  if p_idempotency_key is not null then
    perform pg_advisory_xact_lock(hashtextextended(p_company_id::text || ':' || p_idempotency_key, 0));
    select * into v_existing from documents where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
    if found then
      return jsonb_build_object('id', v_existing.id, 'serie', v_existing.serie, 'correlativo', v_existing.correlativo,
        'tipo_doc', v_existing.tipo_doc, 'total', v_existing.total, 'estado_sunat', v_existing.estado_sunat, 'reused', true);
    end if;
  end if;

  if p_items is not null and jsonb_array_length(p_items) > 0 then
    for v_item in select * from jsonb_array_elements(p_items) loop
      v_qty := (v_item->>'cantidad')::numeric; v_price := (v_item->>'precio_unitario')::numeric;
      v_afect := coalesce(nullif(v_item->>'tipo_afectacion',''), '10');
      v_line_total := round(v_qty * v_price, 2);
      if v_afect = '10' then
        v_line_base := round(v_line_total / (1 + p_igv_rate), 2); v_line_igv := v_line_total - v_line_base;
        v_gravado := v_gravado + v_line_base; v_igv := v_igv + v_line_igv;
      elsif v_afect = '20' then v_exonerado := v_exonerado + v_line_total;
      elsif v_afect = '30' then v_inafecto := v_inafecto + v_line_total;
      elsif v_afect = '40' then v_exportacion := v_exportacion + v_line_total;  -- A8: exportación 0%
      else v_exonerado := v_exonerado + v_line_total;  -- A8: gratuitas/otras sin IGV (no forzar gravado)
      end if;
      v_total := v_total + v_line_total;
    end loop;
  else
    -- A7: copia total con las mismas bases/afectación del comprobante original.
    v_gravado := v_ref.total_gravado; v_igv := v_ref.total_igv;
    v_exonerado := coalesce(v_ref.total_exonerado, 0); v_inafecto := coalesce(v_ref.total_inafecto, 0);
    v_exportacion := coalesce(v_ref.total_exportacion, 0); v_total := v_ref.total;
  end if;

  -- Afectación representativa de la línea "copia total" (no forzar '10').
  v_afect_copia := case when v_gravado > 0 then '10' when v_exonerado > 0 then '20'
                        when v_inafecto > 0 then '30' when v_exportacion > 0 then '40' else '10' end;

  loop
    v_attempts := v_attempts + 1;
    insert into series (company_id, tipo_doc, serie, correlativo)
      values (p_company_id, p_tipo_nota, v_serie, 0) on conflict (company_id, tipo_doc, serie) do nothing;
    update series set correlativo = correlativo + 1
      where company_id = p_company_id and tipo_doc = p_tipo_nota and serie = v_serie returning correlativo into v_correlativo;
    begin
      insert into documents (
        company_id, establishment_id, customer_id, tipo_doc, serie, correlativo,
        moneda, tipo_cambio, total_gravado, total_igv, total_exonerado, total_inafecto, total_exportacion,
        total, estado_sunat, user_id, ref_document_id, motivo_codigo, motivo_desc,
        receptor_tipo_doc, receptor_num_doc, receptor_denominacion, receptor_direccion, idempotency_key
      ) values (
        p_company_id, v_ref.establishment_id, v_ref.customer_id, p_tipo_nota, v_serie, v_correlativo,
        v_ref.moneda, coalesce(v_ref.tipo_cambio,1), v_gravado, v_igv, v_exonerado, v_inafecto, v_exportacion,
        v_total, 'pendiente', v_uid, p_ref_document_id, p_motivo_codigo, p_motivo_desc,
        v_ref.receptor_tipo_doc, v_ref.receptor_num_doc, v_ref.receptor_denominacion, v_ref.receptor_direccion,
        coalesce(p_idempotency_key, gen_random_uuid()::text)
      ) returning id into v_doc_id;
      exit;
    exception when unique_violation then
      if p_idempotency_key is not null then
        select * into v_existing from documents where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
        if found then
          return jsonb_build_object('id', v_existing.id, 'serie', v_existing.serie, 'correlativo', v_existing.correlativo,
            'tipo_doc', v_existing.tipo_doc, 'total', v_existing.total, 'estado_sunat', v_existing.estado_sunat, 'reused', true);
        end if;
      end if;
      if v_attempts >= 5 then raise; end if;
    end;
  end loop;

  if p_items is not null and jsonb_array_length(p_items) > 0 then
    for v_item in select * from jsonb_array_elements(p_items) loop
      v_qty := (v_item->>'cantidad')::numeric; v_price := (v_item->>'precio_unitario')::numeric;
      v_afect := coalesce(nullif(v_item->>'tipo_afectacion',''), '10');
      v_line_total := round(v_qty * v_price, 2);
      if v_afect = '10' then
        v_line_base := round(v_line_total / (1 + p_igv_rate), 2); v_line_igv := v_line_total - v_line_base;
      else v_line_base := v_line_total; v_line_igv := 0; end if;
      insert into document_items (document_id, product_id, descripcion, cantidad,
        valor_unitario, precio_unitario, igv, total, tipo_afectacion, unidad_medida)
      values (v_doc_id, nullif(v_item->>'product_id','')::uuid, v_item->>'descripcion', v_qty,
        case when v_qty <> 0 then round(v_line_base / v_qty, 2) else 0 end,
        v_price, v_line_igv, v_line_total, v_afect, coalesce(nullif(v_item->>'unidad_medida',''),'NIU'));
    end loop;
  else
    insert into document_items (document_id, descripcion, cantidad, valor_unitario, precio_unitario, igv, total, tipo_afectacion)
    values (v_doc_id,
      (case when p_tipo_nota='07' then 'Nota de crédito' else 'Nota de débito' end)
        || ' (' || coalesce(p_motivo_codigo,'') || ' · ' || coalesce(p_motivo_desc,'') || ') sobre ' || v_numero_ref,
      1, v_gravado + v_exonerado + v_inafecto + v_exportacion, v_total, v_igv, v_total, v_afect_copia);
  end if;

  return jsonb_build_object('id', v_doc_id, 'serie', v_serie, 'correlativo', v_correlativo,
    'tipo_doc', p_tipo_nota, 'total_gravado', v_gravado, 'total_igv', v_igv, 'total', v_total,
    'estado_sunat', 'pendiente', 'reused', false);
end $$;
grant execute on function emitir_nota(uuid, uuid, text, text, text, jsonb, text, numeric) to authenticated, service_role;

-- ===================================================================
-- BLOQUE H · Constraints varios
-- ===================================================================
-- B3: estado de comunicaciones acotado.
alter table sunat_comunicaciones drop constraint if exists chk_com_estado;
alter table sunat_comunicaciones add constraint chk_com_estado
  check (estado in ('pendiente','aceptado','rechazado'));
