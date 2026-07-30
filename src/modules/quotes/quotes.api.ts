import { supabase } from '@/lib/supabase'
import { emitirComprobante } from '@/modules/documents/documents.api'
import { todayLocal } from '@/lib/date'
import { cachedQuery, invalidateQueryCache } from '@/stores/queryCache'
import type { TipoDoc } from '@/types'

// Tipos del módulo de cotizaciones (reflejan el esquema 0006_cotizaciones.sql).

export interface Quote {
  id: string
  company_id: string
  customer_id: string | null
  cliente_nombre: string
  fecha: string
  moneda: string
  total: number
  estado: string
  created_at: string
}

export interface QuoteItem {
  id: string
  quote_id: string
  descripcion: string
  cantidad: number
  precio_unitario: number
  total: number
  tipo_afectacion?: string
  unidad_medida?: string
  product_id?: string | null
}

// ==================== COTIZACIONES ====================
export async function listQuotes(companyId: string): Promise<Quote[]> {
  return cachedQuery(['quotes', companyId], ['quotes', `company:${companyId}`], async () => {
    const { data, error } = await supabase
      .from('quotes')
      .select('*')
      .eq('company_id', companyId)
      .order('fecha', { ascending: false })
    if (error) throw error
    return (data ?? []) as Quote[]
  })
}

export interface NewQuoteItem {
  descripcion: string
  cantidad: number
  precio_unitario: number
  tipo_afectacion?: string
  unidad_medida?: string
  product_id?: string | null
}

export interface NewQuote {
  cliente_nombre: string
  customer_id?: string | null
  moneda?: string
  fecha?: string
  items: NewQuoteItem[]
}

export async function createQuote(companyId: string, input: NewQuote): Promise<Quote> {
  const items = input.items.map((it) => ({
    descripcion: it.descripcion,
    cantidad: it.cantidad,
    precio_unitario: it.precio_unitario,
    total: Number((it.cantidad * it.precio_unitario).toFixed(2)),
    tipo_afectacion: it.tipo_afectacion ?? '10',
    unidad_medida: it.unidad_medida ?? 'NIU',
    product_id: it.product_id ?? null,
  }))
  const total = Number(items.reduce((acc, it) => acc + it.total, 0).toFixed(2))

  const { data, error } = await supabase
    .from('quotes')
    .insert({
      company_id: companyId,
      customer_id: input.customer_id ?? null,
      cliente_nombre: input.cliente_nombre,
      moneda: input.moneda ?? 'PEN',
      fecha: input.fecha ?? todayLocal(),
      total,
    })
    .select()
    .single()
  if (error) throw error

  const quote = data as Quote

  if (items.length > 0) {
    const { error: itemsError } = await supabase
      .from('quote_items')
      .insert(items.map((it) => ({ quote_id: quote.id, ...it })))
    if (itemsError) throw itemsError
  }

  invalidateQueryCache()
  return quote
}

export async function getQuoteItems(quoteId: string): Promise<QuoteItem[]> {
  return cachedQuery(['quote-items', quoteId], ['quote_items'], async () => {
    const { data, error } = await supabase.from('quote_items').select('*').eq('quote_id', quoteId)
    if (error) throw error
    return (data ?? []) as QuoteItem[]
  })
}

export async function updateQuoteEstado(id: string, estado: string): Promise<void> {
  const { error } = await supabase.from('quotes').update({ estado }).eq('id', id)
  if (error) throw error
  invalidateQueryCache()
}

export interface ConvertClienteData {
  tipoDoc: string
  numDoc?: string
  denominacion: string
  direccion?: string
}

/**
 * Convierte una cotización en una VENTA real: emite el comprobante (boleta/factura)
 * con los ítems de la cotización vía `emitirComprobante` (RPC atómica + motor SUNAT)
 * y marca la cotización como 'convertida'. Devuelve el documento emitido.
 */
export async function convertQuoteToSale(
  companyId: string,
  quote: Quote,
  tipoDoc: TipoDoc,
  cliente: ConvertClienteData,
) {
  const items = await getQuoteItems(quote.id)
  if (items.length === 0) throw new Error('La cotización no tiene ítems')

  const res = await emitirComprobante({
    companyId,
    tipoDoc,
    customerId: quote.customer_id,
    cliente,
    moneda: quote.moneda,
    // Llave estable derivada de la cotización: reintentar la conversión NO emite un
    // segundo comprobante (el RPC devuelve reused). quote.id ya es un uuid válido.
    idempotencyKey: quote.id,
    items: items.map((it) => ({
      productId: it.product_id ?? null,
      descripcion: it.descripcion,
      cantidad: Number(it.cantidad),
      precioUnitario: Number(it.precio_unitario),
      // Propaga la afectación/unidad reales (si la cotización las capturó) → no fuerza gravado 18%.
      tipoAfectacion: it.tipo_afectacion ?? '10',
      unidadMedida: it.unidad_medida ?? 'NIU',
    })),
  })
  // Solo marca la cotización como convertida si el comprobante NO fue rechazado
  // (si SUNAT lo rechaza, la cotización sigue disponible para reintentar/corregir).
  if (res.result.estado !== 'rechazado') {
    await updateQuoteEstado(quote.id, 'convertida')
  }
  return res
}
