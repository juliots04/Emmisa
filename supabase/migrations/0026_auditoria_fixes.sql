-- ============================================================
-- Emmisa · 0026 Fixes de auditoría (rebasado sobre 0023/0025_roles_rls)
--   NO toca simular_emision ni registrar_abono: 0023 ya los endureció
--   (simular revocado de authenticated; abono con clamp least()). Aquí SOLO:
--     (#6)   document_items.warehouse_id → la venta persiste el almacén de cada
--            línea y la reversión reingresa al MISMO almacén.
--     (notas#1) emitir_nota exige que el comprobante afectado esté ACEPTADO.
--     (notas#2) la Nota de Crédito revierte stock (motivo 01/06/07) y reduce la
--               CxC del original (conservando payments como rastro — A9 de 0023).
--     (notas#4) el fallback de NC copia las líneas reales del original (cuadra).
--     (#734) estado 'baja_pendiente': anular un ACEPTADO no revierte ni marca
--            'anulado' hasta el CDR de la baja (confirmar_baja/revertir_baja).
--   Conserva TODO el hardening de 0023 (total>=0, ICBPER por empresa, unidad
--   fallback, advisory lock, payments como rastro, afectación real en notas).
-- Aplicar DESPUÉS de 0025_roles_rls. Supabase → SQL Editor → Run. Idempotente.
-- ============================================================

-- (1) Almacén por línea + estado 'baja_pendiente' en el CHECK
alter table document_items add column if not exists warehouse_id uuid references warehouses(id);

alter table documents drop constraint if exists chk_doc_estado_sunat;
alter table documents add constraint chk_doc_estado_sunat
  check (estado_sunat in ('pendiente','aceptado','rechazado','anulado','baja_pendiente'));

-- (2) Helper de reversión operativa (stock + caja), reutilizado por anular_documento
--     y confirmar_baja. Usa el almacén persistido; CONSERVA payments (rastro A9) y
--     solo cierra el saldo (no borra pagos).
create or replace function _revertir_operacion(p_company_id uuid, p_document_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_doc documents%rowtype; v_it record; v_wh uuid; v_efectivo numeric(12,2);
begin
  select * into v_doc from documents where id = p_document_id;
  if not found then return; end if;

  if v_doc.tipo_doc in ('01','03') then
    for v_it in select * from document_items where document_id = p_document_id and product_id is not null loop
      if exists (select 1 from products where id = v_it.product_id and controla_stock) then
        v_wh := v_it.warehouse_id;
        if v_wh is null then select warehouse_id into v_wh from stock where product_id = v_it.product_id order by cantidad desc limit 1; end if;
        if v_wh is null then select id into v_wh from warehouses where company_id = p_company_id order by created_at limit 1; end if;
        if v_wh is not null then
          insert into stock (product_id, warehouse_id, cantidad) values (v_it.product_id, v_wh, 0)
            on conflict (product_id, warehouse_id) do nothing;
          update stock set cantidad = cantidad + v_it.cantidad where product_id = v_it.product_id and warehouse_id = v_wh;
          insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
            values (p_company_id, v_it.product_id, v_wh, 'ingreso', v_it.cantidad,
                    p_motivo || ' ' || v_doc.serie || '-' || lpad(v_doc.correlativo::text,8,'0'));
        end if;
      end if;
    end loop;
  end if;

  select coalesce(sum(monto),0) into v_efectivo from cash_movements
    where document_id = p_document_id and tipo = 'ingreso';
  if v_efectivo > 0 and v_doc.cash_session_id is not null
     and exists (select 1 from cash_sessions where id = v_doc.cash_session_id and estado = 'abierta') then
    insert into cash_movements (cash_session_id, tipo, monto, motivo, document_id)
      values (v_doc.cash_session_id, 'retiro', v_efectivo, p_motivo || ' ' || v_doc.serie, p_document_id);
  end if;

  update documents set saldo = 0 where id = p_document_id;  -- CONSERVA payments (A9)
end $$;

-- (3) emitir_venta = versión 0023 + PERSISTE warehouse_id por línea
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
    v_icb := case when coalesce((v_item->>'icbper')::boolean,
                    (select icbper from products where id = v_pid and company_id = p_company_id), false)
                  then round(v_qty * p_icbper_rate, 2) else 0 end;
    v_isc := coalesce((v_item->>'isc')::numeric, 0);
    v_icbper := v_icbper + v_icb; v_isctot := v_isctot + v_isc; v_total := v_total + v_icb + v_isc;
  end loop;

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
    -- #6: resolver el almacén ANTES del insert (mismo criterio que la baja de stock) y persistirlo.
    v_wh := null;
    if v_pid is not null and exists (select 1 from products where id = v_pid and controla_stock) then
      select warehouse_id into v_wh from stock where product_id = v_pid order by cantidad desc limit 1 for update;
    end if;
    insert into document_items (
      document_id, product_id, descripcion, cantidad, valor_unitario,
      precio_unitario, igv, total, tipo_afectacion, unidad_medida, descuento, icbper, isc, warehouse_id
    ) values (
      v_doc_id, v_pid, v_item->>'descripcion', v_qty,
      case when v_qty <> 0 then round(v_base / v_qty, 2) else 0 end,
      v_price, v_ligv, v_line_total, v_code, v_unidad, v_desc, v_icb, v_isc, v_wh
    );
    if v_wh is not null then
      update stock set cantidad = cantidad - v_qty where product_id = v_pid and warehouse_id = v_wh;
      insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
        values (p_company_id, v_pid, v_wh, 'salida', v_qty, 'Venta ' || v_numero);
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

-- (4) emitir_nota = versión 0023 + guard ACEPTADO + fallback copia líneas reales + reversión NC
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
  v_numero_ref text; v_uid uuid := auth.uid(); v_it record; v_wh uuid;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_tipo_nota not in ('07','08') then raise exception 'Tipo de nota inválido (use 07 o 08)'; end if;
  select * into v_ref from documents where id = p_ref_document_id and company_id = p_company_id;
  if not found then raise exception 'Comprobante original no encontrado'; end if;
  if v_ref.tipo_doc not in ('01','03') then raise exception 'Solo se emiten notas sobre facturas (01) o boletas (03)'; end if;
  -- notas#1: la nota solo procede sobre comprobantes ACEPTADOS por SUNAT.
  if v_ref.estado_sunat <> 'aceptado' then
    raise exception 'Solo se emiten notas sobre comprobantes ACEPTADOS (estado actual: %)', coalesce(v_ref.estado_sunat,'desconocido');
  end if;

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
      elsif v_afect = '40' then v_exportacion := v_exportacion + v_line_total;
      else v_exonerado := v_exonerado + v_line_total;
      end if;
      v_total := v_total + v_line_total;
    end loop;
  else
    v_gravado := v_ref.total_gravado; v_igv := v_ref.total_igv;
    v_exonerado := coalesce(v_ref.total_exonerado, 0); v_inafecto := coalesce(v_ref.total_inafecto, 0);
    v_exportacion := coalesce(v_ref.total_exportacion, 0); v_total := v_ref.total;
  end if;

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
    -- notas#4: copiar las LÍNEAS reales del original (afectación/montos correctos → cuadra).
    insert into document_items (document_id, product_id, descripcion, cantidad,
      valor_unitario, precio_unitario, igv, total, tipo_afectacion, unidad_medida)
    select v_doc_id, di.product_id, di.descripcion, di.cantidad,
      di.valor_unitario, di.precio_unitario, di.igv, di.total,
      coalesce(nullif(di.tipo_afectacion,''),'10'), coalesce(nullif(di.unidad_medida,''),'NIU')
    from document_items di where di.document_id = p_ref_document_id;
  end if;

  -- notas#2: efecto operativo de la Nota de Crédito (07): reduce CxC del original y,
  -- para anulación/devolución (01/06/07), restaura stock (conserva payments — A9).
  if p_tipo_nota = '07' then
    update documents set saldo = greatest(coalesce(saldo,0) - v_total, 0),
      estado_pago = case when greatest(coalesce(saldo,0) - v_total, 0) <= 0 then 'pagado' else 'parcial' end
      where id = p_ref_document_id;
    if p_motivo_codigo in ('01','06','07') then
      for v_it in select * from document_items
        where document_id = case when p_motivo_codigo = '07' then v_doc_id else p_ref_document_id end
          and product_id is not null loop
        if exists (select 1 from products where id = v_it.product_id and controla_stock) then
          v_wh := v_it.warehouse_id;
          if v_wh is null then select warehouse_id into v_wh from stock where product_id = v_it.product_id order by cantidad desc limit 1; end if;
          if v_wh is null then select id into v_wh from warehouses where company_id = p_company_id order by created_at limit 1; end if;
          if v_wh is not null then
            insert into stock (product_id, warehouse_id, cantidad) values (v_it.product_id, v_wh, 0)
              on conflict (product_id, warehouse_id) do nothing;
            update stock set cantidad = cantidad + v_it.cantidad where product_id = v_it.product_id and warehouse_id = v_wh;
            insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
              values (p_company_id, v_it.product_id, v_wh, 'ingreso', v_it.cantidad,
                      'NC ' || v_serie || '-' || lpad(v_correlativo::text,8,'0'));
          end if;
        end if;
      end loop;
    end if;
  end if;

  return jsonb_build_object('id', v_doc_id, 'serie', v_serie, 'correlativo', v_correlativo,
    'tipo_doc', p_tipo_nota, 'total_gravado', v_gravado, 'total_igv', v_igv, 'total', v_total,
    'estado_sunat', 'pendiente', 'reused', false);
end $$;
grant execute on function emitir_nota(uuid, uuid, text, text, text, jsonb, text, numeric) to authenticated, service_role;

-- (5) anular_documento = versión 0023 + ciclo 'baja_pendiente' + guarda anti-doble-reversión
create or replace function anular_documento(p_company_id uuid, p_document_id uuid, p_motivo text default 'Anulación')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_doc documents%rowtype;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('anular:' || p_document_id::text, 0));
  select * into v_doc from documents where id = p_document_id and company_id = p_company_id;
  if not found then raise exception 'Comprobante no encontrado'; end if;
  if v_doc.estado_sunat in ('anulado','baja_pendiente') then
    return jsonb_build_object('id', v_doc.id, 'estado_sunat', v_doc.estado_sunat, 'ya', true);
  end if;
  -- Evita DOBLE reversión: si ya hay NC de anulación/devolución total (07, motivo 01/06).
  if exists (
    select 1 from documents where ref_document_id = p_document_id and tipo_doc = '07'
      and coalesce(motivo_codigo, '') in ('01','06') and estado_sunat in ('aceptado','pendiente','baja_pendiente')
  ) then
    raise exception 'Este comprobante ya tiene una Nota de Crédito de anulación/devolución total; no procede la baja.';
  end if;

  if v_doc.estado_sunat = 'aceptado' then
    -- Requiere comunicación formal (RA/RC). NO se revierte hasta el CDR (confirmar_baja).
    update documents set estado_sunat = 'baja_pendiente', sunat_error = p_motivo where id = p_document_id;
    return jsonb_build_object('id', p_document_id, 'estado_sunat', 'baja_pendiente', 'requiere_baja', true, 'ya', false);
  else
    perform _revertir_operacion(p_company_id, p_document_id, 'Anulación');
    update documents set estado_sunat = 'anulado', sunat_error = p_motivo where id = p_document_id;
    return jsonb_build_object('id', p_document_id, 'estado_sunat', 'anulado', 'requiere_baja', false, 'ya', false);
  end if;
end $$;
grant execute on function anular_documento(uuid, uuid, text) to authenticated, service_role;

-- (6) confirmar_baja / revertir_baja: las invoca la Edge (service_role) tras el CDR de la RA/RC.
create or replace function confirmar_baja(p_company_id uuid, p_document_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_doc documents%rowtype;
begin
  if p_company_id is null or (auth.uid() is not null and p_company_id not in (select auth_company_ids())) then
    raise exception 'No autorizado para esta empresa';
  end if;
  select * into v_doc from documents where id = p_document_id and company_id = p_company_id;
  if not found then raise exception 'Comprobante no encontrado'; end if;
  if v_doc.estado_sunat = 'anulado' then return jsonb_build_object('id', p_document_id, 'estado_sunat', 'anulado', 'ya', true); end if;
  if v_doc.estado_sunat <> 'baja_pendiente' then raise exception 'El comprobante no está en baja pendiente'; end if;
  perform _revertir_operacion(p_company_id, p_document_id, 'Baja SUNAT');
  update documents set estado_sunat = 'anulado' where id = p_document_id;
  return jsonb_build_object('id', p_document_id, 'estado_sunat', 'anulado', 'ya', false);
end $$;
grant execute on function confirmar_baja(uuid, uuid) to service_role;

create or replace function revertir_baja(p_company_id uuid, p_document_id uuid, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_doc documents%rowtype;
begin
  if p_company_id is null or (auth.uid() is not null and p_company_id not in (select auth_company_ids())) then
    raise exception 'No autorizado para esta empresa';
  end if;
  select * into v_doc from documents where id = p_document_id and company_id = p_company_id;
  if not found then raise exception 'Comprobante no encontrado'; end if;
  if v_doc.estado_sunat <> 'baja_pendiente' then
    return jsonb_build_object('id', p_document_id, 'estado_sunat', v_doc.estado_sunat, 'ya', true);
  end if;
  update documents set estado_sunat = 'aceptado',
    sunat_error = coalesce(p_motivo, 'La comunicación de baja fue rechazada por SUNAT') where id = p_document_id;
  return jsonb_build_object('id', p_document_id, 'estado_sunat', 'aceptado', 'ya', false);
end $$;
grant execute on function revertir_baja(uuid, uuid, text) to service_role;
