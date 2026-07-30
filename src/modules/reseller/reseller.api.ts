import { supabase } from '@/lib/supabase'
import { cachedQuery, invalidateQueryCache } from '@/stores/queryCache'

export interface Reseller {
  id: string
  owner_id: string
  nombre: string
  dominio: string | null
  branding: {
    logo_url?: string
    color_primario?: string
    color_secundario?: string
    nombre_comercial?: string
  }
  activo: boolean
  created_at: string
}

export interface Plan {
  id: string
  reseller_id: string
  nombre: string
  precio: number
  moneda: string
  periodicidad: string
  limites: { max_comprobantes?: number; max_empresas?: number; max_usuarios?: number }
  activo: boolean
  created_at: string
}

export interface ResellerCompany {
  id: string
  ruc: string
  razon_social: string
  estado: string
  reseller_id: string | null
  created_at: string
}

export interface Subscription {
  id: string
  company_id: string
  plan_id: string | null
  estado: string
  periodo_inicio: string
  periodo_fin: string | null
  created_at: string
}

// ==================== Estado de suscripción (billing) ====================
export interface EstadoSuscripcion {
  tiene_suscripcion: boolean
  estado: string // activa | vencida | suspendida | cancelada | sin_suscripcion
  plan: string | null
  periodo_fin: string | null
  dias_restantes: number | null
  puede_emitir: boolean
}

/** Estado de la suscripción de la empresa (para el banner de "tu plan vence…"). */
export async function estadoSuscripcion(companyId: string): Promise<EstadoSuscripcion> {
  return cachedQuery(
    ['subscription-status', companyId],
    ['subscriptions', `company:${companyId}`],
    async () => {
      const { data, error } = await supabase.rpc('estado_suscripcion', { p_company_id: companyId })
      if (error) throw error
      return data as EstadoSuscripcion
    },
  )
}

// ==================== Revendedor ====================
export async function getMyReseller(): Promise<Reseller | null> {
  return cachedQuery(['my-reseller'], ['resellers'], async () => {
    const { data, error } = await supabase.from('resellers').select('*').limit(1).maybeSingle()
    if (error) throw error
    return (data as Reseller) ?? null
  })
}

export async function createReseller(input: {
  nombre: string
  dominio?: string
}): Promise<Reseller> {
  const {
    data: { session },
  } = await supabase.auth.getSession()
  if (!session) throw new Error('Sesión inválida')
  const { data, error } = await supabase
    .from('resellers')
    .insert({ owner_id: session.user.id, nombre: input.nombre, dominio: input.dominio ?? null })
    .select()
    .single()
  if (error) throw error
  invalidateQueryCache()
  return data as Reseller
}

export async function updateBranding(
  resellerId: string,
  branding: Reseller['branding'],
): Promise<void> {
  const { error } = await supabase.from('resellers').update({ branding }).eq('id', resellerId)
  if (error) throw error
  invalidateQueryCache()
}

// ==================== Planes ====================
export async function listPlans(resellerId: string): Promise<Plan[]> {
  return cachedQuery(['plans', resellerId], ['plans', 'resellers'], async () => {
    const { data, error } = await supabase
      .from('plans')
      .select('*')
      .eq('reseller_id', resellerId)
      .order('precio')
    if (error) throw error
    return (data ?? []) as Plan[]
  })
}

export async function createPlan(
  resellerId: string,
  input: { nombre: string; precio: number; periodicidad: string; limites: Plan['limites'] },
): Promise<Plan> {
  const { data, error } = await supabase
    .from('plans')
    .insert({
      reseller_id: resellerId,
      nombre: input.nombre,
      precio: input.precio,
      periodicidad: input.periodicidad,
      limites: input.limites,
    })
    .select()
    .single()
  if (error) throw error
  invalidateQueryCache()
  return data as Plan
}

export async function deletePlan(planId: string): Promise<void> {
  const { error } = await supabase.from('plans').delete().eq('id', planId)
  if (error) throw error
  invalidateQueryCache()
}

// ==================== Empresas del revendedor ====================
export async function listResellerCompanies(resellerId: string): Promise<ResellerCompany[]> {
  return cachedQuery(['reseller-companies', resellerId], ['companies', 'resellers'], async () => {
    const { data, error } = await supabase
      .from('companies')
      .select('id, ruc, razon_social, estado, reseller_id, created_at')
      .eq('reseller_id', resellerId)
      .order('created_at')
    if (error) throw error
    return (data ?? []) as ResellerCompany[]
  })
}

/** Empresas propias sin revendedor asignado (para poder “absorberlas” al panel). */
export async function listUnassignedCompanies(): Promise<ResellerCompany[]> {
  return cachedQuery(['unassigned-companies'], ['companies', 'resellers'], async () => {
    const { data, error } = await supabase
      .from('companies')
      .select('id, ruc, razon_social, estado, reseller_id, created_at')
      .is('reseller_id', null)
      .order('created_at')
    if (error) throw error
    return (data ?? []) as ResellerCompany[]
  })
}

export async function assignCompany(companyId: string, resellerId: string): Promise<void> {
  // Vía RPC que valida propiedad del reseller y que la empresa esté disponible (el UPDATE
  // directo de reseller_id lo bloquea ahora companies_update WITH CHECK).
  const { error } = await supabase.rpc('asignar_empresa_reseller', {
    p_company_id: companyId,
    p_reseller_id: resellerId,
  })
  if (error) throw error
  invalidateQueryCache()
}

// ==================== Suscripciones ====================
export async function listSubscriptions(resellerCompanyIds: string[]): Promise<Subscription[]> {
  if (resellerCompanyIds.length === 0) return []
  return cachedQuery(
    ['subscriptions', [...resellerCompanyIds].sort()],
    ['subscriptions'],
    async () => {
      const { data, error } = await supabase
        .from('subscriptions')
        .select('*')
        .in('company_id', resellerCompanyIds)
        .order('created_at', { ascending: false })
      if (error) throw error
      return (data ?? []) as Subscription[]
    },
  )
}

export async function createSubscription(input: {
  companyId: string
  planId: string
  periodoFin?: string | null
}): Promise<Subscription> {
  const { data, error } = await supabase
    .from('subscriptions')
    .insert({
      company_id: input.companyId,
      plan_id: input.planId,
      periodo_fin: input.periodoFin ?? null,
    })
    .select()
    .single()
  if (error) throw error
  invalidateQueryCache()
  return data as Subscription
}

export async function setSubscriptionEstado(subscriptionId: string, estado: string): Promise<void> {
  const { error } = await supabase.from('subscriptions').update({ estado }).eq('id', subscriptionId)
  if (error) throw error
  invalidateQueryCache()
}
