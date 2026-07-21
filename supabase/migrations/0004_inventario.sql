-- ============================================================
-- Konversa · Inventario (categorías, almacenes, stock, movimientos)
-- Cómo usarlo: Supabase → SQL Editor → pega todo → Run
-- Requiere 0001_init.sql (usa la función auth_company_ids() y la tabla products).
-- ============================================================

-- ==================== CATEGORÍAS ====================
create table categories (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  nombre      text not null,
  created_at  timestamptz not null default now()
);

-- ==================== ALMACENES ====================
create table warehouses (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  nombre      text not null,
  created_at  timestamptz not null default now()
);

-- ==================== STOCK (existencias por almacén) ====================
create table stock (
  id            uuid primary key default gen_random_uuid(),
  product_id    uuid not null references products(id) on delete cascade,
  warehouse_id  uuid not null references warehouses(id) on delete cascade,
  cantidad      numeric(12,3) not null default 0,
  unique (product_id, warehouse_id)
);

-- ==================== MOVIMIENTOS DE INVENTARIO ====================
create table inventory_movements (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id) on delete cascade,
  product_id    uuid not null references products(id) on delete cascade,
  warehouse_id  uuid not null references warehouses(id) on delete cascade,
  tipo          text not null,                          -- ingreso | salida | ajuste
  cantidad      numeric(12,3) not null default 0,
  motivo        text,
  created_at    timestamptz not null default now()
);

-- ==================== SEGURIDAD (RLS multiempresa) ====================
-- Activar RLS
alter table categories           enable row level security;
alter table warehouses           enable row level security;
alter table stock                enable row level security;
alter table inventory_movements  enable row level security;

-- tablas con company_id: solo filas de mis empresas
create policy categories_all           on categories          for all using (company_id in (select auth_company_ids())) with check (company_id in (select auth_company_ids()));
create policy warehouses_all           on warehouses          for all using (company_id in (select auth_company_ids())) with check (company_id in (select auth_company_ids()));
create policy inventory_movements_all  on inventory_movements for all using (company_id in (select auth_company_ids())) with check (company_id in (select auth_company_ids()));

-- stock: solo filas cuyo almacén pertenece a mis empresas
create policy stock_all on stock for all
  using (warehouse_id in (select id from warehouses where company_id in (select auth_company_ids())))
  with check (warehouse_id in (select id from warehouses where company_id in (select auth_company_ids())));
