-- ============================================================
-- Emmisa · 0021 Aislar el bucket 'productos' por empresa
--   PROBLEMA (auditoría): las policies de storage.objects dejaban que CUALQUIER
--   usuario autenticado subiera/editara/borrara imágenes de OTRA empresa.
--   SOLUCIÓN: escribir/editar/borrar solo si la carpeta raíz del objeto es una
--   empresa a la que pertenece el usuario. La lectura sigue pública (las fotos se
--   muestran por URL pública; no son datos sensibles como los comprobantes).
--   Rutas usadas por la app:
--     • Producto:  {company_id}/{uuid}.ext            -> foldername[1] = company_id
--     • Logo:      empresa/{company_id}/logo-*.ext     -> foldername[2] = company_id
--   Aplicar DESPUÉS de 0020. Supabase → SQL Editor → Run (rol postgres). Idempotente.
-- ============================================================

-- ¿El objeto vive bajo una carpeta de una empresa del usuario?
create or replace function _obj_company_ok(p_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when (storage.foldername(p_name))[1] = 'empresa'
      then (storage.foldername(p_name))[2] in (select auth_company_ids()::text)
    else (storage.foldername(p_name))[1] in (select auth_company_ids()::text)
  end
$$;

drop policy if exists productos_read   on storage.objects;
drop policy if exists productos_insert on storage.objects;
drop policy if exists productos_update on storage.objects;
drop policy if exists productos_delete on storage.objects;

-- Lectura pública (para <img src> con URL pública).
create policy productos_read on storage.objects for select
  using (bucket_id = 'productos');

-- Escritura/edición/borrado: solo dentro de la carpeta de una empresa del usuario.
create policy productos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'productos' and _obj_company_ok(name));
create policy productos_update on storage.objects for update to authenticated
  using (bucket_id = 'productos' and _obj_company_ok(name))
  with check (bucket_id = 'productos' and _obj_company_ok(name));
create policy productos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'productos' and _obj_company_ok(name));
