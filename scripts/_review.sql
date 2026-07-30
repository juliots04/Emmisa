select jsonb_pretty(jsonb_build_object(
  'tablas', (select count(*) from information_schema.tables where table_schema='public'),
  'funciones', (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'),
  'anon_sd_ejecutables', (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and has_function_privilege('anon',p.oid,'EXECUTE')),
  'mig_0031_billing', to_regprocedure('public.suscripcion_permite_emitir(uuid)') is not null,
  'mig_0031_estado_susc', to_regprocedure('public.estado_suscripcion(uuid)') is not null,
  'mig_0032_listar_miembros', to_regprocedure('public.listar_miembros(uuid)') is not null,
  'mig_0032_quitar_miembro', to_regprocedure('public.quitar_miembro(uuid,uuid)') is not null,
  'user_confirmar_baja', to_regprocedure('public.confirmar_baja(uuid)') is not null,
  'user_revertir_baja', to_regprocedure('public.revertir_baja(uuid)') is not null,
  'user_revertir_operacion', to_regprocedure('public._revertir_operacion(uuid)') is not null,
  'docs_total', (select count(*) from documents),
  'docs_por_estado', (select jsonb_object_agg(estado_sunat, c) from (select estado_sunat, count(*) c from documents group by estado_sunat) t),
  'series_correlativos', (select jsonb_object_agg(serie, correlativo) from series),
  'subscriptions', (select count(*) from subscriptions),
  'sire_credentials', (select count(*) from sire_credentials),
  'emisor_credentials', (select count(*) from emisor_credentials)
));
