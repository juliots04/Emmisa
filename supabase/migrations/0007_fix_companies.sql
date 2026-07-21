-- ============================================================
-- Fix definitivo: permisos + políticas de companies
-- Supabase → SQL Editor → pega TODO → Run
-- ============================================================

-- 1) Permisos de la Data API (arregla 403 "permission denied")
grant usage on schema public to anon, authenticated, service_role;
grant all privileges on all tables in schema public to anon, authenticated, service_role;
grant all privileges on all sequences in schema public to anon, authenticated, service_role;
grant execute on all functions in schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;

-- 2) Políticas de companies (recreadas limpias; el owner siempre ve/crea la suya)
drop policy if exists companies_select on companies;
drop policy if exists companies_insert on companies;
drop policy if exists companies_update on companies;

create policy companies_select on companies for select
  using (owner_id = auth.uid() or id in (select auth_company_ids()));
create policy companies_insert on companies for insert
  with check (owner_id = auth.uid());
create policy companies_update on companies for update
  using (owner_id = auth.uid());

-- 3) Diagnóstico: revisa que 'authenticated' tenga privilegios sobre companies
select grantee, privilege_type
from information_schema.role_table_grants
where table_name = 'companies' and grantee in ('anon', 'authenticated')
order by grantee, privilege_type;
