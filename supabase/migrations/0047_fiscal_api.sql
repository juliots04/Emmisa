-- ============================================================
-- Emmisa · 0047 Integración exclusiva con Emmisa Fiscal API
-- La API key nunca se guarda en tablas ni se expone al navegador. Vive como
-- secret de las Edge Functions. Esta tabla solo relaciona una empresa local
-- con un emisor del mismo RUC dentro de Fiscal API.
-- ============================================================

create table if not exists fiscal_integrations (
  company_id   uuid primary key references companies(id) on delete cascade,
  issuer_id    uuid not null,
  environment  text not null default 'beta'
    check (environment in ('beta', 'production')),
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

alter table fiscal_integrations enable row level security;
revoke all on fiscal_integrations from anon, authenticated;
grant all on fiscal_integrations to service_role;

-- Provisionamiento exclusivo del backend/operador. El usuario de Vue no puede
-- elegir otro issuer_id y tratar de emitir con el RUC de una empresa ajena.
create or replace function configurar_integracion_fiscal(
  p_company_id uuid,
  p_issuer_id uuid,
  p_environment text default 'beta'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'Solo el backend puede configurar la integración fiscal';
  end if;
  if p_environment not in ('beta', 'production') then
    raise exception 'Ambiente fiscal inválido';
  end if;
  insert into fiscal_integrations(company_id, issuer_id, environment, active, updated_at)
  values (p_company_id, p_issuer_id, p_environment, true, now())
  on conflict (company_id) do update
    set issuer_id = excluded.issuer_id,
        environment = excluded.environment,
        active = true,
        updated_at = now();
end $$;

revoke all on function configurar_integracion_fiscal(uuid, uuid, text) from public, anon, authenticated;
grant execute on function configurar_integracion_fiscal(uuid, uuid, text) to service_role;

-- El frontend puede consultar únicamente si está configurado y el ambiente; el
-- identificador interno del emisor no se devuelve.
create or replace function estado_integracion_fiscal(p_company_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_environment text;
begin
  if p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  select environment into v_environment
    from fiscal_integrations
   where company_id = p_company_id and active;
  return jsonb_build_object(
    'configured', v_environment is not null,
    'environment', v_environment
  );
end $$;

revoke all on function estado_integracion_fiscal(uuid) from public, anon;
grant execute on function estado_integracion_fiscal(uuid) to authenticated, service_role;

alter table documents
  add column if not exists fiscal_document_id uuid,
  add column if not exists fiscal_sunat_status text,
  add column if not exists fiscal_artifacts jsonb not null default '[]'::jsonb;

create unique index if not exists uq_documents_fiscal_document
  on documents(fiscal_document_id)
  where fiscal_document_id is not null;

-- Las credenciales de PSE antiguas dejan de participar en cualquier emisión.
update emisor_credentials set activo = false where activo;
