-- ============================================================
-- Konversa · Caja (apertura/cierre y movimientos) con RLS
-- Cómo usarlo: Supabase → SQL Editor → pega todo → Run
-- ============================================================

-- ==================== CAJA ====================
create table cash_sessions (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null references companies(id) on delete cascade,
  user_id        uuid not null references auth.users(id) on delete cascade,
  monto_inicial  numeric(12,2) not null default 0,
  monto_final    numeric(12,2),
  diferencia     numeric(12,2),
  estado         text not null default 'abierta',      -- abierta | cerrada
  abierto_en     timestamptz not null default now(),
  cerrado_en     timestamptz
);

create table cash_movements (
  id               uuid primary key default gen_random_uuid(),
  cash_session_id  uuid not null references cash_sessions(id) on delete cascade,
  tipo             text not null,                        -- ingreso | retiro
  monto            numeric(12,2) not null default 0,
  motivo           text,
  created_at       timestamptz not null default now()
);

-- ==================== SEGURIDAD (RLS multiempresa) ====================
-- Reutiliza auth_company_ids() definida en 0001_init.sql
alter table cash_sessions   enable row level security;
alter table cash_movements  enable row level security;

-- cash_sessions: solo sesiones de mis empresas
create policy cash_sessions_all on cash_sessions for all
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

-- cash_movements: solo movimientos de sesiones de mis empresas
create policy cash_movements_all on cash_movements for all
  using (cash_session_id in (select id from cash_sessions where company_id in (select auth_company_ids())))
  with check (cash_session_id in (select id from cash_sessions where company_id in (select auth_company_ids())));
