-- ============================================================
-- Amplía products con los campos de un formulario completo (estilo Pro9)
-- Supabase → SQL Editor → pega TODO → Run
-- ============================================================

alter table products add column if not exists nombre_secundario  text;
alter table products add column if not exists descripcion         text;
alter table products add column if not exists modelo              text;
alter table products add column if not exists barcode             text;
alter table products add column if not exists moneda              text not null default 'PEN';
alter table products add column if not exists incluye_igv         boolean not null default true;
alter table products add column if not exists stock_minimo        numeric(12,3) not null default 0;
alter table products add column if not exists codigo_sunat        text;
alter table products add column if not exists linea_producto      text;
alter table products add column if not exists registro_sanitario  text;
alter table products add column if not exists codigo_digemid      text;
alter table products add column if not exists codigo_fabrica      text;

-- Asegura permisos de la Data API sobre las columnas/tablas
grant all privileges on all tables in schema public to anon, authenticated, service_role;
