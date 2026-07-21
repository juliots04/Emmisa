-- ============================================================
-- Fix de permisos para la Data API (PostgREST)
-- Los proyectos nuevos de Supabase requieren GRANTS explícitos para que
-- las tablas creadas por SQL sean accesibles vía la API REST.
-- (El RLS sigue protegiendo las filas; esto solo abre el acceso a nivel de rol.)
-- Cómo usarlo: Supabase → SQL Editor → pega todo → Run
-- ============================================================

grant usage on schema public to anon, authenticated, service_role;

grant all privileges on all tables in schema public to anon, authenticated, service_role;
grant all privileges on all sequences in schema public to anon, authenticated, service_role;
grant execute on all functions in schema public to anon, authenticated, service_role;

alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
