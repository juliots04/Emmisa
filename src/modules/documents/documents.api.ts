import { supabase } from '@/lib/supabase'
import { emisor } from '@/modules/sunat'
import type { EmitResult } from '@/modules/sunat'
import type { DocumentRow, TipoDoc } from '@/types'

export interface EmitLine {
  productId?: string | null
  descripcion: string
  cantidad: number
  precioUnitario: number
}

export interface EmitParams {
  companyId: string
  tipoDoc: TipoDoc
  customerId?: string | null
  cliente: { tipoDoc: string; numDoc?: string; denominacion: string }
  items: EmitLine[]
  /** Datos de pago (POS). Si no se pasan, se asume efectivo sin registro de vuelto. */
  formaPago?: string
  montoRecibido?: number | null
  vuelto?: number | null
  /** Sesión de caja abierta (POS). Si se pasa, la venta se registra en caja y exige caja abierta. */
  cashSessionId?: string | null
  /** Llave de idempotencia para evitar duplicar la venta ante reintentos/doble clic. */
  idempotencyKey?: string | null
}

interface ReservedDoc {
  id: string
  serie: string
  correlativo: number
  total: number
  reused?: boolean
}

const SERIE: Record<TipoDoc, string> = { '01': 'F001', '03': 'B001' }

/**
 * Emite un comprobante de punta a punta de forma TRANSACCIONAL:
 *   1) RPC `emitir_venta` (Postgres) reserva el correlativo con lock de fila, crea el
 *      comprobante + ítems, descuenta stock y registra el efectivo en caja — todo atómico.
 *   2) Llama al motor SUNAT (hoy mock) con el correlativo ya reservado.
 *   3) Actualiza el estado/CDR/PDF del comprobante con la respuesta del motor.
 */
export async function emitirComprobante(params: EmitParams) {
  if (params.items.length === 0) throw new Error('Agrega al menos un ítem')
  const serie = SERIE[params.tipoDoc]

  // 1) Reserva atómica en la BD (correlativo + documento + stock + caja).
  const { data: rpcData, error: rpcError } = await supabase.rpc('emitir_venta', {
    p_company_id: params.companyId,
    p_tipo_doc: params.tipoDoc,
    p_serie: serie,
    p_cliente: {
      customer_id: params.customerId ?? null,
      tipo_doc: params.cliente.tipoDoc,
      num_doc: params.cliente.numDoc ?? null,
      denominacion: params.cliente.denominacion,
    },
    p_items: params.items.map((i) => ({
      product_id: i.productId ?? null,
      descripcion: i.descripcion,
      cantidad: i.cantidad,
      precio_unitario: i.precioUnitario,
    })),
    p_forma_pago: params.formaPago ?? 'efectivo',
    p_monto_recibido: params.montoRecibido ?? null,
    p_vuelto: params.vuelto ?? null,
    p_cash_session_id: params.cashSessionId ?? null,
    p_idempotency_key: params.idempotencyKey ?? null,
  })
  if (rpcError) throw rpcError
  const reserved = rpcData as ReservedDoc

  // Idempotencia: si la venta ya existía (reintento / doble clic / carrera), NO se re-emite
  // ni se re-actualiza; se devuelve el comprobante ya creado.
  if (reserved.reused) {
    const { data: existing, error: exErr } = await supabase
      .from('documents')
      .select('*')
      .eq('id', reserved.id)
      .single()
    if (exErr) throw exErr
    const result: EmitResult = { estado: 'aceptado', mensaje: 'La venta ya estaba registrada (no se duplicó)' }
    return { document: existing as DocumentRow, result }
  }

  // 2) Motor SUNAT (hoy mock) con el número ya reservado.
  const result = await emisor.emitir({
    tipoDoc: params.tipoDoc,
    serie: reserved.serie,
    correlativo: reserved.correlativo,
    cliente: params.cliente,
    items: params.items.map((i) => ({
      descripcion: i.descripcion,
      cantidad: i.cantidad,
      precioUnitario: i.precioUnitario,
    })),
  })

  // 3) Persistir el resultado del motor sobre el comprobante creado.
  const { data: doc, error } = await supabase
    .from('documents')
    .update({
      estado_sunat: result.estado,
      cdr: result.cdr ?? null,
      xml_url: result.xmlUrl ?? null,
      pdf_url: result.pdfUrl ?? null,
    })
    .eq('id', reserved.id)
    .select()
    .single()
  if (error) throw error

  return { document: doc as DocumentRow, result }
}

export async function listDocuments(companyId: string): Promise<DocumentRow[]> {
  const { data, error } = await supabase
    .from('documents')
    .select('*')
    .eq('company_id', companyId)
    .order('created_at', { ascending: false })
    .limit(100)
  if (error) throw error
  return (data ?? []) as DocumentRow[]
}
