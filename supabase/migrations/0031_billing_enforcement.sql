-- ============================================================
-- Emmisa · 0031 · Enforcement de suscripción (billing)
--   Bloqueante #1 de la auditoría go-to-market: "un moroso emite igual" — nada consultaba
--   el estado de la suscripción antes de emitir. Sin esto no hay negocio de reventa.
--   Este script agrega:
--     • suscripcion_permite_emitir(company)  -> boolean  (lo usa la Edge Function `emitir`)
--     • estado_suscripcion(company)          -> jsonb    (para el banner en la UI)
--     • expirar_suscripciones()              -> int      (cron diario: activa->vencida al pasar la fecha)
--   Regla: si la empresa NO tiene suscripción registrada, NO se bloquea (aún no provisionada).
--   Si la última suscripción está vencida/suspendida/cancelada, o activa pero con
--   periodo_fin < hoy, se BLOQUEA la emisión.
--   Idempotente. Aplicar DESPUÉS de 0030.
-- ============================================================

-- ¿La empresa puede emitir según su suscripción? (mira SOLO la última suscripción)
create or replace function suscripcion_permite_emitir(p_company_id uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_estado text;
  v_fin    date;
begin
  select estado, periodo_fin into v_estado, v_fin
  from subscriptions
  where company_id = p_company_id
  order by periodo_inicio desc, created_at desc
  limit 1;

  if v_estado is null then
    return true;                                   -- sin suscripción: no bloquea (empresa no provisionada)
  end if;
  if v_estado in ('vencida', 'suspendida', 'cancelada') then
    return false;
  end if;
  if v_estado = 'activa' and v_fin is not null and v_fin < current_date then
    return false;                                  -- activa pero vencida por fecha
  end if;
  return true;
end $$;
revoke execute on function suscripcion_permite_emitir(uuid) from public, anon;
grant execute on function suscripcion_permite_emitir(uuid) to authenticated, service_role;

-- Estado legible para la UI (banner "tu plan vence en X días" / "regulariza el pago").
-- Solo lo puede consultar un miembro de la empresa.
create or replace function estado_suscripcion(p_company_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_estado text;
  v_fin    date;
  v_plan   text;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'No autorizado para esta empresa';
  end if;
  select s.estado, s.periodo_fin, p.nombre into v_estado, v_fin, v_plan
  from subscriptions s
  left join plans p on p.id = s.plan_id
  where s.company_id = p_company_id
  order by s.periodo_inicio desc, s.created_at desc
  limit 1;

  return jsonb_build_object(
    'tiene_suscripcion', v_estado is not null,
    'estado', coalesce(v_estado, 'sin_suscripcion'),
    'plan', v_plan,
    'periodo_fin', v_fin,
    'dias_restantes', case when v_fin is null then null else (v_fin - current_date) end,
    'puede_emitir', suscripcion_permite_emitir(p_company_id)
  );
end $$;
revoke execute on function estado_suscripcion(uuid) from public, anon;
grant execute on function estado_suscripcion(uuid) to authenticated, service_role;

-- Cron diario: marca 'vencida' toda suscripción activa cuyo periodo_fin ya pasó.
create or replace function expirar_suscripciones()
returns integer language sql security definer set search_path = public as $$
  with upd as (
    update subscriptions
      set estado = 'vencida'
    where estado = 'activa'
      and periodo_fin is not null
      and periodo_fin < current_date
    returning 1
  )
  select count(*)::int from upd;
$$;
revoke execute on function expirar_suscripciones() from public, anon, authenticated;
grant execute on function expirar_suscripciones() to service_role;

-- Programa el cron si pg_cron está disponible (en Supabase se habilita desde el dashboard).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      perform cron.schedule('emmisa-expirar-suscripciones', '5 0 * * *', 'select expirar_suscripciones();');
    exception when others then
      -- ya existe / no se pudo re-agendar: no es fatal
      null;
    end;
  end if;
end $$;
