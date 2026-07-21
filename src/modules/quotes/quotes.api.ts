import { supabase } from '@/lib/supabase'

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
}

// ==================== COTIZACIONES ====================
export async function listQuotes(companyId: string): Promise<Quote[]> {
  const { data, error } = await supabase
    .from('quotes')
    .select('*')
    .eq('company_id', companyId)
    .order('fecha', { ascending: false })
  if (error) throw error
  return (data ?? []) as Quote[]
}

export interface NewQuoteItem {
  descripcion: string
  cantidad: number
  precio_unitario: number
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
  }))
  const total = Number(items.reduce((acc, it) => acc + it.total, 0).toFixed(2))

  const { data, error } = await supabase
    .from('quotes')
    .insert({
      company_id: companyId,
      customer_id: input.customer_id ?? null,
      cliente_nombre: input.cliente_nombre,
      moneda: input.moneda ?? 'PEN',
      fecha: input.fecha ?? new Date().toISOString().slice(0, 10),
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

  return quote
}

export async function getQuoteItems(quoteId: string): Promise<QuoteItem[]> {
  const { data, error } = await supabase
    .from('quote_items')
    .select('*')
    .eq('quote_id', quoteId)
  if (error) throw error
  return (data ?? []) as QuoteItem[]
}
