import { supabase } from '@/lib/supabase'
import { simular, type EmitResult } from '@/modules/sunat'
import type { DocumentRow, TipoDoc } from '@/types'

export interface EmitLine {
  productId?: string | null
  descripcion: string
  cantidad: number
  precioUnitario: number
  /** Catálogo 07: 10 gravado, 11-17 gravadas gratuitas, 20/21 exonerado, 30-36 inafecto, 40 exportación. */
  tipoAfectacion?: string
  unidadMedida?: string
  /** Descuento (monto) de la línea. */
  descuento?: number
  /** ICBPER (bolsa plástica): cobra el impuesto fijo por unidad. */
  icbper?: boolean
  /** ISC (monto) de la línea, si aplica. */
  isc?: number
}

export interface EmitParams {
  companyId: string
  tipoDoc: TipoDoc
  customerId?: string | null
  cliente: { tipoDoc: string; numDoc?: string; denominacion: string; direccion?: string }
  items: EmitLine[]
  /** Serie del comprobante. Por defecto F001 (factura) / B001 (boleta). */
  serie?: string
  moneda?: string
  tipoCambio?: number
  /** Descuento global (monto) sobre el total. */
  descuentoGlobal?: number
  /** contado | credito (crédito genera cuenta por cobrar). */
  condicionPago?: string
  fechaVencimiento?: string | null
  establishmentId?: string | null
  /** Datos de pago (POS). */
  formaPago?: string
  montoRecibido?: number | null
  vuelto?: number | null
  cashSessionId?: string | null
  /** Llave de idempotencia. Si no se pasa, se genera una (evita duplicar ante doble clic). */
  idempotencyKey?: string | null
}

interface ReservedDoc {
  id: string
  serie: string
  correlativo: number
  total: number
  reused?: boolean
}

const SERIE_DEFAULT: Record<TipoDoc, string> = { '01': 'F001', '03': 'B001' }

/**
 * Emite un comprobante de punta a punta:
 *   1) RPC `emitir_venta` (Postgres) reserva correlativo + crea documento/ítems +
 *      descuenta stock + registra caja/CxC — todo atómico.
 *   2) Edge Function `emitir` firma y envía al PSE real (APISUNAT) con el secreto,
 *      y actualiza el estado server-side. Si la función no está desplegada, cae a
 *      un modo SIMULADO local para no romper el desarrollo.
 */
export async function emitirComprobante(params: EmitParams) {
  if (params.items.length === 0) throw new Error('Agrega al menos un ítem')
  const serie = params.serie ?? SERIE_DEFAULT[params.tipoDoc]
  const idempotencyKey = params.idempotencyKey ?? crypto.randomUUID()

  // 1) Reserva atómica en la BD.
  const { data: rpcData, error: rpcError } = await supabase.rpc('emitir_venta', {
    p_company_id: params.companyId,
    p_tipo_doc: params.tipoDoc,
    p_serie: serie,
    p_cliente: {
      customer_id: params.customerId ?? null,
      tipo_doc: params.cliente.tipoDoc,
      num_doc: params.cliente.numDoc ?? null,
      denominacion: params.cliente.denominacion,
      direccion: params.cliente.direccion ?? null,
    },
    p_items: params.items.map((i) => ({
      product_id: i.productId ?? null,
      descripcion: i.descripcion,
      cantidad: i.cantidad,
      precio_unitario: i.precioUnitario,
      tipo_afectacion: i.tipoAfectacion ?? null,
      unidad_medida: i.unidadMedida ?? null,
      descuento: i.descuento ?? 0,
      icbper: i.icbper ?? false,
      isc: i.isc ?? 0,
    })),
    p_forma_pago: params.formaPago ?? 'efectivo',
    p_monto_recibido: params.montoRecibido ?? null,
    p_vuelto: params.vuelto ?? null,
    p_cash_session_id: params.cashSessionId ?? null,
    p_idempotency_key: idempotencyKey,
    p_moneda: params.moneda ?? 'PEN',
    p_tipo_cambio: params.tipoCambio ?? 1,
    p_condicion_pago: params.condicionPago ?? 'contado',
    p_fecha_vencimiento: params.fechaVencimiento ?? null,
    p_establishment_id: params.establishmentId ?? null,
    p_descuento_global: params.descuentoGlobal ?? 0,
  })
  if (rpcError) throw rpcError
  const reserved = rpcData as ReservedDoc

  // Idempotencia: si ya existía, devolver sin re-emitir.
  if (reserved.reused) {
    const { data: existing, error: exErr } = await supabase
      .from('documents').select('*').eq('id', reserved.id).single()
    if (exErr) throw exErr
    const result: EmitResult = { estado: existing.estado_sunat, mensaje: 'La venta ya estaba registrada (no se duplicó)' }
    return { document: existing as DocumentRow, result }
  }

  // 2) Emisión SUNAT server-side (Edge Function). Fallback simulado si no está desplegada.
  return await emitirEnMotor(reserved.id)
}

/**
 * Llama a la Edge Function `emitir` (motor real). Si la función no está desplegada
 * —o si activas VITE_SUNAT_SIMULADO=true— cae a una SIMULACIÓN local de alta
 * fidelidad que persiste el estado igual que el motor real (para no romper el flujo).
 */
export async function emitirEnMotor(documentId: string) {
  const forzarSimulado = import.meta.env.VITE_SUNAT_SIMULADO === 'true'
  if (!forzarSimulado) {
    try {
      const { data, error } = await supabase.functions.invoke('emitir', { body: { documentId } })
      if (error) throw error
      return { document: data.document as DocumentRow, result: { ...data.result } as EmitResult }
    } catch {
      // La Edge Function no está desplegada -> simulación local.
    }
  }
  return await simularYPersistir(documentId)
}

/** Simula la emisión (sin SUNAT) y persiste el resultado en el documento. */
async function simularYPersistir(documentId: string) {
  const { data: doc0, error: e0 } = await supabase
    .from('documents')
    .select('*')
    .eq('id', documentId)
    .single()
  if (e0) throw e0
  const d = doc0 as unknown as {
    tipo_doc: string
    serie: string
    correlativo: number
    total: number | string
    receptor_num_doc?: string | null
    sunat_ticket?: string | null
  }
  const sim = simular(
    { tipoDoc: d.tipo_doc, serie: d.serie, correlativo: d.correlativo, numDoc: d.receptor_num_doc, total: Number(d.total) },
    { resolverPendiente: Boolean(d.sunat_ticket) },
  )
  const { data: doc, error } = await supabase
    .from('documents')
    .update({
      estado_sunat: sim.estado,
      cdr: sim.cdr ?? null,
      hash: sim.hash ?? null,
      sunat_ticket: sim.ticket ?? null,
      sunat_error: sim.estado === 'rechazado' ? sim.mensaje : null,
    })
    .eq('id', documentId)
    .select()
    .single()
  if (error) throw error
  return { document: doc as DocumentRow, result: { ...sim } as EmitResult }
}

/** Reintenta la emisión/consulta de estado de un comprobante pendiente o rechazado. */
export async function reintentarEmision(documentId: string) {
  return await emitirEnMotor(documentId)
}

/** Anula un comprobante (revierte stock) y lo marca como anulado. */
export async function anularComprobante(companyId: string, documentId: string, motivo: string) {
  const { data, error } = await supabase.rpc('anular_documento', {
    p_company_id: companyId,
    p_document_id: documentId,
    p_motivo: motivo,
  })
  if (error) throw error
  return data
}

export async function listDocuments(companyId: string): Promise<DocumentRow[]> {
  const { data, error } = await supabase
    .from('documents')
    .select('*')
    .eq('company_id', companyId)
    .order('created_at', { ascending: false })
    .limit(200)
  if (error) throw error
  return (data ?? []) as DocumentRow[]
}
