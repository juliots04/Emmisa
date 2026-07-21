-- ============================================================
-- Konversa · Notas de crédito/débito y anulación (transaccional)
-- Reemplaza el correlativo "naive" (select max()+1) de creditnotes.api.ts
-- por una reserva atómica con lock, idempotencia y afectación por ítem.
-- Agrega anular_documento (base de la comunicación de baja RA).
-- Supabase → SQL Editor → pega TODO → Run
-- ============================================================

create or replace function emitir_nota(
  p_company_id      uuid,
  p_ref_document_id uuid,
  p_tipo_nota       text,           -- 07 nota de crédito | 08 nota de débito
  p_motivo_codigo   text,
  p_motivo_desc     text,
  p_items           jsonb   default null,  -- si null, copia el total del original en 1 línea
  p_idempotency_key text    default null,
  p_igv_rate        numeric default 0.18
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref          documents%rowtype;
  v_serie        text;
  v_correlativo  int;
  v_doc_id       uuid;
  v_existing     documents%rowtype;
  v_item         jsonb;
  v_qty          numeric;
  v_price        numeric;
  v_afect        text;
  v_line_total   numeric(12,2);
  v_line_base    numeric(12,2);
  v_line_igv     numeric(12,2);
  v_total        numeric(12,2) := 0;
  v_gravado      numeric(12,2) := 0;
  v_igv          numeric(12,2) := 0;
  v_exonerado    numeric(12,2) := 0;
  v_inafecto     numeric(12,2) := 0;
  v_attempts     int := 0;
  v_numero_ref   text;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_tipo_nota not in ('07','08') then
    raise exception 'Tipo de nota inválido (use 07 o 08)';
  end if;

  select * into v_ref from documents
    where id = p_ref_document_id and company_id = p_company_id;
  if not found then raise exception 'Comprobante original no encontrado'; end if;
  if v_ref.tipo_doc not in ('01','03') then
    raise exception 'Solo se emiten notas sobre facturas (01) o boletas (03)';
  end if;

  -- Serie de la nota según tipo de comprobante afectado
  if p_tipo_nota = '07' then
    v_serie := case when v_ref.tipo_doc = '01' then 'FC01' else 'BC01' end;
  else
    v_serie := case when v_ref.tipo_doc = '01' then 'FD01' else 'BD01' end;
  end if;
  v_numero_ref := v_ref.serie || '-' || lpad(v_ref.correlativo::text, 8, '0');

  -- Idempotencia (lock advisory por llave)
  if p_idempotency_key is not null then
    perform pg_advisory_xact_lock(hashtextextended(p_company_id::text || ':' || p_idempotency_key, 0));
    select * into v_existing from documents
      where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
    if found then
      return jsonb_build_object('id', v_existing.id, 'serie', v_existing.serie,
        'correlativo', v_existing.correlativo, 'tipo_doc', v_existing.tipo_doc,
        'total', v_existing.total, 'estado_sunat', v_existing.estado_sunat, 'reused', true);
    end if;
  end if;

  -- Totales: por ítems (parcial) o copiando el original completo
  if p_items is not null and jsonb_array_length(p_items) > 0 then
    for v_item in select * from jsonb_array_elements(p_items) loop
      v_qty   := (v_item->>'cantidad')::numeric;
      v_price := (v_item->>'precio_unitario')::numeric;
      v_afect := coalesce(nullif(v_item->>'tipo_afectacion',''), '10');
      v_line_total := round(v_qty * v_price, 2);
      if v_afect = '10' then
        v_line_base := round(v_line_total / (1 + p_igv_rate), 2);
        v_line_igv  := v_line_total - v_line_base;
        v_gravado := v_gravado + v_line_base; v_igv := v_igv + v_line_igv;
      elsif v_afect = '20' then v_exonerado := v_exonerado + v_line_total;
      elsif v_afect = '30' then v_inafecto := v_inafecto + v_line_total;
      else
        v_line_base := round(v_line_total / (1 + p_igv_rate), 2);
        v_gravado := v_gravado + v_line_base; v_igv := v_igv + (v_line_total - v_line_base);
      end if;
      v_total := v_total + v_line_total;
    end loop;
  else
    v_gravado   := v_ref.total_gravado;
    v_igv       := v_ref.total_igv;
    v_exonerado := coalesce(v_ref.total_exonerado, 0);
    v_inafecto  := coalesce(v_ref.total_inafecto, 0);
    v_total     := v_ref.total;
  end if;

  -- Reserva de correlativo + insert atómico (con reintento)
  loop
    v_attempts := v_attempts + 1;
    insert into series (company_id, tipo_doc, serie, correlativo)
      values (p_company_id, p_tipo_nota, v_serie, 0)
      on conflict (company_id, tipo_doc, serie) do nothing;
    update series set correlativo = correlativo + 1
      where company_id = p_company_id and tipo_doc = p_tipo_nota and serie = v_serie
      returning correlativo into v_correlativo;

    begin
      insert into documents (
        company_id, establishment_id, customer_id, tipo_doc, serie, correlativo,
        moneda, tipo_cambio, total_gravado, total_igv, total_exonerado, total_inafecto,
        total, estado_sunat, ref_document_id, motivo_codigo, motivo_desc,
        receptor_tipo_doc, receptor_num_doc, receptor_denominacion, receptor_direccion,
        idempotency_key
      ) values (
        p_company_id, v_ref.establishment_id, v_ref.customer_id, p_tipo_nota, v_serie, v_correlativo,
        v_ref.moneda, coalesce(v_ref.tipo_cambio,1), v_gravado, v_igv, v_exonerado, v_inafecto,
        v_total, 'pendiente', p_ref_document_id, p_motivo_codigo, p_motivo_desc,
        v_ref.receptor_tipo_doc, v_ref.receptor_num_doc, v_ref.receptor_denominacion, v_ref.receptor_direccion,
        coalesce(p_idempotency_key, gen_random_uuid()::text)
      ) returning id into v_doc_id;
      exit;
    exception when unique_violation then
      if p_idempotency_key is not null then
        select * into v_existing from documents
          where company_id = p_company_id and idempotency_key = p_idempotency_key limit 1;
        if found then
          return jsonb_build_object('id', v_existing.id, 'serie', v_existing.serie,
            'correlativo', v_existing.correlativo, 'tipo_doc', v_existing.tipo_doc,
            'total', v_existing.total, 'estado_sunat', v_existing.estado_sunat, 'reused', true);
        end if;
      end if;
      if v_attempts >= 5 then raise; end if;
    end;
  end loop;

  -- Ítems de la nota
  if p_items is not null and jsonb_array_length(p_items) > 0 then
    for v_item in select * from jsonb_array_elements(p_items) loop
      v_qty   := (v_item->>'cantidad')::numeric;
      v_price := (v_item->>'precio_unitario')::numeric;
      v_afect := coalesce(nullif(v_item->>'tipo_afectacion',''), '10');
      v_line_total := round(v_qty * v_price, 2);
      if v_afect = '10' then
        v_line_base := round(v_line_total / (1 + p_igv_rate), 2);
        v_line_igv  := v_line_total - v_line_base;
      else v_line_base := v_line_total; v_line_igv := 0; end if;
      insert into document_items (document_id, product_id, descripcion, cantidad,
        valor_unitario, precio_unitario, igv, total, tipo_afectacion, unidad_medida)
      values (v_doc_id, nullif(v_item->>'product_id','')::uuid, v_item->>'descripcion', v_qty,
        case when v_qty <> 0 then round(v_line_base / v_qty, 2) else 0 end,
        v_price, v_line_igv, v_line_total, v_afect, coalesce(nullif(v_item->>'unidad_medida',''),'NIU'));
    end loop;
  else
    insert into document_items (document_id, descripcion, cantidad, valor_unitario,
      precio_unitario, igv, total, tipo_afectacion)
    values (v_doc_id,
      (case when p_tipo_nota='07' then 'Nota de crédito' else 'Nota de débito' end)
        || ' (' || coalesce(p_motivo_codigo,'') || ' · ' || coalesce(p_motivo_desc,'') || ') sobre ' || v_numero_ref,
      1, v_gravado, v_total, v_igv, v_total, '10');
  end if;

  return jsonb_build_object('id', v_doc_id, 'serie', v_serie, 'correlativo', v_correlativo,
    'tipo_doc', p_tipo_nota, 'total_gravado', v_gravado, 'total_igv', v_igv,
    'total', v_total, 'estado_sunat', 'pendiente', 'reused', false);
end $$;

grant execute on function emitir_nota(uuid, uuid, text, text, text, jsonb, text, numeric)
  to authenticated, service_role;

-- ==================== Anulación / baja ====================
-- Marca el comprobante como anulado y revierte el stock de sus ítems.
-- (La comunicación formal RA a SUNAT la dispara la Edge Function.)
create or replace function anular_documento(
  p_company_id uuid,
  p_document_id uuid,
  p_motivo text default 'Anulación'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doc   documents%rowtype;
  v_it    record;
  v_wh    uuid;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  select * into v_doc from documents where id = p_document_id and company_id = p_company_id;
  if not found then raise exception 'Comprobante no encontrado'; end if;
  if v_doc.estado_sunat = 'anulado' then
    return jsonb_build_object('id', v_doc.id, 'estado_sunat', 'anulado', 'ya', true);
  end if;

  -- Revertir kardex (reingresar lo vendido)
  for v_it in select * from document_items where document_id = p_document_id and product_id is not null loop
    if exists (select 1 from products where id = v_it.product_id and controla_stock) then
      select warehouse_id into v_wh from stock where product_id = v_it.product_id order by cantidad desc limit 1;
      if v_wh is null then
        select id into v_wh from warehouses where company_id = p_company_id order by created_at limit 1;
      end if;
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

  update documents set estado_sunat = 'anulado', sunat_error = p_motivo where id = p_document_id;
  return jsonb_build_object('id', p_document_id, 'estado_sunat', 'anulado', 'ya', false);
end $$;

grant execute on function anular_documento(uuid, uuid, text) to authenticated, service_role;
