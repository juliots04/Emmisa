-- ============================================================
-- Emmisa · 0040 · Categorías: imagen + descripción
--   Agrega a `categories` los campos para el formulario ampliado del módulo
--   Categorías (subir imagen y descripción). La imagen se guarda en el bucket
--   público `productos` (mismo que productos), aislada por prefijo company_id.
--   RLS/grants ya existen (0004_inventario.sql / 0005_grants.sql) y cubren las
--   columnas nuevas: no requiere permisos adicionales.
--   Idempotente. Aplicar en Supabase → SQL Editor → Run.
-- ============================================================

alter table categories add column if not exists descripcion text;
alter table categories add column if not exists imagen_url  text;
-- Estado activo/inactivo (para activar/desactivar desde la tabla, baja lógica).
alter table categories add column if not exists activo      boolean not null default true;
