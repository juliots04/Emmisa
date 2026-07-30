-- ============================================================
-- Emmisa · 0028 Fixes de auditoría de núcleos 2 (Caja, Inventario, Clientes, Cotizaciones)
--   (HIGH) ajustar_stock/fijar_stock: validan que el ALMACÉN pertenezca a la empresa
--          (cierra el hueco cross-tenant de escribir stock con warehouse_id ajeno).
--   (HIGH) fijar_stock: registra en el kardex la DIFERENCIA (no el valor absoluto) y
--          exige stock >= 0 (coherente con 0024).
--   (HIGH) Caja: RPCs SECURITY DEFINER abrir_caja / cerrar_caja / mov_caja que validan
--          estado='abierta' + pertenencia y RECOMPUTAN el arqueo en servidor (no forjable).
--          El revoke de escritura directa va en 0029 (aplicar TRAS desplegar el front nuevo).
--   (MED)  quote_items: columnas tipo_afectacion + product_id (para no forzar gravado 18%).
--   (LOW)  índice único de clientes por (empresa, tipo_doc, num_doc) (dedup).
-- Rebasado sobre 0023/0024/0027 (versiones vivas). Aplicar DESPUÉS de 0027. Idempotente.
-- ============================================================

-- (1) ajustar_stock = 0024 + validación de almacén ⊂ empresa
create or replace function ajustar_stock(
  p_company_id uuid, p_product_id uuid, p_warehouse_id uuid, p_delta numeric,
  p_tipo text default 'ajuste', p_motivo text default null
)
returns numeric language plpgsql security definer set search_path = public as $$
declare v_wh uuid := p_warehouse_id; v_cant numeric;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if not exists (select 1 from products where id = p_product_id and company_id = p_company_id) then
    raise exception 'Producto no pertenece a la empresa';
  end if;
  -- FIX cross-tenant: el almacén indicado debe ser de ESTA empresa.
  if v_wh is not null and not exists (select 1 from warehouses where id = v_wh and company_id = p_company_id) then
    raise exception 'El almacén no pertenece a la empresa';
  end if;
  if v_wh is null then
    select id into v_wh from warehouses where company_id = p_company_id order by created_at limit 1;
    if v_wh is null then insert into warehouses (company_id, nombre) values (p_company_id, 'Principal') returning id into v_wh; end if;
  end if;
  insert into stock (product_id, warehouse_id, cantidad) values (p_product_id, v_wh, 0)
    on conflict (product_id, warehouse_id) do nothing;
  update stock set cantidad = cantidad + p_delta
    where product_id = p_product_id and warehouse_id = v_wh
    returning cantidad into v_cant;
  if v_cant < 0 then
    raise exception 'Stock insuficiente: la operación dejaría el stock en % unidades.', v_cant;
  end if;
  insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
    values (p_company_id, p_product_id, v_wh, p_tipo, abs(p_delta), coalesce(p_motivo, p_tipo));
  return v_cant;
end $$;
grant execute on function ajustar_stock(uuid, uuid, uuid, numeric, text, text) to authenticated, service_role;

-- (2) fijar_stock = kardex por DIFERENCIA + no-negativo + validación de almacén
create or replace function fijar_stock(
  p_company_id uuid, p_product_id uuid, p_warehouse_id uuid, p_cantidad numeric, p_motivo text default 'Ajuste'
)
returns numeric language plpgsql security definer set search_path = public as $$
declare v_wh uuid := p_warehouse_id; v_prev numeric := 0; v_diff numeric;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if not exists (select 1 from products where id = p_product_id and company_id = p_company_id) then
    raise exception 'Producto no pertenece a la empresa';
  end if;
  if p_cantidad < 0 then raise exception 'El stock no puede ser negativo'; end if;
  if v_wh is not null and not exists (select 1 from warehouses where id = v_wh and company_id = p_company_id) then
    raise exception 'El almacén no pertenece a la empresa';
  end if;
  if v_wh is null then
    select id into v_wh from warehouses where company_id = p_company_id order by created_at limit 1;
    if v_wh is null then insert into warehouses (company_id, nombre) values (p_company_id, 'Principal') returning id into v_wh; end if;
  end if;
  insert into stock (product_id, warehouse_id, cantidad) values (p_product_id, v_wh, 0)
    on conflict (product_id, warehouse_id) do nothing;
  -- Lee (y bloquea) la cantidad previa para registrar la DIFERENCIA en el kardex.
  select cantidad into v_prev from stock where product_id = p_product_id and warehouse_id = v_wh for update;
  v_diff := p_cantidad - coalesce(v_prev, 0);
  update stock set cantidad = p_cantidad where product_id = p_product_id and warehouse_id = v_wh;
  if v_diff <> 0 then
    insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
      values (p_company_id, p_product_id, v_wh,
              case when v_diff > 0 then 'ingreso' else 'salida' end, abs(v_diff),
              coalesce(p_motivo, 'Ajuste por conteo') || ' (' || coalesce(v_prev, 0)::text || '→' || p_cantidad::text || ')');
  end if;
  return p_cantidad;
end $$;
grant execute on function fijar_stock(uuid, uuid, uuid, numeric, text) to authenticated, service_role;

-- (3) Caja: RPCs server-side (arqueo no forjable)
create or replace function abrir_caja(p_company_id uuid, p_monto_inicial numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_uid uuid := auth.uid();
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_monto_inicial is null or p_monto_inicial < 0 then raise exception 'Monto inicial inválido'; end if;
  if exists (select 1 from cash_sessions where company_id = p_company_id and user_id = v_uid and estado = 'abierta') then
    raise exception 'Ya tienes una caja abierta';
  end if;
  insert into cash_sessions (company_id, user_id, monto_inicial) values (p_company_id, v_uid, p_monto_inicial)
    returning id into v_id;
  return jsonb_build_object('id', v_id, 'estado', 'abierta');
end $$;
grant execute on function abrir_caja(uuid, numeric) to authenticated, service_role;

create or replace function mov_caja(p_session_id uuid, p_tipo text, p_monto numeric, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_s cash_sessions%rowtype; v_id uuid;
begin
  if p_tipo not in ('ingreso','retiro') then raise exception 'Tipo de movimiento inválido'; end if;
  if p_monto is null or p_monto <= 0 then raise exception 'Monto inválido'; end if;
  select * into v_s from cash_sessions where id = p_session_id;
  if not found then raise exception 'Caja no encontrada'; end if;
  if v_s.company_id not in (select auth_company_ids()) then raise exception 'No autorizado para esta empresa'; end if;
  if v_s.estado <> 'abierta' then raise exception 'La caja está cerrada'; end if;
  insert into cash_movements (cash_session_id, tipo, monto, motivo)
    values (p_session_id, p_tipo, p_monto, p_motivo) returning id into v_id;
  return jsonb_build_object('id', v_id);
end $$;
grant execute on function mov_caja(uuid, text, numeric, text) to authenticated, service_role;

create or replace function cerrar_caja(p_session_id uuid, p_monto_final numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_s cash_sessions%rowtype; v_ing numeric(12,2); v_ret numeric(12,2); v_esperado numeric(12,2); v_dif numeric(12,2);
begin
  if p_monto_final is null or p_monto_final < 0 then raise exception 'Monto final inválido'; end if;
  -- Bloquea la fila para serializar el cierre.
  select * into v_s from cash_sessions where id = p_session_id for update;
  if not found then raise exception 'Caja no encontrada'; end if;
  if v_s.company_id not in (select auth_company_ids()) then raise exception 'No autorizado para esta empresa'; end if;
  if v_s.estado <> 'abierta' then raise exception 'La caja ya está cerrada'; end if;
  -- Arqueo RECOMPUTADO en servidor (no forjable desde el cliente).
  select coalesce(sum(case when tipo = 'ingreso' then monto else 0 end), 0),
         coalesce(sum(case when tipo = 'retiro'  then monto else 0 end), 0)
    into v_ing, v_ret from cash_movements where cash_session_id = p_session_id;
  v_esperado := round(coalesce(v_s.monto_inicial, 0) + v_ing - v_ret, 2);
  v_dif := round(p_monto_final - v_esperado, 2);
  update cash_sessions set monto_final = p_monto_final, diferencia = v_dif, estado = 'cerrada', cerrado_en = now()
    where id = p_session_id and estado = 'abierta';
  return jsonb_build_object('id', p_session_id, 'monto_final', p_monto_final, 'esperado', v_esperado,
    'diferencia', v_dif, 'estado', 'cerrada');
end $$;
grant execute on function cerrar_caja(uuid, numeric) to authenticated, service_role;

-- (4) quote_items: afectación + vínculo a producto (para no forzar gravado 18% al convertir)
alter table quote_items add column if not exists tipo_afectacion text not null default '10';
alter table quote_items add column if not exists product_id uuid references products(id) on delete set null;
alter table quote_items add column if not exists unidad_medida text not null default 'NIU';

-- (5) Dedup de clientes por (empresa, tipo_doc, num_doc) — evita receptores duplicados.
create unique index if not exists ux_customers_doc on customers (company_id, tipo_doc, num_doc)
  where num_doc is not null and num_doc <> '';
