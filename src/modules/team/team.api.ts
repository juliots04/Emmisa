import { supabase } from '@/lib/supabase'
import { cachedQuery, invalidateQueryCache } from '@/stores/queryCache'

export type Rol = 'admin' | 'vendedor' | 'cajero' | 'contador'

export interface Miembro {
  user_id: string
  email: string
  role: Rol
  created_at: string
}

export const ROLES: { value: Rol; label: string }[] = [
  { value: 'admin', label: 'Administrador' },
  { value: 'vendedor', label: 'Vendedor' },
  { value: 'cajero', label: 'Cajero' },
  { value: 'contador', label: 'Contador' },
]

export function rolLabel(r: string): string {
  return ROLES.find((x) => x.value === r)?.label ?? r
}

/** Lista los miembros de la empresa (email + rol). */
export async function listarMiembros(companyId: string): Promise<Miembro[]> {
  return cachedQuery(['team-members', companyId], ['team', `company:${companyId}`], async () => {
    const { data, error } = await supabase.rpc('listar_miembros', { p_company_id: companyId })
    if (error) throw error
    return (data ?? []) as Miembro[]
  })
}

/** Invita/agrega un usuario ya registrado a la empresa con un rol. */
export async function agregarMiembro(companyId: string, email: string, role: Rol): Promise<void> {
  const { error } = await supabase.rpc('agregar_miembro_por_email', {
    p_company_id: companyId,
    p_email: email,
    p_role: role,
  })
  if (error) throw error
  invalidateQueryCache()
}

/** Cambia el rol de un miembro. */
export async function cambiarRolMiembro(
  companyId: string,
  userId: string,
  role: Rol,
): Promise<void> {
  const { error } = await supabase.rpc('cambiar_rol_miembro', {
    p_company_id: companyId,
    p_user_id: userId,
    p_role: role,
  })
  if (error) throw error
  invalidateQueryCache()
}

/** Quita un miembro de la empresa. */
export async function quitarMiembro(companyId: string, userId: string): Promise<void> {
  const { error } = await supabase.rpc('quitar_miembro', {
    p_company_id: companyId,
    p_user_id: userId,
  })
  if (error) throw error
  invalidateQueryCache()
}
