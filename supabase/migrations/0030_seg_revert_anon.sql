-- ============================================================
-- Emmisa · 0030 · Cierre de regresión de seguridad (anon EXECUTE)
--   Hallado en auditoría 2026-07-22: `anon` (la anon key PÚBLICA del navegador) podía
--   EJECUTAR funciones SECURITY DEFINER que mutan estado/stock/caja entre empresas
--   (confirmar_baja, revertir_baja, _revertir_operacion). Con solo un UUID, un atacante
--   con la anon key corrompía datos de CUALQUIER empresa (fuga cross-tenant).
--
--   Causa: Postgres otorga EXECUTE a PUBLIC por defecto al crear/replace una función;
--   `revoke from authenticated` NO basta — hay que revocar de PUBLIC (y de anon).
--   Ver la misma trampa en [[supabase-grants-gotcha]] y 0024/0026.
--
--   Estrategia: revocar EXECUTE de public+anon en TODAS las funciones SECURITY DEFINER
--   del esquema public, y re-otorgar solo a authenticated + service_role (los guards
--   internos —auth_company_ids()/is_company_admin()— hacen la autorización fina). Las
--   funciones internas (prefijo `_`) se otorgan solo a service_role.
--   Idempotente. Aplicar DESPUÉS de 0029.
-- ============================================================

do $$
declare
  r record;
begin
  for r in
    select p.oid,
           p.proname,
           pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef                                   -- solo SECURITY DEFINER
      and has_function_privilege('anon', p.oid, 'EXECUTE')  -- solo las que anon PUEDE ejecutar hoy
  loop
    execute format('revoke execute on function public.%I(%s) from public, anon;', r.proname, r.args);
    if left(r.proname, 1) = '_' then
      -- helper interno: nunca directamente desde el cliente
      execute format('grant execute on function public.%I(%s) to service_role;', r.proname, r.args);
    else
      execute format('grant execute on function public.%I(%s) to authenticated, service_role;', r.proname, r.args);
    end if;
    raise notice 'hardened: %(%)', r.proname, r.args;
  end loop;
end $$;

-- Verificación: no debe quedar NINGUNA función SECURITY DEFINER ejecutable por anon.
-- (correr aparte tras aplicar)
--   select count(*) as anon_ejecutables
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname='public' and p.prosecdef
--     and has_function_privilege('anon', p.oid, 'EXECUTE');   -- debe dar 0
