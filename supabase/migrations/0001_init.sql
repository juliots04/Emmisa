-- ============================================================
-- Konversa · Esquema base (multi-tenant con RLS)
-- Cómo usarlo: Supabase → SQL Editor → pega todo → Run
-- ============================================================

create extension if not exists "pgcrypto";

-- ==================== TENANCY (multiempresa) ====================
create table companies (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references auth.users(id) on delete cascade,
  ruc           text not null,
  razon_social  text not null,
  regimen       text not null default 'RER',        -- RER | RMT | GENERAL | NRUS
  direccion     text,
  ubigeo        text,
  logo_url      text,
  estado        text not null default 'activo',
  created_at    timestamptz not null default now()
);

create table memberships (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  company_id  uuid not null references companies(id) on delete cascade,
  role        text not null default 'admin',        -- admin | cajero | vendedor | contador
  created_at  timestamptz not null default now(),
  unique (user_id, company_id)
);

create table establishments (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  codigo      text not null default '0000',
  nombre      text not null,
  direccion   text,
  ubigeo      text,
  created_at  timestamptz not null default now()
);

create table series (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references companies(id) on delete cascade,
  establishment_id  uuid references establishments(id) on delete set null,
  tipo_doc          text not null,                  -- 01 factura, 03 boleta, 07 NC, 08 ND
  serie             text not null,                  -- F001, B001
  correlativo       int  not null default 0,
  unique (company_id, tipo_doc, serie)
);

-- ==================== CATÁLOGO / CLIENTES ====================
create table products (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references companies(id) on delete cascade,
  sku              text,
  nombre           text not null,
  tipo             text not null default 'bien',    -- bien | servicio
  unidad_medida    text not null default 'NIU',
  tipo_afectacion  text not null default '10',       -- 10 gravado, 20 exonerado, 30 inafecto
  precio           numeric(12,2) not null default 0,
  costo            numeric(12,2) not null default 0,
  controla_stock   boolean not null default true,
  activo           boolean not null default true,
  created_at       timestamptz not null default now()
);

create table customers (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id) on delete cascade,
  tipo_doc      text not null default '1',           -- 1 DNI, 6 RUC
  num_doc       text,
  denominacion  text not null,
  direccion     text,
  email         text,
  created_at    timestamptz not null default now()
);

-- ==================== COMPROBANTES ====================
create table documents (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references companies(id) on delete cascade,
  customer_id      uuid references customers(id) on delete set null,
  tipo_doc         text not null,                    -- 01 factura, 03 boleta
  serie            text not null,
  correlativo      int  not null,
  moneda           text not null default 'PEN',
  total_gravado    numeric(12,2) not null default 0,
  total_igv        numeric(12,2) not null default 0,
  total            numeric(12,2) not null default 0,
  estado_sunat     text not null default 'pendiente',-- pendiente|aceptado|rechazado|anulado
  cdr              text,
  xml_url          text,
  pdf_url          text,
  ref_document_id  uuid references documents(id),    -- para notas de crédito/débito
  idempotency_key  text,
  created_at       timestamptz not null default now(),
  unique (company_id, tipo_doc, serie, correlativo)
);

create table document_items (
  id               uuid primary key default gen_random_uuid(),
  document_id      uuid not null references documents(id) on delete cascade,
  product_id       uuid references products(id) on delete set null,
  descripcion      text not null,
  cantidad         numeric(12,3) not null default 1,
  valor_unitario   numeric(12,2) not null default 0,
  precio_unitario  numeric(12,2) not null default 0,
  igv              numeric(12,2) not null default 0,
  total            numeric(12,2) not null default 0
);

-- ==================== SEGURIDAD (RLS multiempresa) ====================
-- Empresas a las que pertenece el usuario actual (security definer = puede leer memberships)
create or replace function auth_company_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select company_id from memberships where user_id = auth.uid()
$$;

-- Al crear una empresa, el creador queda como admin automáticamente
create or replace function on_company_created()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into memberships (user_id, company_id, role) values (new.owner_id, new.id, 'admin');
  return new;
end $$;
create trigger trg_company_created after insert on companies
  for each row execute function on_company_created();

-- Activar RLS
alter table companies       enable row level security;
alter table memberships     enable row level security;
alter table establishments  enable row level security;
alter table series          enable row level security;
alter table products        enable row level security;
alter table customers       enable row level security;
alter table documents       enable row level security;
alter table document_items  enable row level security;

-- companies
create policy companies_select on companies for select using (id in (select auth_company_ids()));
create policy companies_insert on companies for insert with check (owner_id = auth.uid());
create policy companies_update on companies for update using (id in (select auth_company_ids()));

-- memberships (solo el dueño de la empresa puede agregar miembros)
create policy memberships_select on memberships for select using (user_id = auth.uid());
create policy memberships_insert on memberships for insert
  with check (company_id in (select id from companies where owner_id = auth.uid()));

-- tablas hijas: solo filas de mis empresas
create policy estab_all     on establishments for all using (company_id in (select auth_company_ids())) with check (company_id in (select auth_company_ids()));
create policy series_all     on series        for all using (company_id in (select auth_company_ids())) with check (company_id in (select auth_company_ids()));
create policy products_all   on products      for all using (company_id in (select auth_company_ids())) with check (company_id in (select auth_company_ids()));
create policy customers_all  on customers     for all using (company_id in (select auth_company_ids())) with check (company_id in (select auth_company_ids()));
create policy documents_all  on documents     for all using (company_id in (select auth_company_ids())) with check (company_id in (select auth_company_ids()));
create policy docitems_all   on document_items for all
  using (document_id in (select id from documents where company_id in (select auth_company_ids())))
  with check (document_id in (select id from documents where company_id in (select auth_company_ids())));
