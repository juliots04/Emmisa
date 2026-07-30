  -- ============================================================
  -- Konversa · Imagen de producto
  --   • Columna products.imagen_url
  --   • Bucket público de Storage 'productos' + policies (subir/leer/borrar)
  -- Aplicar después de 0017. Supabase → SQL Editor → Run
  -- ============================================================

  alter table products add column if not exists imagen_url text;

  -- Bucket público para las fotos de producto (lectura pública, 5MB, solo imágenes).
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('productos', 'productos', true, 5242880,
          array['image/png','image/jpeg','image/jpg','image/webp','image/gif'])
  on conflict (id) do update
    set public = true,
        file_size_limit = 5242880,
        allowed_mime_types = array['image/png','image/jpeg','image/jpg','image/webp','image/gif'];

  -- Policies sobre storage.objects para el bucket 'productos'.
  drop policy if exists productos_read   on storage.objects;
  drop policy if exists productos_insert on storage.objects;
  drop policy if exists productos_update on storage.objects;
  drop policy if exists productos_delete on storage.objects;

  create policy productos_read on storage.objects for select
    using (bucket_id = 'productos');
  create policy productos_insert on storage.objects for insert to authenticated
    with check (bucket_id = 'productos');
  create policy productos_update on storage.objects for update to authenticated
    using (bucket_id = 'productos') with check (bucket_id = 'productos');
  create policy productos_delete on storage.objects for delete to authenticated
    using (bucket_id = 'productos');
