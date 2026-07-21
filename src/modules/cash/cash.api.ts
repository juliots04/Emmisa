import { supabase } from '@/lib/supabase'

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

/** Abre una caja para la empresa. El usuario que la abre queda registrado. */
export async function openSession(companyId: string, montoInicial: number): Promise<CashSession> {
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) throw new Error('No hay sesión activa')

  const { data, error } = await supabase
    .from('cash_sessions')
    .insert({
      company_id: companyId,
      user_id: user.id,
      monto_inicial: montoInicial,
    })
    .select()
    .single()
  if (error) throw error
  return data as CashSession
}

/** Devuelve la caja abierta de la empresa (o null si no hay ninguna). */
export async function getOpenSession(companyId: string): Promise<CashSession | null> {
  const { data, error } = await supabase
    .from('cash_sessions')
    .select('*')
    .eq('company_id', companyId)
    .eq('estado', 'abierta')
    .order('abierto_en', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (error) throw error
  return (data as CashSession | null) ?? null
}

export async function listMovements(sessionId: string): Promise<CashMovement[]> {
  const { data, error } = await supabase
    .from('cash_movements')
    .select('*')
    .eq('cash_session_id', sessionId)
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as CashMovement[]
}

export async function addMovement(sessionId: string, input: NewMovement): Promise<CashMovement> {
  const { data, error } = await supabase
    .from('cash_movements')
    .insert({
      cash_session_id: sessionId,
      tipo: input.tipo,
      monto: input.monto,
      motivo: input.motivo ?? null,
    })
    .select()
    .single()
  if (error) throw error
  return data as CashMovement
}

/**
 * Cierra la caja calculando la diferencia:
 *   diferencia = montoFinal - (montoInicial + ingresos - retiros)
 * donde ingresos/retiros salen de los movimientos de la sesión.
 */
export async function closeSession(sessionId: string, montoFinal: number): Promise<CashSession> {
  const { data: sessionData, error: sessionError } = await supabase
    .from('cash_sessions')
    .select('*')
    .eq('id', sessionId)
    .single()
  if (sessionError) throw sessionError
  const session = sessionData as CashSession

  const movements = await listMovements(sessionId)
  const ingresos = movements
    .filter((m) => m.tipo === 'ingreso')
    .reduce((acc, m) => acc + Number(m.monto), 0)
  const retiros = movements
    .filter((m) => m.tipo === 'retiro')
    .reduce((acc, m) => acc + Number(m.monto), 0)

  const esperado = Number(session.monto_inicial) + ingresos - retiros
  const diferencia = montoFinal - esperado

  const { data, error } = await supabase
    .from('cash_sessions')
    .update({
      monto_final: montoFinal,
      diferencia,
      estado: 'cerrada',
      cerrado_en: new Date().toISOString(),
    })
    .eq('id', sessionId)
    .select()
    .single()
  if (error) throw error
  return data as CashSession
}

export async function listSessions(companyId: string): Promise<CashSession[]> {
  const { data, error } = await supabase
    .from('cash_sessions')
    .select('*')
    .eq('company_id', companyId)
    .order('abierto_en', { ascending: false })
    .limit(100)
  if (error) throw error
  return (data ?? []) as CashSession[]
}
