-- ============================================================
-- Emmisa · 0020 Correctitud del XML fiscal (emitir_venta v4)
--   La BD ya CALCULA bien ICBPER, ISC, gratuitas y exportación (0017), pero:
--     1) La unidad de medida no caía al valor del PRODUCTO -> toda línea salía NIU
--        aunque el producto fuera KGM/LTR. Ahora hace fallback a products.unidad_medida.
--     2) El ICBPER e ISC de cada línea no se PERSISTÍAN en document_items, así que la
--        Edge Function no podía declararlos como tributo en el XML (rechazo SUNAT 3105).
--        Ahora se guardan por línea (icbper, isc) para que el motor los emita.
--   Aplicar DESPUÉS de 0019. Supabase → SQL Editor → Run (rol postgres). Idempotente.
-- ============================================================

-- Columnas por línea para que el motor de emisión declare los tributos en el XML.
alter table document_items add column if not exists icbper numeric(12,2) not null default 0;
alter table document_items add column if not exists isc    numeric(12,2) not null default 0;

create or replace function emitir_venta(
  p_company_id       uuid,
  p_tipo_doc         text,
  p_serie            text,
  p_cliente          jsonb,
  p_items            jsonb,
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
  v_unidad       text;
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
    else v_gratuito := v_gratuito + v_line_total;
    end if;

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

  -- Ítems + kardex. Recalcula por línea la afectación, la unidad (con fallback al
  -- producto) e ICBPER/ISC para persistirlos y que el motor los declare en el XML.
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
    -- Fallback de unidad de medida: ítem → producto → NIU (cat. 03)
    v_unidad := coalesce(nullif(v_item->>'unidad_medida',''),
                         (select unidad_medida from products where id = v_pid), 'NIU');
    v_line_total := round(v_qty * v_price - v_desc, 2);
    select base, igv, bucket into v_base, v_ligv, v_bucket from _clasificar_afectacion(v_code, v_line_total, p_igv_rate);
    v_icb := case when coalesce((v_item->>'icbper')::boolean, (select icbper from products where id = v_pid), false)
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
