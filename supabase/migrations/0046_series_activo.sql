-- ============================================================
-- Emmisa · 0046 · Series: flag activo/inactivo (separado del ciclo)
--   El serial tiene DOS ejes independientes:
--     • estado (ciclo): disponible | vendido | baja  → automático (compra/venta)
--     • activo (flag):   true/false                  → manual (activar/desactivar),
--       igual que categorías/marcas (baja lógica que no afecta el ciclo de venta).
--   RLS/grants de product_serials (0039) ya cubren la columna nueva. Idempotente.
--   Aplicar en Supabase → SQL Editor → Run.
-- ============================================================

alter table product_serials add column if not exists activo boolean not null default true;
