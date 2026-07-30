-- ============================================================
-- Emmisa · 0045 · Series "como los buenos" — FASE 1: Entrada (compra)
--   • Liga cada número de serie a su ORIGEN (compra) y DESTINO (venta):
--       product_serials.purchase_id  -> compra que lo ingresó
--       product_serials.document_id  -> comprobante que lo vendió (se usa en la fase 2)
--   • registrar_compra v4: si una línea trae `series` (array) y su producto
--     «maneja_series», crea esos seriales como 'disponible' ligados a la compra,
--     dentro de la MISMA transacción atómica. Backward-compatible: las compras sin
--     `series` se comportan igual que antes (la firma de la función NO cambia; los
--     seriales viajan dentro de p_items).
--   Requiere 0037 (registrar_compra v3) y 0039 (product_serials). Idempotente.
--   Aplicar en Supabase → SQL Editor (rol postgres) → Run.
-- ============================================================

-- ---------- Trazabilidad: origen/destino del serial ----------
alter table product_serials add column if not exists purchase_id uuid references purchases(id) on delete set null;
alter table product_serials add column if not exists document_id uuid references documents(id) on delete set null;
create index if not exists product_serials_purchase_idx on product_serials(purchase_id);
create index if not exists product_serials_document_idx on product_serials(document_id);

-- ==================== registrar_compra v4 (crea seriales al recibir) ====================
create or replace function registrar_compra(
  p_company_id uuid, p_supplier_id uuid, p_tipo_doc text, p_serie_numero text, p_fecha date,
  p_items jsonb, p_moneda text default 'PEN', p_condicion_pago text default 'contado',
  p_fecha_vencimiento date default null, p_afecta_inventario boolean default true,
  p_warehouse_id uuid default null, p_igv_rate numeric default 0.18, p_tipo_cambio numeric default 1
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id uuid; v_item jsonb; v_total numeric(12,2) := 0; v_gravado numeric(12,2) := 0;
  v_igv numeric(12,2) := 0; v_grav_afecto numeric(12,2) := 0; v_pid uuid; v_qty numeric; v_costo numeric;
  v_saldo numeric(12,2); v_estado text; v_existing uuid; v_credito boolean; v_afecto boolean; v_line numeric(12,2);
  v_tc numeric(10,3) := case when coalesce(p_tipo_cambio, 1) > 0 then p_tipo_cambio else 1 end;
  v_serie text;
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
  if p_warehouse_id is not null and not exists (
       select 1 from warehouses where id = p_warehouse_id and company_id = p_company_id) then
    raise exception 'El almacén no pertenece a la empresa';
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

  v_credito := (p_tipo_doc = '01');
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'cantidad')::numeric; v_costo := (v_item->>'costo')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'Cantidad inválida en un ítem'; end if;
    if v_costo is null or v_costo < 0 then raise exception 'Costo inválido en un ítem'; end if;
    v_afecto := coalesce((v_item->>'afecto')::boolean, true);
    v_line := round(v_qty * v_costo, 2);
    v_total := v_total + v_line;
    if v_credito and v_afecto then v_grav_afecto := v_grav_afecto + v_line; end if;
  end loop;

  if v_credito then
    v_gravado := round(v_grav_afecto / (1 + p_igv_rate), 2);
    v_igv := round(v_grav_afecto - v_gravado, 2);
  else
    v_gravado := v_total; v_igv := 0;
  end if;

  if p_condicion_pago = 'credito' then v_estado := 'pendiente'; v_saldo := v_total;
  else v_estado := 'pagado'; v_saldo := 0; end if;

  insert into purchases (company_id, supplier_id, tipo_doc, serie_numero, fecha, total,
    moneda, tipo_cambio, total_gravado, total_igv, condicion_pago, estado_pago, saldo, fecha_vencimiento,
    afecta_inventario, warehouse_id)
  values (p_company_id, p_supplier_id, p_tipo_doc, p_serie_numero, coalesce(p_fecha, current_date), v_total,
    p_moneda, v_tc, v_gravado, v_igv, p_condicion_pago, v_estado, v_saldo, p_fecha_vencimiento,
    p_afecta_inventario, p_warehouse_id)
  returning id into v_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid := nullif(v_item->>'product_id','')::uuid;
    if v_pid is not null and not exists (select 1 from products where id = v_pid and company_id = p_company_id) then
      v_pid := null;
    end if;
    v_qty := (v_item->>'cantidad')::numeric; v_costo := (v_item->>'costo')::numeric;
    v_afecto := coalesce((v_item->>'afecto')::boolean, true);
    insert into purchase_items (purchase_id, product_id, descripcion, cantidad, costo, total)
      values (v_id, v_pid, v_item->>'descripcion', v_qty, v_costo, round(v_qty * v_costo, 2));
    if p_afecta_inventario and v_pid is not null
       and exists (select 1 from products where id = v_pid and controla_stock) then
      perform ajustar_stock(p_company_id, v_pid, p_warehouse_id, v_qty, 'ingreso', 'Compra ' || coalesce(p_serie_numero, ''));
      update products set costo = case when v_credito and v_afecto then round(v_costo / (1 + p_igv_rate), 2) else round(v_costo, 2) end
        where id = v_pid;
    end if;

    -- Números de serie: si la línea trae `series` y su producto maneja series, crea
    -- cada serial como 'disponible' ligado a esta compra (dentro de la transacción).
    if p_afecta_inventario and v_pid is not null
       and (v_item ? 'series') and jsonb_typeof(v_item->'series') = 'array'
       and exists (select 1 from products where id = v_pid and maneja_series) then
      for v_serie in select trim(both from t.x) from jsonb_array_elements_text(v_item->'series') as t(x) loop
        if v_serie is null or v_serie = '' then continue; end if;
        begin
          insert into product_serials (company_id, product_id, serie, estado, purchase_id)
            values (p_company_id, v_pid, v_serie, 'disponible', v_id);
        exception when unique_violation then
          raise exception 'El número de serie "%" ya está registrado para este producto', v_serie;
        end;
      end loop;
    end if;
  end loop;

  return jsonb_build_object('id', v_id, 'total', v_total, 'total_gravado', v_gravado,
    'total_igv', v_igv, 'saldo', v_saldo, 'estado_pago', v_estado, 'reused', false);
end $$;
grant execute on function registrar_compra(uuid, uuid, text, text, date, jsonb, text, text, date, boolean, uuid, numeric, numeric)
  to authenticated, service_role;
