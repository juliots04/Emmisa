-- ============================================================
-- Emmisa · 0046 · Elimina products.nombre_secundario
--   Campo opcional heredado del facturador de referencia (nombre alterno); no lo
--   pide SUNAT ni lo usa la app. Se retira del formulario y del esquema.
--   Idempotente. Aplicar en Supabase → SQL Editor → Run.
-- ============================================================

alter table products drop column if exists nombre_secundario;
