-- ============================================================
-- Konversa · Integridad operativa
--   • Una sola caja abierta por usuario (índice único parcial).
--   • Stock 100% atómico (RPC ajustar_stock) — reemplaza el read-modify-write.
--   • Compra transaccional que ingresa a inventario y arma CxP (registrar_compra).
--   • Abonos de cuentas por cobrar / pagar (registrar_abono).
--   • Gestión real de miembros (policies UPDATE/DELETE + alta por email).
--   • Auditoría automática (audit_events por trigger).
-- Supabase → SQL Editor → pega TODO → Run
-- ============================================================

-- ==================== 1) Caja: una abierta por usuario ====================
create unique index if not exists ux_caja_abierta_por_usuario
  on cash_sessions (company_id, user_id)
  where estado = 'abierta';

-- ==================== 2) Stock atómico ====================
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
  insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
    values (p_company_id, p_product_id, v_wh, p_tipo, abs(p_delta), coalesce(p_motivo, p_tipo));
  return v_cant;
end $$;
grant execute on function ajustar_stock(uuid, uuid, uuid, numeric, text, text) to authenticated, service_role;

-- Fija el stock a un valor absoluto (ajuste por conteo físico), atómico.
create or replace function fijar_stock(
  p_company_id uuid, p_product_id uuid, p_warehouse_id uuid, p_cantidad numeric, p_motivo text default 'Ajuste'
)
returns numeric
language plpgsql security definer set search_path = public as $$
declare v_wh uuid := p_warehouse_id;
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
  insert into stock (product_id, warehouse_id, cantidad) values (p_product_id, v_wh, p_cantidad)
    on conflict (product_id, warehouse_id) do update set cantidad = excluded.cantidad;
  insert into inventory_movements (company_id, product_id, warehouse_id, tipo, cantidad, motivo)
    values (p_company_id, p_product_id, v_wh, 'ajuste', p_cantidad, coalesce(p_motivo,'Ajuste'));
  return p_cantidad;
end $$;
grant execute on function fijar_stock(uuid, uuid, uuid, numeric, text) to authenticated, service_role;

-- ==================== 3) Compra transaccional (→ inventario + CxP) ====================
create or replace function registrar_compra(
  p_company_id       uuid,
  p_supplier_id      uuid,
  p_tipo_doc         text,
  p_serie_numero     text,
  p_fecha            date,
  p_items            jsonb,           -- [ { product_id?, descripcion, cantidad, costo } ] (costo incluye IGV)
  p_moneda           text    default 'PEN',
  p_condicion_pago   text    default 'contado',
  p_fecha_vencimiento date   default null,
  p_afecta_inventario boolean default true,
  p_warehouse_id     uuid    default null,
  p_igv_rate         numeric default 0.18
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id       uuid;
  v_item     jsonb;
  v_total    numeric(12,2) := 0;
  v_gravado  numeric(12,2) := 0;
  v_igv      numeric(12,2) := 0;
  v_line     numeric(12,2);
  v_pid      uuid;
  v_qty      numeric;
  v_costo    numeric;
  v_saldo    numeric(12,2);
  v_estado   text;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'La compra no tiene ítems';
  end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'cantidad')::numeric; v_costo := (v_item->>'costo')::numeric;
    v_line := round(v_qty * v_costo, 2);
    v_total := v_total + v_line;
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
      perform ajustar_stock(p_company_id, v_pid, p_warehouse_id, v_qty, 'ingreso',
        'Compra ' || coalesce(p_serie_numero, ''));
      -- actualiza costo del producto (simplificado; costo promedio móvil es Fase 2)
      update products set costo = round(v_costo / (1 + p_igv_rate), 2) where id = v_pid;
    end if;
  end loop;

  return jsonb_build_object('id', v_id, 'total', v_total, 'total_gravado', v_gravado,
    'total_igv', v_igv, 'saldo', v_saldo, 'estado_pago', v_estado);
end $$;
grant execute on function registrar_compra(uuid, uuid, text, text, date, jsonb, text, text, date, boolean, uuid, numeric)
  to authenticated, service_role;

-- ==================== 4) Abonos (CxC / CxP) ====================
create or replace function registrar_abono(
  p_company_id      uuid,
  p_monto           numeric,
  p_document_id     uuid    default null,   -- cobro (CxC)
  p_purchase_id     uuid    default null,   -- pago (CxP)
  p_medio           text    default 'efectivo',
  p_referencia      text    default null,
  p_cash_session_id uuid    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_saldo numeric(12,2);
  v_tipo  text;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if p_monto is null or p_monto <= 0 then raise exception 'Monto inválido'; end if;

  if p_document_id is not null then
    v_tipo := 'cobro';
    update documents set saldo = greatest(saldo - p_monto, 0)
      where id = p_document_id and company_id = p_company_id
      returning saldo into v_saldo;
    if not found then raise exception 'Comprobante no encontrado'; end if;
    update documents set estado_pago = case when saldo <= 0 then 'pagado' else 'parcial' end
      where id = p_document_id;
    insert into payments (company_id, tipo, document_id, cash_session_id, medio, monto, referencia)
      values (p_company_id, 'cobro', p_document_id, p_cash_session_id, p_medio, p_monto, p_referencia);
    if p_cash_session_id is not null and p_medio = 'efectivo' then
      insert into cash_movements (cash_session_id, tipo, monto, motivo, document_id)
        values (p_cash_session_id, 'ingreso', p_monto, 'Abono CxC', p_document_id);
    end if;
  elsif p_purchase_id is not null then
    v_tipo := 'pago';
    update purchases set saldo = greatest(saldo - p_monto, 0)
      where id = p_purchase_id and company_id = p_company_id
      returning saldo into v_saldo;
    if not found then raise exception 'Compra no encontrada'; end if;
    update purchases set estado_pago = case when saldo <= 0 then 'pagado' else 'parcial' end
      where id = p_purchase_id;
    insert into payments (company_id, tipo, purchase_id, cash_session_id, medio, monto, referencia)
      values (p_company_id, 'pago', p_purchase_id, p_cash_session_id, p_medio, p_monto, p_referencia);
    if p_cash_session_id is not null and p_medio = 'efectivo' then
      insert into cash_movements (cash_session_id, tipo, monto, motivo, document_id)
        values (p_cash_session_id, 'retiro', p_monto, 'Pago CxP', null);
    end if;
  else
    raise exception 'Indica un comprobante (CxC) o una compra (CxP)';
  end if;

  return jsonb_build_object('tipo', v_tipo, 'saldo', v_saldo);
end $$;
grant execute on function registrar_abono(uuid, numeric, uuid, uuid, text, text, uuid) to authenticated, service_role;

-- ==================== 5) Gestión de miembros ====================
drop policy if exists memberships_update on memberships;
create policy memberships_update on memberships for update
  using (is_company_admin(company_id)) with check (is_company_admin(company_id));
drop policy if exists memberships_delete on memberships;
create policy memberships_delete on memberships for delete
  using (is_company_admin(company_id));
-- ver a los demás miembros de mis empresas (no solo a mí mismo)
drop policy if exists memberships_select_company on memberships;
create policy memberships_select_company on memberships for select
  using (company_id in (select auth_company_ids()));

-- Alta de miembro por email (el usuario debe existir en Auth). Solo admin de la empresa.
create or replace function agregar_miembro_por_email(
  p_company_id uuid, p_email text, p_role text default 'vendedor'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid;
begin
  if not is_company_admin(p_company_id) then
    raise exception 'Solo un admin puede agregar miembros';
  end if;
  select id into v_uid from auth.users where lower(email) = lower(p_email) limit 1;
  if v_uid is null then
    raise exception 'No existe un usuario con ese email. Pídele que se registre primero.';
  end if;
  insert into memberships (user_id, company_id, role) values (v_uid, p_company_id, p_role)
    on conflict (user_id, company_id) do update set role = excluded.role;
  return jsonb_build_object('user_id', v_uid, 'role', p_role);
end $$;
grant execute on function agregar_miembro_por_email(uuid, text, text) to authenticated, service_role;

-- ==================== 6) Auditoría automática ====================
create or replace function audit_row()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_cid uuid; v_eid uuid; v_payload jsonb;
begin
  if TG_OP = 'DELETE' then
    v_cid := (to_jsonb(OLD)->>'company_id')::uuid; v_eid := (to_jsonb(OLD)->>'id')::uuid;
    v_payload := to_jsonb(OLD);
  else
    v_cid := (to_jsonb(NEW)->>'company_id')::uuid; v_eid := (to_jsonb(NEW)->>'id')::uuid;
    v_payload := to_jsonb(NEW);
  end if;
  insert into audit_events (company_id, user_id, accion, entidad, entidad_id, payload)
    values (v_cid, auth.uid(), lower(TG_OP), TG_TABLE_NAME, v_eid, v_payload);
  if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
end $$;

drop trigger if exists trg_audit_documents on documents;
create trigger trg_audit_documents after insert or update or delete on documents
  for each row execute function audit_row();
drop trigger if exists trg_audit_products on products;
create trigger trg_audit_products after insert or update or delete on products
  for each row execute function audit_row();
drop trigger if exists trg_audit_purchases on purchases;
create trigger trg_audit_purchases after insert or update or delete on purchases
  for each row execute function audit_row();

-- ==================== GRANTS ====================
grant all privileges on all tables    in schema public to anon, authenticated, service_role;
grant execute        on all functions in schema public to anon, authenticated, service_role;
