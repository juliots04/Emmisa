-- ============================================================
-- Konversa · Campos de comprobante para cumplimiento SUNAT real
-- Añade a `documents` los totales por afectación, los datos del receptor
-- "varios" (que hoy se perdían), moneda/tipo de cambio, fecha de emisión,
-- hash/QR, ticket asíncrono y condición de pago (para cuentas por cobrar).
-- Crea la tabla `payments` (pagos y abonos) y extiende compras.
-- Idempotente. Supabase → SQL Editor → pega TODO → Run
-- ============================================================

-- ==================== documents ====================
alter table documents add column if not exists establishment_id     uuid references establishments(id) on delete set null;
-- Totales por tipo de afectación (SUNAT exige desglose)
alter table documents add column if not exists total_exonerado      numeric(12,2) not null default 0;
alter table documents add column if not exists total_inafecto       numeric(12,2) not null default 0;
alter table documents add column if not exists total_gratuito       numeric(12,2) not null default 0;
alter table documents add column if not exists total_icbper         numeric(12,2) not null default 0;
alter table documents add column if not exists total_isc            numeric(12,2) not null default 0;
alter table documents add column if not exists descuento_global     numeric(12,2) not null default 0;
-- Moneda / tipo de cambio
alter table documents add column if not exists tipo_cambio          numeric(12,3) not null default 1;
-- Fechas y firma
alter table documents add column if not exists fecha_emision        date not null default current_date;
alter table documents add column if not exists fecha_vencimiento    date;
alter table documents add column if not exists hash                 text;   -- digest de la firma
alter table documents add column if not exists codigo_qr            text;
alter table documents add column if not exists sunat_ticket         text;   -- ticket asíncrono (boletas/resúmenes)
alter table documents add column if not exists sunat_error          text;   -- observación/rechazo
-- Receptor "varios" persistido (antes solo se guardaba customer_id)
alter table documents add column if not exists receptor_tipo_doc    text;
alter table documents add column if not exists receptor_num_doc     text;
alter table documents add column if not exists receptor_denominacion text;
alter table documents add column if not exists receptor_direccion   text;
-- Condición de pago y cuentas por cobrar
alter table documents add column if not exists condicion_pago       text not null default 'contado'; -- contado | credito
alter table documents add column if not exists estado_pago          text not null default 'pagado';  -- pagado | pendiente | parcial
alter table documents add column if not exists saldo                numeric(12,2) not null default 0;
-- Notas: motivo (catálogo 09 NC / 10 ND)
alter table documents add column if not exists motivo_codigo        text;
alter table documents add column if not exists motivo_desc          text;

-- ==================== document_items ====================
alter table document_items add column if not exists tipo_afectacion text not null default '10'; -- 10 grav, 20 exon, 30 inaf, 21 gratuito
alter table document_items add column if not exists unidad_medida   text not null default 'NIU';
alter table document_items add column if not exists codigo_producto text;
alter table document_items add column if not exists descuento       numeric(12,2) not null default 0;

-- ==================== products (FK catálogo) ====================
alter table products add column if not exists category_id uuid references categories(id) on delete set null;
alter table products add column if not exists brand_id    uuid references brands(id)     on delete set null;

-- ==================== caja / compras: establecimiento y CxP ====================
alter table cash_sessions add column if not exists establishment_id uuid references establishments(id) on delete set null;
alter table cash_sessions add column if not exists terminal_id      text;

alter table purchases add column if not exists moneda            text not null default 'PEN';
alter table purchases add column if not exists total_gravado     numeric(12,2) not null default 0;
alter table purchases add column if not exists total_igv         numeric(12,2) not null default 0;
alter table purchases add column if not exists condicion_pago    text not null default 'contado';
alter table purchases add column if not exists estado_pago       text not null default 'pagado';
alter table purchases add column if not exists saldo             numeric(12,2) not null default 0;
alter table purchases add column if not exists fecha_vencimiento date;
alter table purchases add column if not exists afecta_inventario boolean not null default false;
alter table purchases add column if not exists warehouse_id      uuid references warehouses(id) on delete set null;

alter table purchase_items add column if not exists product_id uuid references products(id) on delete set null;

-- ==================== payments (pagos y abonos: CxC / CxP) ====================
-- Un registro por cada cobro (a un comprobante) o pago (a una compra).
create table if not exists payments (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references companies(id) on delete cascade,
  tipo             text not null default 'cobro',   -- cobro (CxC) | pago (CxP)
  document_id      uuid references documents(id) on delete cascade,
  purchase_id      uuid references purchases(id) on delete cascade,
  cash_session_id  uuid references cash_sessions(id) on delete set null,
  medio            text not null default 'efectivo',
  monto            numeric(12,2) not null default 0,
  referencia       text,
  fecha            date not null default current_date,
  created_at       timestamptz not null default now()
);

create index if not exists ix_payments_document on payments(document_id);
create index if not exists ix_payments_purchase on payments(purchase_id);
create index if not exists ix_documents_estado_pago on documents(company_id, estado_pago) where estado_pago <> 'pagado';

alter table payments enable row level security;
drop policy if exists payments_all on payments;
create policy payments_all on payments for all
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

-- ==================== GRANTS (Data API) ====================
grant all privileges on all tables    in schema public to anon, authenticated, service_role;
grant all privileges on all sequences in schema public to anon, authenticated, service_role;
grant execute        on all functions in schema public to anon, authenticated, service_role;
