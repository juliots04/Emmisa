-- ============================================================
-- Emmisa · 0042 · Marcas: imagen + descripción + estado
--   Réplica de 0040 (categorías) para el módulo Marcas: agrega a `brands` los
--   campos del formulario ampliado (subir imagen, descripción) y el estado
--   activo/inactivo (baja lógica, para activar/desactivar desde la tabla).
--   La imagen se guarda en el bucket público `productos` (aislada por company_id).
--   RLS/grants ya existen (0010_plataforma.sql) y cubren las columnas nuevas.
--   Idempotente. Aplicar en Supabase → SQL Editor → Run.
-- ============================================================

alter table brands add column if not exists descripcion text;
alter table brands add column if not exists imagen_url  text;
alter table brands add column if not exists activo      boolean not null default true;
