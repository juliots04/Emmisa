-- ============================================================
-- Konversa · 0035 · Control optimista de concurrencia en products
--   Aplicar DESPUÉS de 0034.
--   Añade products.updated_at (auto) para detectar "lost update": si dos sesiones
--   editan el mismo producto, la segunda al guardar recibe error en vez de pisar en
--   silencio los cambios de la primera (p. ej. reactivar un producto desactivado).
-- ============================================================

alter table products add column if not exists updated_at timestamptz not null default now();

create or replace function _touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_products_updated_at on products;
create trigger trg_products_updated_at
  before update on products
  for each row execute function _touch_updated_at();
