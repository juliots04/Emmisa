import { supabase } from '@/lib/supabase'
import { uid } from '@/lib/uid'
import { cachedQuery, invalidateQueryCache } from '@/stores/queryCache'
import type { EmitResult } from '@/modules/sunat'
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
 *   2) Edge Function `emitir` envía a nuestra Fiscal API con una API key
 *      exclusivamente server-side. Fiscal API firma, envía directamente a SUNAT
 *      y genera XML, ZIP, CDR y PDF.
 */
export async function emitirComprobante(params: EmitParams) {
  if (params.items.length === 0) throw new Error('Agrega al menos un ítem')
  const serie = params.serie ?? SERIE_DEFAULT[params.tipoDoc]
  const idempotencyKey = params.idempotencyKey ?? uid()

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

  // Si ya existía y SUNAT lo resolvió, devolverlo. Si sigue pendiente se consulta
  // Fiscal API usando la misma idempotencia, sin crear otro comprobante.
  if (reserved.reused) {
    const { data: existing, error: exErr } = await supabase
      .from('documents')
      .select('*')
      .eq('id', reserved.id)
      .single()
    if (exErr) throw exErr
    if (existing.estado_sunat === 'aceptado' || existing.estado_sunat === 'rechazado') {
      const result: EmitResult = {
        estado: existing.estado_sunat,
        mensaje: 'La venta ya estaba registrada (no se duplicó)',
      }
      return { document: existing as DocumentRow, result }
    }
    return await emitirEnMotor(reserved.id)
  }

  // 2) Emisión SUNAT server-side mediante nuestra Fiscal API.
  return await emitirEnMotor(reserved.id)
}

/**
 * Llama a la Edge Function `emitir`. No existe fallback simulado: una falla de
 * configuración o red se muestra como error y el comprobante queda pendiente.
 */
export async function emitirEnMotor(documentId: string) {
  const { data, error } = await supabase.functions.invoke('emitir', { body: { documentId } })
  if (error) throw error
  invalidateQueryCache()
  return { document: data.document as DocumentRow, result: { ...data.result } as EmitResult }
}

/** Reintenta la emisión/consulta de estado de un comprobante pendiente o rechazado. */
export async function reintentarEmision(documentId: string) {
  return await emitirEnMotor(documentId)
}

export type FiscalArtifactKind =
  | 'signed_xml'
  | 'request_zip'
  | 'cdr_zip'
  | 'cdr_xml'
  | 'pdf'

/** Descarga un artefacto sin exponer la API key de Fiscal API al navegador. */
export async function descargarArtefactoFiscal(
  document: Pick<DocumentRow, 'id' | 'serie' | 'correlativo' | 'fiscal_document_id'>,
  kind: FiscalArtifactKind,
): Promise<void> {
  if (!document.fiscal_document_id) {
    throw new Error('El comprobante no tiene artefactos de Fiscal API')
  }
  const { data, error } = await supabase.functions.invoke('fiscal-artifact', {
    body: { documentId: document.id, kind },
  })
  if (error) throw error
  const contentType =
    kind === 'pdf' ? 'application/pdf' : kind.endsWith('_zip') ? 'application/zip' : 'application/xml'
  const blob =
    data instanceof Blob
      ? data
      : new Blob([typeof data === 'string' ? data : JSON.stringify(data)], { type: contentType })
  const extension = kind === 'pdf' ? 'pdf' : kind.endsWith('_zip') ? 'zip' : 'xml'
  const filename =
    `${document.serie}-${String(document.correlativo).padStart(8, '0')}-${kind}.${extension}`
  const url = URL.createObjectURL(blob)
  try {
    const anchor = window.document.createElement('a')
    anchor.href = url
    anchor.download = filename
    anchor.click()
  } finally {
    window.setTimeout(() => URL.revokeObjectURL(url), 1_000)
  }
}

/** Anula un comprobante (revierte stock) y lo marca como anulado. */
export async function anularComprobante(companyId: string, documentId: string, motivo: string) {
  const { data, error } = await supabase.rpc('anular_documento', {
    p_company_id: companyId,
    p_document_id: documentId,
    p_motivo: motivo,
  })
  if (error) throw error
  invalidateQueryCache()
  return data
}

export interface ComunicacionResult {
  identificador: string
  tipo: string // RA baja (factura/nota) · RC resumen (boleta)
  estado: string // pendiente | aceptado | rechazado
  enviada: boolean // false si la Edge Function no está desplegada aún
}

/**
 * Comunica la BAJA de un comprobante ACEPTADO a SUNAT:
 *   • Factura/nota (01/07/08) → Comunicación de Baja (RA)
 *   • Boleta (03)            → Resumen Diario con estado 3 (RC)
 * Crea la comunicación (RPC `crear_comunicacion`) y la envía por la Edge Function
 * `resumen`. Si la función no está desplegada, la comunicación queda registrada
 * como 'pendiente' para reenviarse después.
 */
export async function comunicarBajaSunat(
  companyId: string,
  documentId: string,
  motivo: string,
): Promise<ComunicacionResult> {
  void companyId
  void documentId
  void motivo
  throw new Error(
    'Las bajas aún no están implementadas en Emmisa Fiscal API. El comprobante no fue comunicado ni alterado.',
  )
  /*
  const { data, error } = await supabase.rpc('crear_comunicacion', {
    p_company_id: companyId,
    p_document_id: documentId,
    p_motivo: motivo,
  })
  if (error) throw error
  const com = data as { id: string; identificador: string; tipo: string; estado: string }
  try {
    const { data: res, error: fnErr } = await supabase.functions.invoke('resumen', {
      body: { comunicacionId: com.id },
    })
    if (fnErr) throw fnErr
    const c = res.comunicacion as { estado: string } | null
    invalidateQueryCache()
    return {
      identificador: com.identificador,
      tipo: com.tipo,
      estado: c?.estado ?? 'pendiente',
      enviada: true,
    }
  } catch {
    invalidateQueryCache()
    return { identificador: com.identificador, tipo: com.tipo, estado: 'pendiente', enviada: false }
  }
  */
}

/** Envía el comprobante por correo con PDF, XML firmado y CDR adjuntos. */
export async function enviarComprobantePorEmail(documentId: string, email: string): Promise<void> {
  const { data, error } = await supabase.functions.invoke('enviar-comprobante', {
    body: { documentId, email },
  })
  if (error) {
    const detalle = (data as { error?: string } | null)?.error
    throw new Error(detalle || error.message)
  }
  if ((data as { error?: string })?.error) throw new Error((data as { error: string }).error)
}

export interface ListDocsOpts {
  desde?: string // YYYY-MM-DD (filtra en la BD por fecha_emision)
  hasta?: string
  limit?: number
}

export async function listDocuments(
  companyId: string,
  opts: ListDocsOpts = {},
): Promise<DocumentRow[]> {
  return cachedQuery(
    ['documents', companyId, opts],
    ['documents', `company:${companyId}`],
    async () => {
      let q = supabase.from('documents').select('*').eq('company_id', companyId)
      if (opts.desde) q = q.gte('fecha_emision', opts.desde)
      if (opts.hasta) q = q.lte('fecha_emision', opts.hasta)
      const { data, error } = await q
        .order('created_at', { ascending: false })
        .limit(opts.limit ?? 500)
      if (error) throw error
      return (data ?? []) as DocumentRow[]
    },
  )
}

/** Una línea de venta de un producto (para el historial "Últimas ventas"). */
export interface ProductSaleRow {
  id: string
  fecha: string // fecha_emision (YYYY-MM-DD)
  comprobante: string // p.ej. 'F001-0123'
  tipoDoc: string // 01 factura, 03 boleta, 07 NC, 08 ND
  estado: string // estado_sunat
  cantidad: number
  precioUnitario: number
  total: number
  moneda: string
}

interface SaleJoinRow {
  serie: string
  correlativo: number
  tipo_doc: string
  fecha_emision: string
  estado_sunat: string
  moneda: string | null
  document_items: {
    id: string
    cantidad: number | string
    precio_unitario: number | string
    total: number | string
  }[]
}

/**
 * Últimas ventas de un producto: líneas de `document_items` del producto con la
 * cabecera del comprobante (serie-correlativo, fecha, estado). De la más reciente
 * a la más antigua. El `!inner` + el filtro sobre la tabla embebida dejan solo los
 * comprobantes con el producto y, dentro de cada uno, solo sus líneas. El
 * aislamiento por empresa lo refuerza el RLS (además del company_id explícito).
 */
export async function listProductSales(
  companyId: string,
  productId: string,
): Promise<ProductSaleRow[]> {
  return cachedQuery(
    ['product-sales', companyId, productId],
    ['documents', 'document_items', `company:${companyId}`],
    async () => {
      const { data, error } = await supabase
        .from('documents')
        .select(
          'serie, correlativo, tipo_doc, fecha_emision, estado_sunat, moneda, document_items!inner(id, cantidad, precio_unitario, total)',
        )
        .eq('company_id', companyId)
        .eq('document_items.product_id', productId)
        .order('fecha_emision', { ascending: false })
        .order('created_at', { ascending: false })
        .limit(50)
      if (error) throw error
      const rows = (data ?? []) as unknown as SaleJoinRow[]
      return rows.flatMap((d) =>
        (d.document_items ?? []).map((it) => ({
          id: it.id,
          fecha: d.fecha_emision,
          comprobante: `${d.serie}-${String(d.correlativo).padStart(4, '0')}`,
          tipoDoc: d.tipo_doc,
          estado: d.estado_sunat,
          cantidad: Number(it.cantidad),
          precioUnitario: Number(it.precio_unitario),
          total: Number(it.total),
          moneda: d.moneda ?? 'PEN',
        })),
      )
    },
  )
}

/** Trae documentos por id (para resolver referencias de NC/ND de otro periodo). */
export async function getDocumentsByIds(companyId: string, ids: string[]): Promise<DocumentRow[]> {
  if (!ids.length) return []
  return cachedQuery(
    ['documents-by-id', companyId, [...ids].sort()],
    ['documents', `company:${companyId}`],
    async () => {
      const { data, error } = await supabase
        .from('documents')
        .select('*')
        .eq('company_id', companyId)
        .in('id', ids)
      if (error) throw error
      return (data ?? []) as DocumentRow[]
    },
  )
}

/**
 * Trae TODOS los documentos del rango, paginando con .range() hasta agotar.
 * Úsese para libros/reportes legales (PLE): `listDocuments` corta en 500/1000 y
 * truncaría el Registro de Ventas en silencio (subdeclaración de IGV).
 */
export async function listAllDocuments(
  companyId: string,
  opts: ListDocsOpts = {},
): Promise<DocumentRow[]> {
  return cachedQuery(
    ['all-documents', companyId, opts],
    ['documents', `company:${companyId}`],
    async () => {
      const CHUNK = 1000
      const rows: DocumentRow[] = []
      for (let from = 0; ; from += CHUNK) {
        let q = supabase.from('documents').select('*').eq('company_id', companyId)
        if (opts.desde) q = q.gte('fecha_emision', opts.desde)
        if (opts.hasta) q = q.lte('fecha_emision', opts.hasta)
        const { data, error } = await q
          .order('created_at', { ascending: false })
          .range(from, from + CHUNK - 1)
        if (error) throw error
        const batch = (data ?? []) as DocumentRow[]
        rows.push(...batch)
        if (batch.length < CHUNK) break
      }
      return rows
    },
  )
}
