import { supabase } from '@/lib/supabase'
import { cachedQuery, invalidateQueryCache } from '@/stores/queryCache'

export interface SireProceso {
  id: string
  company_id: string
  tipo: 'RVIE' | 'RCE'
  periodo: string
  num_ticket: string | null
  estado: string
  resumen: unknown
  archivo_url: string | null
  mensaje: string | null
  created_at: string
}

export interface SireEstado {
  configurado: boolean
  usuario: string | null
}

/** ¿La empresa tiene SIRE configurado? (no expone el secreto) */
export async function tieneSire(companyId: string): Promise<SireEstado> {
  return cachedQuery(['sire-status', companyId], ['sire', `company:${companyId}`], async () => {
    const { data, error } = await supabase.rpc('tiene_sire', { p_company_id: companyId })
    if (error) throw error
    return (data ?? { configurado: false, usuario: null }) as SireEstado
  })
}

export interface SireCredInput {
  clientId: string
  clientSecret: string
  solUsuario: string
  solClave: string
}

/** Guarda las credenciales SIRE de la empresa (solo admin). */
export async function guardarCredencialesSire(
  companyId: string,
  input: SireCredInput,
): Promise<void> {
  const { error } = await supabase.rpc('guardar_credenciales_sire', {
    p_company_id: companyId,
    p_client_id: input.clientId,
    p_client_secret: input.clientSecret,
    p_sol_usuario: input.solUsuario,
    p_sol_clave: input.solClave,
  })
  if (error) throw error
  invalidateQueryCache()
}

async function invokeSire<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke('sire', { body })
  if (error) {
    // La Edge Function devuelve el detalle del error de SUNAT en el cuerpo.
    const detalle = (data as { error?: string } | null)?.error
    throw new Error(detalle || error.message)
  }
  if ((data as { error?: string })?.error) throw new Error((data as { error: string }).error)
  return data as T
}

/** Prueba que las credenciales autentican contra SUNAT. */
export async function sireTest(companyId: string): Promise<{ ok: boolean; mensaje: string }> {
  return invokeSire({ companyId, accion: 'test' })
}

/** Solicita la propuesta del periodo (AAAAMM) para RVIE (ventas) o RCE (compras). */
export async function sireDescargarPropuesta(
  companyId: string,
  tipo: 'RVIE' | 'RCE',
  periodo: string,
): Promise<{ proceso: SireProceso; numTicket: string }> {
  const result = await invokeSire<{ proceso: SireProceso; numTicket: string }>({
    companyId,
    accion: 'propuesta',
    tipo,
    periodo,
  })
  invalidateQueryCache()
  return result
}

/** Acepta/registra la propuesta del periodo como el registro definitivo (RVIE/RCE). */
export async function sireAceptarPropuesta(
  companyId: string,
  tipo: 'RVIE' | 'RCE',
  periodo: string,
): Promise<{ proceso: SireProceso; numTicket: string }> {
  const result = await invokeSire<{ proceso: SireProceso; numTicket: string }>({
    companyId,
    accion: 'aceptar',
    tipo,
    periodo,
  })
  invalidateQueryCache()
  return result
}

/** Consulta el estado del ticket de una propuesta. */
export async function sireConsultarTicket(
  companyId: string,
  tipo: 'RVIE' | 'RCE',
  numTicket: string,
  procesoId?: string,
): Promise<{ estado: string; archivoUrl?: string; resumen?: unknown }> {
  const result = await invokeSire<{ estado: string; archivoUrl?: string; resumen?: unknown }>({
    companyId,
    accion: 'consultar',
    tipo,
    numTicket,
    procesoId,
  })
  invalidateQueryCache()
  return result
}

/** Historial de procesos SIRE de la empresa. */
export async function listSireProcesos(companyId: string): Promise<SireProceso[]> {
  return cachedQuery(['sire-processes', companyId], ['sire', `company:${companyId}`], async () => {
    const { data, error } = await supabase
      .from('sire_procesos')
      .select('*')
      .eq('company_id', companyId)
      .order('created_at', { ascending: false })
      .limit(50)
    if (error) throw error
    return (data ?? []) as SireProceso[]
  })
}
