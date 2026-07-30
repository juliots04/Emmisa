-- ============================================================
-- Emmisa · 0035 Fixes de auditoría periférica (Revendedor / Billing)
--   (HIGH) companies_update_reseller carecía de WITH CHECK → por el OR-combine de
--          políticas permissive, un dueño de reseller podía saltarse el blindaje A10
--          y reescribir owner_id / ruc / estado de las empresas que administra
--          (secuestro de propiedad, corrupción de identidad fiscal, bypass de
--          suspensión por impago). Se recrea con WITH CHECK que congela esos campos.
--   (HIGH) suscripcion_permite_emitir solo miraba estado/fecha: los límites
--          cuantitativos del plan (max_comprobantes) NO se aplicaban (eran visuales).
--          Ahora cuenta los comprobantes emitidos en el periodo y bloquea al superar
--          el límite (0/null = ilimitado). La Edge Function `emitir` ya la invoca.
-- Rebasado sobre el estado VIVO de la BD. Aplicar en cualquier momento. Idempotente.
-- ============================================================

-- (1) companies_update_reseller con WITH CHECK (congela owner_id/ruc/estado/reseller_id)
drop policy if exists companies_update_reseller on companies;
create policy companies_update_reseller on companies for update
  using (reseller_id in (select auth_reseller_ids()))
  with check (
    reseller_id in (select auth_reseller_ids())
    and coalesce(owner_id::text, '')     = coalesce((select c.owner_id::text     from companies c where c.id = companies.id), '')
    and coalesce(ruc, '')                = coalesce((select c.ruc                from companies c where c.id = companies.id), '')
    and coalesce(estado, '')             = coalesce((select c.estado             from companies c where c.id = companies.id), '')
    and coalesce(reseller_id::text, '')  = coalesce((select c.reseller_id::text  from companies c where c.id = companies.id), '')
  );

-- (2) suscripcion_permite_emitir + límite cuantitativo del plan
create or replace function suscripcion_permite_emitir(p_company_id uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_estado text; v_fin date; v_ini date; v_plan uuid; v_max int; v_count int;
begin
  select estado, periodo_fin, periodo_inicio, plan_id into v_estado, v_fin, v_ini, v_plan
  from subscriptions
  where company_id = p_company_id
  order by periodo_inicio desc, created_at desc
  limit 1;

  if v_estado is null then return true; end if;                       -- sin suscripción: no bloquea
  if v_estado in ('vencida', 'suspendida', 'cancelada') then return false; end if;
  if v_estado = 'activa' and v_fin is not null and v_fin < current_date then return false; end if;

  -- Límite cuantitativo: comprobantes emitidos en el periodo vs plan.limites.max_comprobantes
  -- (0 o null = ilimitado). Se cuenta el comprobante recién creado, por eso el corte es '>'.
  select nullif(limites->>'max_comprobantes', '')::int into v_max from plans where id = v_plan;
  if v_max is not null and v_max > 0 then
    select count(*) into v_count from documents
      where company_id = p_company_id
        and tipo_doc in ('01','03','07','08')
        and estado_sunat <> 'rechazado'
        and fecha_emision >= coalesce(v_ini, date_trunc('month', current_date)::date)
        and fecha_emision <= coalesce(v_fin, current_date);
    if v_count > v_max then return false; end if;
  end if;

  return true;
end $$;
revoke execute on function suscripcion_permite_emitir(uuid) from public, anon;
grant execute on function suscripcion_permite_emitir(uuid) to authenticated, service_role;
