-- ============================================================
-- 0023 · Realtime: publica las tablas clave para que el frontend
-- reciba INSERT/UPDATE/DELETE en vivo (Supabase Realtime).
-- Solo tablas con company_id (el cliente filtra por empresa). stock y
-- cash_movements se aíslan por join → se cubren vía inventory_movements y documents.
--
-- - Agrega cada tabla a la publicación `supabase_realtime` (idempotente).
-- - `replica identity full`: para que el filtro por company_id funcione también
--   en DELETE (por defecto solo se registra la PK, sin company_id).
--
-- La seguridad multiempresa la sostiene el RLS existente + el filtro
-- company_id=eq.<id> que pone el cliente. Aplica esta migración en el SQL Editor.
-- ============================================================

do $$
declare
  t text;
  tablas text[] := array[
    'documents', 'products', 'inventory_movements',
    'cash_sessions', 'customers',
    'quotes', 'purchases', 'expenses', 'suppliers'
  ];
begin
  foreach t in array tablas loop
    -- replica identity full → company_id disponible en todos los eventos
    execute format('alter table public.%I replica identity full', t);

    -- agregar a la publicación de realtime solo si aún no está
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
