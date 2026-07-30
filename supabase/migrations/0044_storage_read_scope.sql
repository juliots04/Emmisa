-- ============================================================
-- Emmisa · 0044 · Seguridad: acotar la LECTURA del bucket 'productos' por empresa
--   PROBLEMA (auditoría): la policy `productos_read` era `using (bucket_id='productos')`
--   sin scoping, así que cualquiera con la anon key podía ENUMERAR objetos de otras
--   empresas vía storage.list('') / list('<companyId>') y luego bajar cada imagen.
--   Rompe el aislamiento multiempresa de lectura (fotos de productos/categorías/
--   marcas y logos de empresa).
--   SOLUCIÓN: la SELECT (que autoriza list()) se acota a las empresas del usuario con
--   _obj_company_ok(name) — igual que insert/update/delete (0021).
--   Las <img> con URL pública SIGUEN funcionando: el bucket es public=true y la ruta
--   /storage/v1/object/public/... sirve objetos por clave conocida SIN pasar por RLS;
--   lo único que se cierra es el listado/enumeración. La app nunca llama a .list().
--   Requiere 0021 (define _obj_company_ok). Idempotente. Supabase → SQL Editor → Run.
-- ============================================================

drop policy if exists productos_read on storage.objects;
create policy productos_read on storage.objects for select
  using (bucket_id = 'productos' and _obj_company_ok(name));
