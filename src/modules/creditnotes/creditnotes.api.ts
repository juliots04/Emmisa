import { supabase } from '@/lib/supabase'
import { emitirEnMotor } from '@/modules/documents/documents.api'

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
 * Comprobantes aceptados por SUNAT que pueden ser rectificados por una NC:
 * facturas ('01') y boletas ('03') en estado 'aceptado'.
 */
export async function listAcceptedDocuments(companyId: string): Promise<CreditNoteRow[]> {
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
}

/** Notas de crédito ya emitidas (tipo_doc '07'). */
export async function listCreditNotes(companyId: string): Promise<CreditNoteRow[]> {
  const { data, error } = await supabase
    .from('documents')
    .select('*')
    .eq('company_id', companyId)
    .eq('tipo_doc', '07')
    .order('created_at', { ascending: false })
    .limit(100)
  if (error) throw error
  return (data ?? []) as CreditNoteRow[]
}

/**
 * Emite una nota de crédito ('07') o débito ('08') que rectifica un comprobante.
 *
 * Flujo TRANSACCIONAL:
 *   1) RPC `emitir_nota` (Postgres): reserva correlativo con lock, copia receptor y
 *      totales del original (o de los ítems parciales), crea la nota atómica.
 *   2) Edge Function `emitir`: firma/envía al PSE real y actualiza estado server-side.
 *
 * La serie la decide el RPC: NC factura->FC01 / boleta->BC01 · ND factura->FD01 / boleta->BD01.
 */
export async function issueNote(
  companyId: string,
  originalDocId: string,
  tipoNota: '07' | '08',
  motivoCodigo: string,
  motivoDesc: string,
  items?: { descripcion: string; cantidad: number; precioUnitario: number; tipoAfectacion?: string }[],
): Promise<CreditNoteRow> {
  const { data, error } = await supabase.rpc('emitir_nota', {
    p_company_id: companyId,
    p_ref_document_id: originalDocId,
    p_tipo_nota: tipoNota,
    p_motivo_codigo: motivoCodigo,
    p_motivo_desc: motivoDesc,
    p_items: items
      ? items.map((i) => ({
          descripcion: i.descripcion,
          cantidad: i.cantidad,
          precio_unitario: i.precioUnitario,
          tipo_afectacion: i.tipoAfectacion ?? '10',
        }))
      : null,
    p_idempotency_key: crypto.randomUUID(),
  })
  if (error) throw error
  const reserved = data as { id: string; reused?: boolean }

  // Emitir en el motor (real o simulado). No re-emite si ya existía.
  if (!reserved.reused) await emitirEnMotor(reserved.id)

  const { data: nc, error: getErr } = await supabase
    .from('documents').select('*').eq('id', reserved.id).single()
  if (getErr) throw getErr
  return nc as CreditNoteRow
}

/** Compat: emite una nota de crédito (07). */
export async function issueCreditNote(
  companyId: string,
  originalDocId: string,
  motivoCodigo: string,
  motivoDesc: string,
): Promise<CreditNoteRow> {
  return issueNote(companyId, originalDocId, '07', motivoCodigo, motivoDesc)
}
