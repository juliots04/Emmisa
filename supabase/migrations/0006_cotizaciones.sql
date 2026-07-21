-- ============================================================
-- Konversa · Cotizaciones (proformas) (multi-tenant con RLS)
-- Cómo usarlo: Supabase → SQL Editor → pega todo → Run
-- Requiere 0001_init.sql (usa la función auth_company_ids()).
-- ============================================================

-- ==================== COTIZACIONES ====================
create table quotes (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null references companies(id) on delete cascade,
  customer_id    uuid references customers(id) on delete set null,
  cliente_nombre text not null,
  fecha          date not null default current_date,
  moneda         text not null default 'PEN',
  total          numeric(12,2) not null default 0,
  estado         text not null default 'vigente',       -- vigente | aprobada | rechazada | vencida
  created_at     timestamptz not null default now()
);

create table quote_items (
  id               uuid primary key default gen_random_uuid(),
  quote_id         uuid not null references quotes(id) on delete cascade,
  descripcion      text not null,
  cantidad         numeric(12,3) not null default 1,
  precio_unitario  numeric(12,2) not null default 0,
  total            numeric(12,2) not null default 0
);

-- ==================== SEGURIDAD (RLS multiempresa) ====================
-- Activar RLS
alter table quotes       enable row level security;
alter table quote_items  enable row level security;

-- quotes: solo filas de mis empresas
create policy quotes_all on quotes for all using (company_id in (select auth_company_ids())) with check (company_id in (select auth_company_ids()));

-- quote_items: solo ítems de cotizaciones de mis empresas
create policy quote_items_all on quote_items for all
  using (quote_id in (select id from quotes where company_id in (select auth_company_ids())))
  with check (quote_id in (select id from quotes where company_id in (select auth_company_ids())));
