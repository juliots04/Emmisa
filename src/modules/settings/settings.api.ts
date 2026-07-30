import { supabase } from '@/lib/supabase'
import { uid } from '@/lib/uid'
import { processImage } from '@/lib/image'
import { cachedQuery, invalidateQueryCache } from '@/stores/queryCache'
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
  /** Logo de la empresa. Si se omite, no se toca; `null` lo borra. */
  logo_url?: string | null
}

export async function updateCompany(companyId: string, patch: CompanyPatch): Promise<Company> {
  const payload: Record<string, unknown> = {
    razon_social: patch.razon_social,
    direccion: patch.direccion ?? null,
    regimen: patch.regimen,
  }
  // Solo tocar el logo si el caller lo envió (evita borrarlo sin querer).
  if (patch.logo_url !== undefined) payload.logo_url = patch.logo_url

  const { data, error } = await supabase
    .from('companies')
    .update(payload)
    .eq('id', companyId)
    .select()
    .single()
  if (error) throw error
  invalidateQueryCache()
  return data as Company
}

/** Sube el logo de la empresa al bucket 'productos': validado, saneado y comprimido a
 *  WebP por el pipeline central (@/lib/image). Devuelve su URL pública. */
export async function uploadCompanyLogo(companyId: string, file: File): Promise<string> {
  // Calidad un poco más alta para el logo (suele ser gráfico/nítido).
  const { blob, ext, contentType } = await processImage(file, { quality: 0.9 })
  const path = `empresa/${companyId}/logo-${uid()}.${ext}`
  const { error } = await supabase.storage.from('productos').upload(path, blob, {
    upsert: true,
    contentType,
  })
  if (error) throw error
  return supabase.storage.from('productos').getPublicUrl(path).data.publicUrl
}

export async function listSeries(companyId: string): Promise<Serie[]> {
  return cachedQuery(['series', companyId], ['series', `company:${companyId}`], async () => {
    const { data, error } = await supabase
      .from('series')
      .select('*')
      .eq('company_id', companyId)
      .order('serie')
    if (error) throw error
    return (data ?? []) as Serie[]
  })
}

export interface NewSerie {
  tipo_doc: SerieTipoDoc
  serie: string
}

// El DML directo sobre `series` está revocado (0023): se gestiona por RPC SECURITY
// DEFINER que valida admin, formato y prefijo (F factura / B boleta).
export async function createSerie(companyId: string, input: NewSerie): Promise<void> {
  const { error } = await supabase.rpc('crear_serie', {
    p_company_id: companyId,
    p_tipo_doc: input.tipo_doc,
    p_serie: input.serie,
  })
  if (error) throw error
  invalidateQueryCache()
}

export async function deleteSerie(companyId: string, id: string): Promise<void> {
  const { error } = await supabase.rpc('eliminar_serie', {
    p_company_id: companyId,
    p_serie_id: id,
  })
  if (error) throw error
  invalidateQueryCache()
}

// ==================== Emisor vinculado con nuestra Fiscal API ====================
// La API key vive como secret del backend. Vue solo puede ver el estado, nunca la clave
// ni el issuerId interno.
export interface FiscalIntegrationStatus {
  configured: boolean
  environment: 'beta' | 'production' | null
}

export async function estadoIntegracionFiscal(
  companyId: string,
): Promise<FiscalIntegrationStatus> {
  return cachedQuery(
    ['fiscal-integration', companyId],
    ['fiscal-integration', `company:${companyId}`],
    async () => {
      const { data, error } = await supabase.rpc('estado_integracion_fiscal', {
        p_company_id: companyId,
      })
      if (error) throw error
      return data as FiscalIntegrationStatus
    },
  )
}
