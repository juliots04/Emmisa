-- ============================================================
-- Konversa · Compras, proveedores y gastos (multi-tenant con RLS)
-- Cómo usarlo: Supabase → SQL Editor → pega todo → Run
-- Requiere 0001_init.sql (usa la función auth_company_ids()).
-- ============================================================

-- ==================== PROVEEDORES ====================
create table suppliers (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id) on delete cascade,
  ruc           text,
  razon_social  text not null,
  contacto      text,
  created_at    timestamptz not null default now()
);

-- ==================== COMPRAS ====================
create table purchases (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id) on delete cascade,
  supplier_id   uuid references suppliers(id) on delete set null,
  tipo_doc      text not null default '01',            -- 01 factura, 03 boleta, etc.
  serie_numero  text,
  fecha         date not null default current_date,
  total         numeric(12,2) not null default 0,
  created_at    timestamptz not null default now()
);

create table purchase_items (
  id           uuid primary key default gen_random_uuid(),
  purchase_id  uuid not null references purchases(id) on delete cascade,
  descripcion  text not null,
  cantidad     numeric(12,3) not null default 1,
  costo        numeric(12,2) not null default 0,
  total        numeric(12,2) not null default 0
);

-- ==================== GASTOS ====================
create table expenses (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  concepto    text not null,
  monto       numeric(12,2) not null default 0,
  fecha       date not null default current_date,
  categoria   text,
  created_at  timestamptz not null default now()
);

-- ==================== SEGURIDAD (RLS multiempresa) ====================
-- Activar RLS
alter table suppliers       enable row level security;
alter table purchases       enable row level security;
alter table purchase_items  enable row level security;
alter table expenses        enable row level security;

-- tablas hijas: solo filas de mis empresas
create policy suppliers_all  on suppliers  for all using (company_id in (select auth_company_ids())) with check (company_id in (select auth_company_ids()));
create policy purchases_all  on purchases  for all using (company_id in (select auth_company_ids())) with check (company_id in (select auth_company_ids()));
create policy expenses_all   on expenses   for all using (company_id in (select auth_company_ids())) with check (company_id in (select auth_company_ids()));

-- purchase_items: solo ítems de compras de mis empresas
create policy purchase_items_all on purchase_items for all
  using (purchase_id in (select id from purchases where company_id in (select auth_company_ids())))
  with check (purchase_id in (select id from purchases where company_id in (select auth_company_ids())));
