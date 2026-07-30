import { supabase } from '@/lib/supabase'
import { cachedQuery, invalidateQueryCache } from '@/stores/queryCache'

export type CashSessionEstado = 'abierta' | 'cerrada'
export type MovementTipo = 'ingreso' | 'retiro'

export interface CashSession {
  id: string
  company_id: string
  user_id: string
  monto_inicial: number
  monto_final: number | null
  diferencia: number | null
  estado: CashSessionEstado
  abierto_en: string
  cerrado_en: string | null
}

export interface CashMovement {
  id: string
  cash_session_id: string
  tipo: MovementTipo
  monto: number
  motivo: string | null
  created_at: string
}

export interface NewMovement {
  tipo: MovementTipo
  monto: number
  motivo?: string | null
}

/** Abre una caja (RPC server-side: valida empresa y que el usuario no tenga otra abierta). */
export async function openSession(companyId: string, montoInicial: number): Promise<CashSession> {
  const { data, error } = await supabase.rpc('abrir_caja', {
    p_company_id: companyId,
    p_monto_inicial: montoInicial,
  })
  if (error) throw error
  const id = (data as { id: string }).id
  const { data: s, error: e2 } = await supabase
    .from('cash_sessions')
    .select('*')
    .eq('id', id)
    .single()
  if (e2) throw e2
  invalidateQueryCache()
  return s as CashSession
}

/** Devuelve la caja abierta DEL USUARIO ACTUAL en esta empresa (modelo por-cajero). */
export async function getOpenSession(companyId: string): Promise<CashSession | null> {
  return cachedQuery(
    ['open-cash-session', companyId],
    ['cash_sessions', `company:${companyId}`],
    async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) return null
      const { data, error } = await supabase
        .from('cash_sessions')
        .select('*')
        .eq('company_id', companyId)
        .eq('user_id', user.id)
        .eq('estado', 'abierta')
        .order('abierto_en', { ascending: false })
        .limit(1)
        .maybeSingle()
      if (error) throw error
      return (data as CashSession | null) ?? null
    },
  )
}

export async function listMovements(sessionId: string): Promise<CashMovement[]> {
  return cachedQuery(['cash-movements', sessionId], ['cash_movements'], async () => {
    const { data, error } = await supabase
      .from('cash_movements')
      .select('*')
      .eq('cash_session_id', sessionId)
      .order('created_at', { ascending: false })
    if (error) throw error
    return (data ?? []) as CashMovement[]
  })
}

export async function addMovement(sessionId: string, input: NewMovement): Promise<CashMovement> {
  // RPC server-side: valida que la caja esté ABIERTA y sea de la empresa.
  const { data, error } = await supabase.rpc('mov_caja', {
    p_session_id: sessionId,
    p_tipo: input.tipo,
    p_monto: input.monto,
    p_motivo: input.motivo ?? null,
  })
  if (error) throw error
  const id = (data as { id: string }).id
  const { data: m, error: e2 } = await supabase
    .from('cash_movements')
    .select('*')
    .eq('id', id)
    .single()
  if (e2) throw e2
  invalidateQueryCache()
  return m as CashMovement
}

/**
 * Cierra la caja vía RPC server-side (cerrar_caja): el arqueo (esperado y diferencia)
 * se RECOMPUTA en el servidor a partir de los movimientos, valida estado='abierta'
 * y serializa con FOR UPDATE. No es forjable desde el cliente.
 */
export async function closeSession(sessionId: string, montoFinal: number): Promise<CashSession> {
  const { error } = await supabase.rpc('cerrar_caja', {
    p_session_id: sessionId,
    p_monto_final: montoFinal,
  })
  if (error) throw error
  const { data, error: e2 } = await supabase
    .from('cash_sessions')
    .select('*')
    .eq('id', sessionId)
    .single()
  if (e2) throw e2
  invalidateQueryCache()
  return data as CashSession
}

export async function listSessions(companyId: string): Promise<CashSession[]> {
  return cachedQuery(
    ['cash-sessions', companyId],
    ['cash_sessions', `company:${companyId}`],
    async () => {
      const { data, error } = await supabase
        .from('cash_sessions')
        .select('*')
        .eq('company_id', companyId)
        .order('abierto_en', { ascending: false })
        .limit(100)
      if (error) throw error
      return (data ?? []) as CashSession[]
    },
  )
}
