-- ============================================================
-- Emmisa · 0041 · Precios por almacén (por producto)
--   Guarda un precio de venta opcional por almacén, como mapa JSON:
--     { "<warehouse_id>": 12.5, ... }
--   Es informativo/base para listas de precios por local; el POS/emisión
--   siguen usando `precio` mientras no se integre explícitamente.
--   Idempotente. Aplicar en Supabase → SQL Editor → Run.
-- ============================================================

alter table products
  add column if not exists precios_almacen jsonb not null default '{}'::jsonb;
