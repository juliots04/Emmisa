-- ============================================================
-- Emmisa · 0032 · Gestión de usuarios/roles (equipo)
--   Hueco día-1 de la auditoría: existía agregar_miembro_por_email pero no había forma
--   de LISTAR ni QUITAR miembros ni cambiar su rol. Este script agrega:
--     • listar_miembros(company)              -> tabla (user_id, email, role, created_at)
--     • quitar_miembro(company, user)          -> jsonb
--     • cambiar_rol_miembro(company, user, rol) -> jsonb
--   Guarda de seguridad: nunca dejar la empresa sin ningún administrador.
--   Roles válidos: admin | vendedor | cajero | contador. Idempotente.
-- ============================================================

-- Lista los miembros de la empresa (email vive en auth.users; se lee vía SECURITY DEFINER).
-- Cualquier miembro de la empresa puede verla.
create or replace function listar_miembros(p_company_id uuid)
returns table(user_id uuid, email text, role text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select m.user_id, u.email::text, m.role, m.created_at
  from memberships m
  join auth.users u on u.id = m.user_id
  where m.company_id = p_company_id
    and p_company_id in (select auth_company_ids())
  order by m.created_at;
$$;
revoke execute on function listar_miembros(uuid) from public, anon;
grant execute on function listar_miembros(uuid) to authenticated, service_role;

-- Quita un miembro. Solo admin; no permite quitar al ÚLTIMO admin.
create or replace function quitar_miembro(p_company_id uuid, p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admins int;
begin
  if not is_company_admin(p_company_id) then
    raise exception 'Solo un administrador puede quitar miembros';
  end if;
  select count(*) into v_admins from memberships where company_id = p_company_id and role = 'admin';
  if v_admins <= 1 and exists (
    select 1 from memberships where company_id = p_company_id and user_id = p_user_id and role = 'admin'
  ) then
    raise exception 'No puedes quitar al único administrador de la empresa';
  end if;
  delete from memberships where company_id = p_company_id and user_id = p_user_id;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function quitar_miembro(uuid, uuid) from public, anon;
grant execute on function quitar_miembro(uuid, uuid) to authenticated, service_role;

-- Cambia el rol de un miembro. Solo admin; no permite degradar al ÚLTIMO admin.
create or replace function cambiar_rol_miembro(p_company_id uuid, p_user_id uuid, p_role text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admins int;
begin
  if not is_company_admin(p_company_id) then
    raise exception 'Solo un administrador puede cambiar roles';
  end if;
  if p_role not in ('admin', 'vendedor', 'cajero', 'contador') then
    raise exception 'Rol inválido';
  end if;
  select count(*) into v_admins from memberships where company_id = p_company_id and role = 'admin';
  if v_admins <= 1 and p_role <> 'admin' and exists (
    select 1 from memberships where company_id = p_company_id and user_id = p_user_id and role = 'admin'
  ) then
    raise exception 'No puedes quitarle el rol de administrador al único admin de la empresa';
  end if;
  update memberships set role = p_role where company_id = p_company_id and user_id = p_user_id;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function cambiar_rol_miembro(uuid, uuid, text) from public, anon;
grant execute on function cambiar_rol_miembro(uuid, uuid, text) to authenticated, service_role;
