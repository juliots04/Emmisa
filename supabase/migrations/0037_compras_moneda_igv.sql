-- ============================================================
-- Konversa · 0034 Compras: moneda/TC + IGV por ítem + unicidad de barcode
--   Aplicar DESPUÉS de 0033. Supabase → SQL Editor (rol postgres) → Run.
--
--   • A2  registrar_compra: el IGV/crédito se calcula por ÍTEM (afecto/no afecto),
--         no 18% sobre todo el total de la factura. Antes una factura con líneas
--         exoneradas/inafectas sobre-declaraba crédito fiscal.
--   • Compras en moneda extranjera: nueva columna purchases.tipo_cambio (para el PLE
--         de compras y el arqueo). registrar_compra acepta p_tipo_cambio.
--   • Unicidad de código de barra por empresa (evita que el POS facture el producto
--         equivocado por un barcode duplicado). Si ya hay duplicados, avisa sin romper.
-- ============================================================

-- Tipo de cambio de la compra (para PLE 8.1 col 25 y conversión a soles).
alter table purchases add column if not exists tipo_cambio numeric(10,3) not null default 1;

-- ==================== registrar_compra v3 (IGV por ítem + tipo de cambio) ====================
drop function if exists registrar_compra(uuid, uuid, text, text, date, jsonb, text, text, date, boolean, uuid, numeric);

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
  -- El almacén (si se indica) debe pertenecer a la empresa.
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

  -- Solo la factura (01) da crédito fiscal. El IGV se extrae SOLO de las líneas afectas.
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
    v_gravado := round(v_grav_afecto / (1 + p_igv_rate), 2);  -- base con derecho a crédito
    v_igv := round(v_grav_afecto - v_gravado, 2);
    -- (las líneas NO afectas de la factura quedan como "no gravado" = total - gravado - igv)
  else
    v_gravado := v_total; v_igv := 0;                          -- boleta/otros: todo costo
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
      -- Costo NETO solo si la línea tiene crédito fiscal (factura + afecto); si no, el IGV es parte del costo.
      update products set costo = case when v_credito and v_afecto then round(v_costo / (1 + p_igv_rate), 2) else round(v_costo, 2) end
        where id = v_pid;
    end if;
  end loop;

  return jsonb_build_object('id', v_id, 'total', v_total, 'total_gravado', v_gravado,
    'total_igv', v_igv, 'saldo', v_saldo, 'estado_pago', v_estado, 'reused', false);
end $$;
grant execute on function registrar_compra(uuid, uuid, text, text, date, jsonb, text, text, date, boolean, uuid, numeric, numeric)
  to authenticated, service_role;

-- ==================== Unicidad de código de barra por empresa ====================
-- El POS resuelve el lector por barcode → el primer match. Dos productos con el mismo
-- barcode = factura el equivocado. Índice único parcial (ignora vacíos/nulos).
do $$
begin
  create unique index if not exists ux_products_barcode
    on products (company_id, barcode) where barcode is not null and barcode <> '';
exception when others then
  raise notice 'No se pudo crear la unicidad de barcode (¿duplicados existentes?): %', sqlerrm;
end $$;
