import { supabase } from '@/lib/supabase'
import { cachedQuery } from '@/stores/queryCache'

/**
 * Fila de comprobante tal como vive en la tabla `documents`.
 * Se define aquí (y no en @/types) porque una NC usa tipo_doc '07', que no
 * forma parte del union `TipoDoc` del dominio base ('01' | '03').
 */
export interface CreditNoteRow {
  id: string
  company_id: string
  customer_id: string | null
  tipo_doc: string // '01' factura, '03' boleta, '07' nota de crédito
  serie: string
  correlativo: number
  moneda: string
  total_gravado: number
  total_igv: number
  total: number
  estado_sunat: string
  cdr: string | null
  pdf_url: string | null
  ref_document_id: string | null
  created_at: string
}

/**
 * Motivo de la nota de crédito · Catálogo SUNAT 09.
 * https://cpe.sunat.gob.pe (Anexo · Códigos de tipo de nota de crédito)
 */
export interface MotivoNC {
  codigo: string
  descripcion: string
}

export const MOTIVOS_NC: MotivoNC[] = [
  { codigo: '01', descripcion: 'Anulación de la operación' },
  { codigo: '02', descripcion: 'Anulación por error en el RUC' },
  { codigo: '03', descripcion: 'Corrección por error en la descripción' },
  { codigo: '06', descripcion: 'Devolución total' },
  { codigo: '07', descripcion: 'Devolución por ítem' },
]

/**
 * Motivo de la nota de débito · Catálogo SUNAT 10.
 * https://cpe.sunat.gob.pe (Anexo · Códigos de tipo de nota de débito)
 */
export const MOTIVOS_ND: MotivoNC[] = [
  { codigo: '01', descripcion: 'Intereses por mora' },
  { codigo: '02', descripcion: 'Aumento en el valor' },
  { codigo: '03', descripcion: 'Penalidades u otros conceptos' },
]

/** Motivos por tipo de nota: 07 crédito (cat.09) · 08 débito (cat.10). */
export function motivosPorTipo(tipoNota: '07' | '08'): MotivoNC[] {
  return tipoNota === '08' ? MOTIVOS_ND : MOTIVOS_NC
}

/**
 * Comprobantes aceptados por SUNAT que pueden ser rectificados por una NC:
 * facturas ('01') y boletas ('03') en estado 'aceptado'.
 */
export async function listAcceptedDocuments(companyId: string): Promise<CreditNoteRow[]> {
  return cachedQuery(
    ['accepted-documents', companyId],
    ['documents', `company:${companyId}`],
    async () => {
      const { data, error } = await supabase
        .from('documents')
        .select('*')
        .eq('company_id', companyId)
        .eq('estado_sunat', 'aceptado')
        .in('tipo_doc', ['01', '03'])
        .order('created_at', { ascending: false })
        .limit(100)
      if (error) throw error
      return (data ?? []) as CreditNoteRow[]
    },
  )
}

/** Notas de crédito ya emitidas (tipo_doc '07'). */
export async function listCreditNotes(companyId: string): Promise<CreditNoteRow[]> {
  return cachedQuery(
    ['credit-notes', companyId],
    ['documents', `company:${companyId}`],
    async () => {
      const { data, error } = await supabase
        .from('documents')
        .select('*')
        .eq('company_id', companyId)
        .eq('tipo_doc', '07')
        .order('created_at', { ascending: false })
        .limit(100)
      if (error) throw error
      return (data ?? []) as CreditNoteRow[]
    },
  )
}

/** Notas emitidas: crédito ('07') y débito ('08'). */
export async function listNotes(companyId: string): Promise<CreditNoteRow[]> {
  return cachedQuery(['notes', companyId], ['documents', `company:${companyId}`], async () => {
    const { data, error } = await supabase
      .from('documents')
      .select('*')
      .eq('company_id', companyId)
      .in('tipo_doc', ['07', '08'])
      .order('created_at', { ascending: false })
      .limit(100)
    if (error) throw error
    return (data ?? []) as CreditNoteRow[]
  })
}

/**
 * Emite una nota de crédito ('07') o débito ('08') que rectifica un comprobante.
 *
 * Flujo TRANSACCIONAL:
 *   1) RPC `emitir_nota` (Postgres): reserva correlativo con lock, copia receptor y
 *      totales del original (o de los ítems parciales), crea la nota atómica.
 *   2) Edge Function `emitir`: envía mediante Emmisa Fiscal API directa.
 *
 * La serie la decide el RPC: NC factura->FC01 / boleta->BC01 · ND factura->FD01 / boleta->BD01.
 */
export async function issueNote(
  companyId: string,
  originalDocId: string,
  tipoNota: '07' | '08',
  motivoCodigo: string,
  motivoDesc: string,
  items?: {
    descripcion: string
    cantidad: number
    precioUnitario: number
    tipoAfectacion?: string
  }[],
  /**
   * Llave de idempotencia: DEBE ser estable durante un intento (reintentos/doble
   * clic incluidos) para que el RPC deduplique y no emita DOS notas. Si no se pasa,
   * se genera una (sin protección real ante reintento). El caller debe conservar y
   * reusar una llave por intento, igual que la venta (ventaKey en el POS).
   */
  idempotencyKey?: string,
): Promise<CreditNoteRow> {
  void companyId
  void originalDocId
  void tipoNota
  void motivoCodigo
  void motivoDesc
  void items
  void idempotencyKey
  throw new Error(
    'Las notas de crédito y débito aún no están implementadas en Emmisa Fiscal API. No se creó ni envió la nota.',
  )
}

/** Compat: emite una nota de crédito (07). */
export async function issueCreditNote(
  companyId: string,
  originalDocId: string,
  motivoCodigo: string,
  motivoDesc: string,
  idempotencyKey?: string,
): Promise<CreditNoteRow> {
  return issueNote(
    companyId,
    originalDocId,
    '07',
    motivoCodigo,
    motivoDesc,
    undefined,
    idempotencyKey,
  )
}
