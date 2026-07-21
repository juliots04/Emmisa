import { supabase } from '@/lib/supabase'
import { emisor } from '@/modules/sunat'

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

interface CustomerLite {
  tipo_doc: string
  num_doc: string | null
  denominacion: string
}

function numeroDoc(serie: string, correlativo: number): string {
  return `${serie}-${String(correlativo).padStart(8, '0')}`
}

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
 * Emite una nota de crédito (tipo_doc '07') que rectifica un comprobante aceptado.
 *
 * Flujo: lee el documento original -> arma serie/correlativo de la NC ->
 * llama al motor SUNAT (mock) -> guarda la NC en `documents` con
 * `ref_document_id` apuntando al original y los mismos totales.
 *
 * La serie de la NC depende del comprobante afectado:
 *   factura ('01') -> 'FC01'   ·   boleta ('03') -> 'BC01'.
 *
 * Nota: el correlativo aquí es "naive" (mismo criterio que documents.api.ts);
 * en producción debería salir de una función transaccional en Postgres.
 */
export async function issueCreditNote(
  companyId: string,
  originalDocId: string,
  motivoCodigo: string,
  motivoDesc: string,
): Promise<CreditNoteRow> {
  // 1) Comprobante original (acotado a la empresa actual · multi-tenant)
  const { data: original, error: origError } = await supabase
    .from('documents')
    .select('*')
    .eq('company_id', companyId)
    .eq('id', originalDocId)
    .single()
  if (origError) throw origError
  const doc = original as CreditNoteRow

  // 2) Serie de la NC según el tipo del comprobante afectado
  const serie = doc.tipo_doc === '01' ? 'FC01' : 'BC01'

  // 3) Correlativo siguiente para esa serie / tipo '07'
  const { data: last } = await supabase
    .from('documents')
    .select('correlativo')
    .eq('company_id', companyId)
    .eq('tipo_doc', '07')
    .eq('serie', serie)
    .order('correlativo', { ascending: false })
    .limit(1)
    .maybeSingle()
  const correlativo = ((last?.correlativo as number | undefined) ?? 0) + 1

  // 4) Cliente del comprobante original (para el payload SUNAT)
  let cliente: { tipoDoc: string; numDoc?: string; denominacion: string } = {
    tipoDoc: '1',
    denominacion: 'Cliente varios',
  }
  if (doc.customer_id) {
    const { data: cust } = await supabase
      .from('customers')
      .select('tipo_doc, num_doc, denominacion')
      .eq('id', doc.customer_id)
      .maybeSingle()
    if (cust) {
      const c = cust as CustomerLite
      cliente = {
        tipoDoc: c.tipo_doc,
        numDoc: c.num_doc ?? undefined,
        denominacion: c.denominacion,
      }
    }
  }

  const numeroOriginal = numeroDoc(doc.serie, doc.correlativo)

  // 5) Emitir la NC en el motor SUNAT (hoy: mock -> siempre acepta)
  const result = await emisor.emitir({
    tipoDoc: '07',
    serie,
    correlativo,
    cliente,
    items: [
      {
        descripcion: `Nota de crédito (${motivoCodigo} · ${motivoDesc}) sobre ${numeroOriginal}`,
        cantidad: 1,
        precioUnitario: doc.total,
      },
    ],
  })

  // 6) Guardar la NC con los mismos totales del original
  const { data: nc, error } = await supabase
    .from('documents')
    .insert({
      company_id: companyId,
      customer_id: doc.customer_id,
      tipo_doc: '07',
      serie,
      correlativo,
      moneda: doc.moneda,
      total_gravado: doc.total_gravado,
      total_igv: doc.total_igv,
      total: doc.total,
      estado_sunat: result.estado,
      cdr: result.cdr ?? null,
      pdf_url: result.pdfUrl ?? null,
      ref_document_id: originalDocId,
      idempotency_key: crypto.randomUUID(),
    })
    .select()
    .single()
  if (error) throw error

  return nc as CreditNoteRow
}
