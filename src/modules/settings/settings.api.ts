import { supabase } from '@/lib/supabase'
import type { Company, Regimen } from '@/types'

// Tipos de comprobante admitidos por una serie.
export type SerieTipoDoc = '01' | '03' | '07' | '08' // 01 factura, 03 boleta, 07 NC, 08 ND

export interface Serie {
  id: string
  company_id: string
  establishment_id: string | null
  tipo_doc: SerieTipoDoc
  serie: string
  correlativo: number
}

export interface CompanyPatch {
  razon_social: string
  direccion?: string | null
  regimen: Regimen
}

export async function updateCompany(companyId: string, patch: CompanyPatch): Promise<Company> {
  const { data, error } = await supabase
    .from('companies')
    .update({
      razon_social: patch.razon_social,
      direccion: patch.direccion ?? null,
      regimen: patch.regimen,
    })
    .eq('id', companyId)
    .select()
    .single()
  if (error) throw error
  return data as Company
}

export async function listSeries(companyId: string): Promise<Serie[]> {
  const { data, error } = await supabase
    .from('series')
    .select('*')
    .eq('company_id', companyId)
    .order('serie')
  if (error) throw error
  return (data ?? []) as Serie[]
}

export interface NewSerie {
  tipo_doc: SerieTipoDoc
  serie: string
}

export async function createSerie(companyId: string, input: NewSerie): Promise<Serie> {
  const { data, error } = await supabase
    .from('series')
    .insert({
      company_id: companyId,
      tipo_doc: input.tipo_doc,
      serie: input.serie,
    })
    .select()
    .single()
  if (error) throw error
  return data as Serie
}

export async function deleteSerie(id: string): Promise<void> {
  const { error } = await supabase.from('series').delete().eq('id', id)
  if (error) throw error
}

// ==================== Credenciales del emisor (PSE: APISUNAT / Nubefact) ====================
// El token nunca se lee de vuelta (seguridad): solo se guarda y se consulta el ESTADO.
export async function tieneCredenciales(companyId: string): Promise<boolean> {
  const { data, error } = await supabase.rpc('tiene_credenciales', {
    p_company_id: companyId,
    p_provider: null,
  })
  if (error) throw error
  return Boolean(data)
}

export interface CredencialesInput {
  provider: string // apisunat | nubefact
  personaId: string
  token: string
  url?: string
}

export async function guardarCredenciales(companyId: string, input: CredencialesInput): Promise<void> {
  const { error } = await supabase.rpc('guardar_credenciales', {
    p_company_id: companyId,
    p_provider: input.provider,
    p_persona_id: input.personaId,
    p_token: input.token,
    p_extra: input.url ? { url: input.url } : {},
  })
  if (error) throw error
}
