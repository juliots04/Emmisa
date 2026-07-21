-- ============================================================
-- Konversa · 0017 Correctitud tributaria (emitir_venta v3 + anular v2)
--   • Clasificación correcta de afectación (cat. 07): gravado 10, gravadas
--     gratuitas 11-17, exonerado 20/21, inafecto 30-36, EXPORTACIÓN 40 (0%).
--   • ICBPER (bolsas plásticas) e ISC (pass-through por ítem).
--   • Descuentos por ítem y global.
--   • anular_documento v2: revierte stock + caja + cuenta por cobrar (y NO
--     reingresa stock de notas).
-- Aplicar DESPUÉS de 0016. Supabase → SQL Editor → Run
-- ============================================================

-- Columnas nuevas
alter table documents add column if not exists total_exportacion numeric(12,2) not null default 0;
alter table products  add column if not exists icbper boolean not null default false;

-- ==================== Helper: clasificar una línea por afectación ====================
create or replace function _clasificar_afectacion(p_code text, p_line_total numeric, p_igv_rate numeric)
returns table(base numeric, igv numeric, bucket text)
language plpgsql immutable as $$
begin
  if p_code = '10' then                                   -- gravado onerosa
    base := round(p_line_total / (1 + p_igv_rate), 2); igv := p_line_total - base; bucket := 'gravado';
  elsif p_code in ('11','12','13','14','15','16','17') then   -- gravadas gratuitas (bonificación, retiro…)
    base := round(p_line_total / (1 + p_igv_rate), 2); igv := p_line_total - base; bucket := 'gratuito';
  elsif p_code = '20' then base := p_line_total; igv := 0; bucket := 'exonerado';
  elsif p_code = '21' then base := p_line_total; igv := 0; bucket := 'gratuito';   -- exonerado gratuito
  elsif p_code = '30' then base := p_line_total; igv := 0; bucket := 'inafecto';
  elsif p_code in ('31','32','33','34','35','36') then base := p_line_total; igv := 0; bucket := 'gratuito'; -- inafecto gratuito
  elsif p_code = '40' then base := p_line_total; igv := 0; bucket := 'exportacion';  -- exportación 0%
  else base := round(p_line_total / (1 + p_igv_rate), 2); igv := p_line_total - base; bucket := 'gravado';
  end if;
  return next;
end $$;
grant execute on function _clasificar_afectacion(text, numeric, numeric) to authenticated, service_role;

-- ==================== emitir_venta v3 ====================
drop function if exists emitir_venta(uuid, text, text, jsonb, jsonb, text, numeric, numeric, uuid, text, numeric, text, numeric, text, date, uuid);

create or replace function emitir_venta(
  p_company_id       uuid,
  p_tipo_doc         text,
  p_serie            text,
  p_cliente          jsonb,
  p_items            jsonb,          -- [ { product_id?, descripcion, cantidad, precio_unitario, tipo_afectacion?, unidad_medida?, descuento?, icbper?, isc? } ]
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
  p_establishment_id uuid    default null,
  p_icbper_rate      numeric default 0.50,
  p_descuento_global numeric default 0
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
  v_price        numeric;
  v_desc         numeric;
  v_code         text;
  v_line_total   numeric(12,2);
  v_base         numeric(12,2);
  v_ligv         numeric(12,2);
  v_bucket       text;
  v_icb          numeric(12,2);
  v_isc          numeric(12,2);
  v_total        numeric(12,2) := 0;
  v_gravado      numeric(12,2) := 0;
  v_igv          numeric(12,2) := 0;
  v_exonerado    numeric(12,2) := 0;
  v_inafecto     numeric(12,2) := 0;
  v_gratuito     numeric(12,2) := 0;
  v_exportacion  numeric(12,2) := 0;
  v_icbper       numeric(12,2) := 0;
  v_isctot       numeric(12,2) := 0;
  v_wh           uuid;
  v_numero       text;
  v_attempts     int := 0;
  v_estado_pago  text;
  v_saldo        numeric(12,2);
  v_r_tipo       text := coalesce(nullif(p_cliente->>'tipo_doc',''), '0');
  v_r_num        text := nullif(p_cliente->>'num_doc','');
  v_r_den        text := coalesce(nullif(p_cliente->>'denominacion',''), 'Cliente varios');
  v_r_dir        text := nullif(p_cliente->>'direccion','');
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no tiene ítems';
  end if;
  if p_tipo_doc = '01' then
    if v_r_tipo <> '6' or v_r_num is null or v_r_num !~ '^\d{11}$' then
      raise exception 'Una factura (01) requiere un cliente con RUC válido de 11 dígitos';
    end if;
  end if;

  -- Idempotencia (lock advisory por llave → sin salto de correlativo)
  if p_idempotency_key is not null then
    perform pg_advisory_xact_lock(hashtextextended(p_company_id::text || ':' || p_idempotency_key, 0));
    select * into v_existing from documents
      where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
    if found then
      return jsonb_build_object('id', v_existing.id, 'serie', v_existing.serie, 'correlativo', v_existing.correlativo,
        'tipo_doc', v_existing.tipo_doc, 'total', v_existing.total, 'estado_sunat', v_existing.estado_sunat, 'reused', true);
    end if;
  end if;

  if p_cash_session_id is not null then
    perform 1 from cash_sessions where id = p_cash_session_id and company_id = p_company_id and estado = 'abierta';
    if not found then raise exception 'No hay una caja abierta para registrar la venta'; end if;
  end if;

  -- Totales por afectación (con descuento por ítem, ICBPER e ISC)
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid   := nullif(v_item->>'product_id','')::uuid;
    v_qty   := (v_item->>'cantidad')::numeric;
    v_price := (v_item->>'precio_unitario')::numeric;
    v_desc  := coalesce((v_item->>'descuento')::numeric, 0);
    v_code  := coalesce(nullif(v_item->>'tipo_afectacion',''),
                        (select tipo_afectacion from products where id = v_pid and company_id = p_company_id), '10');
    v_line_total := round(v_qty * v_price - v_desc, 2);
    select base, igv, bucket into v_base, v_ligv, v_bucket from _clasificar_afectacion(v_code, v_line_total, p_igv_rate);

    if v_bucket = 'gravado' then
      v_gravado := v_gravado + v_base; v_igv := v_igv + v_ligv; v_total := v_total + v_line_total;
    elsif v_bucket = 'exonerado' then v_exonerado := v_exonerado + v_line_total; v_total := v_total + v_line_total;
    elsif v_bucket = 'inafecto'  then v_inafecto  := v_inafecto  + v_line_total; v_total := v_total + v_line_total;
    elsif v_bucket = 'exportacion' then v_exportacion := v_exportacion + v_line_total; v_total := v_total + v_line_total;
    else v_gratuito := v_gratuito + v_line_total;  -- gratuito: no suma a pagar
    end if;

    -- ICBPER (bolsa plástica) e ISC (monto por ítem) suman al total a pagar
    v_icb := case when coalesce((v_item->>'icbper')::boolean, (select icbper from products where id = v_pid), false)
                  then round(v_qty * p_icbper_rate, 2) else 0 end;
    v_isc := coalesce((v_item->>'isc')::numeric, 0);
    v_icbper := v_icbper + v_icb;
    v_isctot := v_isctot + v_isc;
    v_total  := v_total + v_icb + v_isc;
  end loop;

  v_total := round(v_total - coalesce(p_descuento_global, 0), 2);

  v_customer_id := nullif(p_cliente->>'customer_id', '')::uuid;
  if v_customer_id is not null
     and not exists (select 1 from customers where id = v_customer_id and company_id = p_company_id) then
    v_customer_id := null;
  end if;

  if p_condicion_pago = 'credito' then v_estado_pago := 'pendiente'; v_saldo := v_total;
  else v_estado_pago := 'pagado'; v_saldo := 0; end if;

  -- Reserva de correlativo + insert atómico
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
        select * into v_existing from documents
          where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
        if found then
          return jsonb_build_object('id', v_existing.id, 'serie', v_existing.serie, 'correlativo', v_existing.correlativo,
            'tipo_doc', v_existing.tipo_doc, 'total', v_existing.total, 'estado_sunat', v_existing.estado_sunat, 'reused', true);
        end if;
      end if;
      if v_attempts >= 5 then raise; end if;
    end;
  end loop;

  -- Ítems + kardex
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid := nullif(v_item->>'product_id','')::uuid;
    if v_pid is not null and not exists (select 1 from products where id = v_pid and company_id = p_company_id) then
      v_pid := null;
    end if;
    v_qty   := (v_item->>'cantidad')::numeric;
    v_price := (v_item->>'precio_unitario')::numeric;
    v_desc  := coalesce((v_item->>'descuento')::numeric, 0);
    v_code  := coalesce(nullif(v_item->>'tipo_afectacion',''),
                        (select tipo_afectacion from products where id = v_pid), '10');
    v_line_total := round(v_qty * v_price - v_desc, 2);
    select base, igv, bucket into v_base, v_ligv, v_bucket from _clasificar_afectacion(v_code, v_line_total, p_igv_rate);

    insert into document_items (
      document_id, product_id, descripcion, cantidad, valor_unitario,
      precio_unitario, igv, total, tipo_afectacion, unidad_medida, descuento
    ) values (
      v_doc_id, v_pid, v_item->>'descripcion', v_qty,
      case when v_qty <> 0 then round(v_base / v_qty, 2) else 0 end,
      v_price, v_ligv, v_line_total, v_code,
      coalesce(nullif(v_item->>'unidad_medida',''), 'NIU'), v_desc
    );

    if v_pid is not null and exists (select 1 from products where id = v_pid and controla_stock) then
      select warehouse_id into v_wh from stock where product_id = v_pid order by cantidad desc limit 1 for update;
      if v_wh is null then select id into v_wh from warehouses where company_id = p_company_id order by created_at limit 1; end if;
      if v_wh is null then insert into warehouses (company_id, nombre) values (p_company_id, 'Principal') returning id into v_wh; end if;
      insert into stock (product_id, warehouse_id, cantidad) values (v_pid, v_wh, 0) on conflict (product_id, warehouse_id) do nothing;
      update stock set cantidad = cantidad - v_qty where product_id = v_pid and warehouse_id = v_wh;
      insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
        values (p_company_id, v_pid, v_wh, 'salida', v_qty, 'Venta ' || v_numero);
    end if;
  end loop;

  -- Pago: ledger + efectivo a caja (solo contado con monto > 0; una venta 100% gratuita no cobra)
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

-- ==================== anular_documento v2 (revierte stock + caja + CxC) ====================
create or replace function anular_documento(
  p_company_id uuid, p_document_id uuid, p_motivo text default 'Anulación'
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_doc      documents%rowtype;
  v_it       record;
  v_wh       uuid;
  v_efectivo numeric(12,2);
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  select * into v_doc from documents where id = p_document_id and company_id = p_company_id;
  if not found then raise exception 'Comprobante no encontrado'; end if;
  if v_doc.estado_sunat = 'anulado' then
    return jsonb_build_object('id', v_doc.id, 'estado_sunat', 'anulado', 'ya', true);
  end if;

  -- 1) Stock: solo se revierte para VENTAS (01/03); las notas no descontaron stock.
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

  -- 2) Caja: si hubo efectivo ingresado por este doc, se registra el retiro compensatorio.
  select coalesce(sum(monto),0) into v_efectivo from cash_movements
    where document_id = p_document_id and tipo = 'ingreso';
  if v_efectivo > 0 and v_doc.cash_session_id is not null then
    insert into cash_movements (cash_session_id, tipo, monto, motivo, document_id)
      values (v_doc.cash_session_id, 'retiro', v_efectivo, 'Anulación ' || v_doc.serie, p_document_id);
  end if;

  -- 3) Cuentas por cobrar: se elimina el saldo y los cobros de este doc.
  delete from payments where document_id = p_document_id;
  update documents set estado_sunat = 'anulado', sunat_error = p_motivo, estado_pago = 'pagado', saldo = 0
    where id = p_document_id;

  return jsonb_build_object('id', p_document_id, 'estado_sunat', 'anulado', 'ya', false);
end $$;
grant execute on function anular_documento(uuid, uuid, text) to authenticated, service_role;
