-- ============================================================
-- Emmisa · 0043 · Fix: restaurar DELETE en categories
--   La migración 0036_auditoria_2.sql revocó `delete on categories` del rol
--   `authenticated` con la intención "solo un admin borra", pero el permiso de
--   tabla se evalúa por ROL (todos los usuarios comparten `authenticated`), no por
--   RLS — así que en la práctica NADIE (ni el admin) podía borrar categorías:
--   `deleteCategory` fallaba siempre con 42501 (permission denied).
--   El aislamiento por empresa lo sigue garantizando la policy `categories_all`
--   (FOR ALL, company_id in auth_company_ids()). Se restaura el grant para dejar
--   el borrado igual que en `brands` (que nunca perdió el permiso).
--   Idempotente. Aplicar en Supabase → SQL Editor → Run.
-- ============================================================

grant delete on categories to authenticated;
