-- ============================================================
-- Emmisa · 0039 · Catálogo ampliado + Números de serie de productos
--   Parte del rediseño del módulo «Productos/Servicios»:
--     1) Nuevas columnas en `products` (campos del formulario estilo facturador:
--        fecha de vencimiento, lotes/series, ISC, detracción, percepción, canje por
--        puntos, restricción en CPE y datos de compra para el margen).
--     2) Tabla `product_serials`: registro de números de serie por producto
--        (para productos con «¿Maneja series?» activado).
--   Requiere 0001_init.sql (products, auth_company_ids()) y 0010/0011 (brands, brand_id).
--   Idempotente. Aplicar en Supabase → SQL Editor → Run.
-- ============================================================

-- ==================== 1) COLUMNAS NUEVAS EN products ====================
-- Compra / margen
alter table products add column if not exists tipo_afectacion_compra text;      -- cat. 07 para la compra
alter table products add column if not exists aplica_ganancia         boolean not null default false;
alter table products add column if not exists porcentaje_ganancia     numeric(6,2) not null default 0;
alter table products add column if not exists incluye_isc             boolean not null default false;

-- Tributos / restricciones (catálogo del comprobante)
alter table products add column if not exists detraccion              boolean not null default false; -- sujeto a detracción
alter table products add column if not exists percepcion              boolean not null default false; -- incluye percepción
alter table products add column if not exists restringir_cpe          boolean not null default false; -- restringir venta en CPE
alter table products add column if not exists canje_puntos            boolean not null default false; -- ¿canjeable por puntos?

-- Trazabilidad de existencias
alter table products add column if not exists fecha_vencimiento       date;
alter table products add column if not exists maneja_lotes            boolean not null default false;
alter table products add column if not exists maneja_series           boolean not null default false;

-- ==================== 2) NÚMEROS DE SERIE POR PRODUCTO ====================
create table if not exists product_serials (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  product_id  uuid not null references products(id) on delete cascade,
  serie       text not null,                              -- número de serie / serial
  estado      text not null default 'disponible',         -- disponible | vendido | baja
  nota        text,
  created_at  timestamptz not null default now(),
  unique (company_id, product_id, serie)
);

create index if not exists product_serials_product_idx on product_serials (product_id);

alter table product_serials enable row level security;

-- Solo filas de mis empresas (patrón estándar multiempresa).
drop policy if exists product_serials_all on product_serials;
create policy product_serials_all on product_serials for all
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

-- La Data API opera esta tabla directamente (no hay secreto): grant a authenticated.
-- NO se otorga a anon (la anon key es pública; ver 0030 y [[supabase-grants-gotcha]]).
grant select, insert, update, delete on product_serials to authenticated;
grant all privileges on product_serials to service_role;

-- ==================== 3) REALTIME ====================
-- Publica product_serials para refresco en vivo de la página Series.
do $$
begin
  execute 'alter table public.product_serials replica identity full';
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'product_serials'
  ) then
    execute 'alter publication supabase_realtime add table public.product_serials';
  end if;
end $$;
