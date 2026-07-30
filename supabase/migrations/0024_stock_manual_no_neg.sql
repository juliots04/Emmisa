-- ============================================================
-- 0024 · La salida/ajuste MANUAL de inventario no puede dejar stock negativo.
--   La migración 0019 solo protegió la VENTA (emitir_venta); la ruta manual
--   (registerMovement → ajustar_stock) seguía sin guarda y una salida mayor al
--   stock dejaba `stock.cantidad` en negativo.
--   Aquí se redefine ajustar_stock para abortar (rollback) si la operación
--   dejaría el stock por debajo de 0. NO se toca la venta ni se agrega un CHECK
--   global (que bloquearía sobre-ventas legítimas del POS). Idempotente.
-- ============================================================

create or replace function ajustar_stock(
  p_company_id   uuid,
  p_product_id   uuid,
  p_warehouse_id uuid,
  p_delta        numeric,
  p_tipo         text default 'ajuste',   -- ingreso | salida | ajuste
  p_motivo       text default null
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare v_wh uuid := p_warehouse_id; v_cant numeric;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if not exists (select 1 from products where id = p_product_id and company_id = p_company_id) then
    raise exception 'Producto no pertenece a la empresa';
  end if;
  if v_wh is null then
    select id into v_wh from warehouses where company_id = p_company_id order by created_at limit 1;
    if v_wh is null then
      insert into warehouses (company_id, nombre) values (p_company_id, 'Principal') returning id into v_wh;
    end if;
  end if;
  insert into stock (product_id, warehouse_id, cantidad) values (p_product_id, v_wh, 0)
    on conflict (product_id, warehouse_id) do nothing;
  update stock set cantidad = cantidad + p_delta
    where product_id = p_product_id and warehouse_id = v_wh
    returning cantidad into v_cant;

  -- Guarda: una salida/ajuste no puede dejar el stock por debajo de 0 (rollback).
  if v_cant < 0 then
    raise exception 'Stock insuficiente: la operación dejaría el stock en % unidades.', v_cant;
  end if;

  insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
    values (p_company_id, p_product_id, v_wh, p_tipo, abs(p_delta), coalesce(p_motivo, p_tipo));
  return v_cant;
end $$;
grant execute on function ajustar_stock(uuid, uuid, uuid, numeric, text, text) to authenticated, service_role;
