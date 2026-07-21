-- ============================================================
-- Konversa · Capa SaaS / marca blanca (revendedor)
-- Añade el bloque de PLATAFORMA que faltaba por completo:
--   resellers, plans, subscriptions, subscription_payments,
--   brands, webhooks, audit_events, emisor_credentials.
-- Aísla por RLS igual que el resto. Idempotente (create if not exists).
-- Cómo usarlo: Supabase → SQL Editor → pega TODO → Run
-- ============================================================

-- ==================== REVENDEDOR (marca blanca) ====================
create table if not exists resellers (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users(id) on delete cascade,
  nombre      text not null,
  dominio     text,                                   -- subdominio/dominio propio
  branding    jsonb not null default '{}'::jsonb,     -- { logo_url, color_primario, color_secundario, nombre_comercial }
  activo      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- Cada empresa emisora puede pertenecer a un revendedor.
alter table companies add column if not exists reseller_id uuid references resellers(id) on delete set null;
alter table companies add column if not exists config      jsonb not null default '{}'::jsonb;

-- ==================== PLANES / SUSCRIPCIONES ====================
create table if not exists plans (
  id           uuid primary key default gen_random_uuid(),
  reseller_id  uuid not null references resellers(id) on delete cascade,
  nombre       text not null,
  precio       numeric(12,2) not null default 0,
  moneda       text not null default 'PEN',
  periodicidad text not null default 'mensual',       -- mensual | anual
  limites      jsonb not null default '{}'::jsonb,     -- { max_comprobantes, max_empresas, max_usuarios }
  activo       boolean not null default true,
  created_at   timestamptz not null default now()
);

create table if not exists subscriptions (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null references companies(id) on delete cascade,
  plan_id        uuid references plans(id) on delete set null,
  estado         text not null default 'activa',       -- activa | vencida | suspendida | cancelada
  periodo_inicio date not null default current_date,
  periodo_fin    date,
  created_at     timestamptz not null default now()
);

create table if not exists subscription_payments (
  id              uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references subscriptions(id) on delete cascade,
  monto           numeric(12,2) not null default 0,
  medio           text,                                -- yape | transferencia | tarjeta | efectivo
  estado          text not null default 'pagado',      -- pagado | pendiente | fallido
  referencia      text,
  fecha           date not null default current_date,
  created_at      timestamptz not null default now()
);

-- ==================== MARCAS DE PRODUCTO ====================
create table if not exists brands (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  nombre      text not null,
  created_at  timestamptz not null default now()
);

-- ==================== WEBHOOKS ====================
create table if not exists webhooks (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  url         text not null,
  eventos     text[] not null default '{}',
  secret      text,
  activo      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- ==================== AUDITORÍA ====================
create table if not exists audit_events (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid references companies(id) on delete set null,
  user_id     uuid references auth.users(id) on delete set null,
  accion      text not null,                           -- insert | update | delete | emitir | anular | login...
  entidad     text,
  entidad_id  uuid,
  payload     jsonb,
  created_at  timestamptz not null default now()
);

-- ==================== CREDENCIALES DEL EMISOR (SENSIBLE) ====================
-- Guarda el token del PSE/OSE (APISUNAT/Nubefact) por empresa.
-- RLS: los admin de la empresa pueden ESCRIBIR (upsert) pero NO LEER el token de vuelta.
-- Solo la Edge Function (service_role, que salta RLS) lo lee para emitir.
create table if not exists emisor_credentials (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  provider    text not null default 'apisunat',        -- apisunat | nubefact
  persona_id  text,                                    -- APISUNAT personaId
  token       text,                                    -- APISUNAT personaToken (secreto)
  extra       jsonb not null default '{}'::jsonb,      -- otros datos del proveedor
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (company_id, provider)
);

-- ==================== HELPERS DE RLS ====================
-- Revendedores que administra el usuario actual.
create or replace function auth_reseller_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select id from resellers where owner_id = auth.uid()
$$;

-- ¿El usuario actual es admin (rol 'admin') de esta empresa?
create or replace function is_company_admin(p_company_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from memberships
    where user_id = auth.uid() and company_id = p_company_id and role = 'admin'
  )
$$;

-- Empresas cuyo revendedor administra el usuario actual (para el panel del reseller).
create or replace function auth_reseller_company_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select id from companies where reseller_id in (select auth_reseller_ids())
$$;

-- ==================== RLS ====================
alter table resellers             enable row level security;
alter table plans                 enable row level security;
alter table subscriptions         enable row level security;
alter table subscription_payments enable row level security;
alter table brands                enable row level security;
alter table webhooks              enable row level security;
alter table audit_events          enable row level security;
alter table emisor_credentials    enable row level security;

-- resellers: el dueño gestiona lo suyo.
drop policy if exists resellers_all on resellers;
create policy resellers_all on resellers for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- companies: además del owner/miembro (0007), el revendedor ve y gestiona sus empresas.
drop policy if exists companies_select_reseller on companies;
create policy companies_select_reseller on companies for select
  using (reseller_id in (select auth_reseller_ids()));
drop policy if exists companies_update_reseller on companies;
create policy companies_update_reseller on companies for update
  using (reseller_id in (select auth_reseller_ids()));

-- plans: el revendedor gestiona; los miembros de una empresa del revendedor pueden verlos.
drop policy if exists plans_reseller_all on plans;
create policy plans_reseller_all on plans for all
  using (reseller_id in (select auth_reseller_ids()))
  with check (reseller_id in (select auth_reseller_ids()));
drop policy if exists plans_member_select on plans;
create policy plans_member_select on plans for select
  using (reseller_id in (
    select reseller_id from companies where id in (select auth_company_ids())
  ));

-- subscriptions: miembros ven la de su empresa; el revendedor gestiona.
drop policy if exists subs_member_select on subscriptions;
create policy subs_member_select on subscriptions for select
  using (company_id in (select auth_company_ids())
      or company_id in (select auth_reseller_company_ids()));
drop policy if exists subs_reseller_all on subscriptions;
create policy subs_reseller_all on subscriptions for all
  using (company_id in (select auth_reseller_company_ids()))
  with check (company_id in (select auth_reseller_company_ids()));

-- subscription_payments: vía la suscripción (empresa del revendedor).
drop policy if exists subpays_all on subscription_payments;
create policy subpays_all on subscription_payments for all
  using (subscription_id in (
    select id from subscriptions where company_id in (
      select auth_reseller_company_ids() union select auth_company_ids())))
  with check (subscription_id in (
    select id from subscriptions where company_id in (select auth_reseller_company_ids())));

-- brands / webhooks: aislados por empresa (patrón estándar).
drop policy if exists brands_all on brands;
create policy brands_all on brands for all
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));
drop policy if exists webhooks_all on webhooks;
create policy webhooks_all on webhooks for all
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

-- audit_events: los miembros de la empresa pueden LEER; la escritura la hacen triggers (definer).
drop policy if exists audit_select on audit_events;
create policy audit_select on audit_events for select
  using (company_id in (select auth_company_ids()));

-- emisor_credentials: los admin ESCRIBEN sus credenciales; NADIE (authenticated) las LEE.
-- (sin policy de SELECT → la Data API no puede leer el token; solo service_role lo lee).
drop policy if exists emisorcred_insert on emisor_credentials;
create policy emisorcred_insert on emisor_credentials for insert
  with check (is_company_admin(company_id));
drop policy if exists emisorcred_update on emisor_credentials;
create policy emisorcred_update on emisor_credentials for update
  using (is_company_admin(company_id)) with check (is_company_admin(company_id));
drop policy if exists emisorcred_delete on emisor_credentials;
create policy emisorcred_delete on emisor_credentials for delete
  using (is_company_admin(company_id));

-- ==================== Helpers seguros de credenciales ====================
-- El frontend NO puede leer el token (sin policy SELECT). Estas funciones
-- (security definer) permiten guardar y consultar el ESTADO sin exponer el secreto.
create or replace function guardar_credenciales(
  p_company_id uuid, p_provider text, p_persona_id text, p_token text, p_extra jsonb default '{}'::jsonb
)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not is_company_admin(p_company_id) then
    raise exception 'Solo un admin puede configurar las credenciales del emisor';
  end if;
  insert into emisor_credentials (company_id, provider, persona_id, token, extra, updated_at)
    values (p_company_id, coalesce(p_provider,'apisunat'), p_persona_id, p_token, coalesce(p_extra,'{}'::jsonb), now())
    on conflict (company_id, provider)
    do update set persona_id = excluded.persona_id, token = excluded.token,
                  extra = excluded.extra, activo = true, updated_at = now();
  return jsonb_build_object('ok', true, 'provider', coalesce(p_provider,'apisunat'));
end $$;
grant execute on function guardar_credenciales(uuid, text, text, text, jsonb) to authenticated, service_role;

create or replace function tiene_credenciales(p_company_id uuid, p_provider text default null)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from emisor_credentials
    where company_id = p_company_id and activo
      and coalesce(token,'') <> ''
      and (p_provider is null or provider = p_provider)
      and company_id in (select auth_company_ids()));
$$;
grant execute on function tiene_credenciales(uuid, text) to authenticated, service_role;

-- ==================== GRANTS (Data API) ====================
-- Reaplica el patrón del proyecto para las tablas nuevas.
grant all privileges on all tables    in schema public to anon, authenticated, service_role;
grant all privileges on all sequences in schema public to anon, authenticated, service_role;
grant execute        on all functions in schema public to anon, authenticated, service_role;

-- Defensa extra: el token del emisor NO debe ser accesible por el rol anónimo.
revoke all on emisor_credentials from anon;
