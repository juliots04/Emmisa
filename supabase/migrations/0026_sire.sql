-- ============================================================
-- Emmisa · 0026 SIRE (Sistema Integrado de Registros Electrónicos)
--   RVIE (Registro de Ventas) + RCE (Registro de Compras). Cada EMPRESA guarda sus
--   propias credenciales de API SUNAT (client_id/secret + usuario/clave SOL); el
--   token OAuth2 y las llamadas las hace la Edge Function `sire` server-side (CORS
--   bloquea el navegador). Las credenciales NO se leen por la Data API.
--   Aplicar DESPUÉS de 0025. Idempotente.
--   NOTA: los endpoints exactos de SUNAT se validan con un RUC real (no hay modo prueba).
-- ============================================================

-- Credenciales SIRE por empresa (secreto: sin policy SELECT; se leen con service_role).
create table if not exists sire_credentials (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null unique references companies(id) on delete cascade,
  client_id    text not null,
  client_secret text not null,
  sol_usuario  text not null,
  sol_clave    text not null,
  activo       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
alter table sire_credentials enable row level security;
-- Sin policies de lectura/escritura por la Data API: todo pasa por las RPC/Edge Function.
revoke all on sire_credentials from anon, authenticated;

-- Procesos SIRE (propuestas descargadas, tickets, estado) — visibles por la empresa.
create table if not exists sire_procesos (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  tipo        text not null check (tipo in ('RVIE', 'RCE')),
  periodo     text not null,               -- AAAAMM
  num_ticket  text,
  estado      text not null default 'solicitado', -- solicitado|procesando|terminado|error|aceptado
  resumen     jsonb,                       -- totales/resumen de la propuesta
  archivo_url text,                        -- enlace de descarga (si aplica)
  mensaje     text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table sire_procesos enable row level security;
drop policy if exists sire_procesos_sel on sire_procesos;
create policy sire_procesos_sel on sire_procesos for select
  using (company_id in (select auth_company_ids()));
grant select on sire_procesos to authenticated;

-- Guarda/actualiza las credenciales SIRE de la empresa (solo un admin de la empresa).
create or replace function guardar_credenciales_sire(
  p_company_id uuid, p_client_id text, p_client_secret text, p_sol_usuario text, p_sol_clave text
)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  if not is_company_admin(p_company_id) then
    raise exception 'Solo un administrador puede configurar SIRE';
  end if;
  insert into sire_credentials (company_id, client_id, client_secret, sol_usuario, sol_clave)
    values (p_company_id, p_client_id, p_client_secret, p_sol_usuario, p_sol_clave)
  on conflict (company_id) do update set
    client_id = excluded.client_id, client_secret = excluded.client_secret,
    sol_usuario = excluded.sol_usuario, sol_clave = excluded.sol_clave,
    activo = true, updated_at = now();
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function guardar_credenciales_sire(uuid, text, text, text, text) from public, anon;
grant execute on function guardar_credenciales_sire(uuid, text, text, text, text) to authenticated, service_role;

-- ¿La empresa tiene SIRE configurado? (no expone el secreto)
create or replace function tiene_sire(p_company_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'configurado', exists (select 1 from sire_credentials where company_id = p_company_id and activo),
    'usuario', (select sol_usuario from sire_credentials where company_id = p_company_id and activo))
  where p_company_id in (select auth_company_ids());
$$;
revoke execute on function tiene_sire(uuid) from public, anon;
grant execute on function tiene_sire(uuid) to authenticated, service_role;
