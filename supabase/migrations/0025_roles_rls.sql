-- ============================================================
-- Emmisa · 0025 RLS por rol en catálogo (A2)
--   PROBLEMA: products/customers/establishments eran FOR ALL solo por company_id →
--   cualquier miembro (cajero/vendedor) podía BORRAR todo el catálogo/clientes.
--   SOLUCIÓN: separar las policies — leer/crear/editar cualquier miembro; BORRAR
--   solo admin (is_company_admin). No rompe flujos normales; frena el borrado masivo.
--   Aplicar DESPUÉS de 0024. Idempotente.
-- ============================================================

-- ---------- products ----------
drop policy if exists products_all on products;
drop policy if exists products_sel on products;
drop policy if exists products_ins on products;
drop policy if exists products_upd on products;
drop policy if exists products_del on products;
create policy products_sel on products for select using (company_id in (select auth_company_ids()));
create policy products_ins on products for insert with check (company_id in (select auth_company_ids()));
create policy products_upd on products for update using (company_id in (select auth_company_ids())) with check (company_id in (select auth_company_ids()));
create policy products_del on products for delete using (is_company_admin(company_id));

-- ---------- customers ----------
drop policy if exists customers_all on customers;
drop policy if exists customers_sel on customers;
drop policy if exists customers_ins on customers;
drop policy if exists customers_upd on customers;
drop policy if exists customers_del on customers;
create policy customers_sel on customers for select using (company_id in (select auth_company_ids()));
create policy customers_ins on customers for insert with check (company_id in (select auth_company_ids()));
create policy customers_upd on customers for update using (company_id in (select auth_company_ids())) with check (company_id in (select auth_company_ids()));
create policy customers_del on customers for delete using (is_company_admin(company_id));

-- ---------- establishments ----------
drop policy if exists estab_all on establishments;
drop policy if exists estab_sel on establishments;
drop policy if exists estab_ins on establishments;
drop policy if exists estab_upd on establishments;
drop policy if exists estab_del on establishments;
create policy estab_sel on establishments for select using (company_id in (select auth_company_ids()));
create policy estab_ins on establishments for insert with check (company_id in (select auth_company_ids()));
create policy estab_upd on establishments for update using (company_id in (select auth_company_ids())) with check (company_id in (select auth_company_ids()));
create policy estab_del on establishments for delete using (is_company_admin(company_id));

-- ---------- suppliers (mismo criterio) ----------
drop policy if exists suppliers_all on suppliers;
drop policy if exists suppliers_sel on suppliers;
drop policy if exists suppliers_ins on suppliers;
drop policy if exists suppliers_upd on suppliers;
drop policy if exists suppliers_del on suppliers;
create policy suppliers_sel on suppliers for select using (company_id in (select auth_company_ids()));
create policy suppliers_ins on suppliers for insert with check (company_id in (select auth_company_ids()));
create policy suppliers_upd on suppliers for update using (company_id in (select auth_company_ids())) with check (company_id in (select auth_company_ids()));
create policy suppliers_del on suppliers for delete using (is_company_admin(company_id));
