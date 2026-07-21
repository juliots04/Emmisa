import { supabase } from '@/lib/supabase'
import type { EstadoSunat } from '@/types'

// Solo los comprobantes aceptados por SUNAT cuentan como ventas reales.
const ACEPTADO: EstadoSunat = 'aceptado'

export interface SalesSummary {
  totalFacturado: number
  numComprobantes: number
  ticketPromedio: number
}

export interface SalesByDay {
  fecha: string
  total: number
  cantidad: number
}

export interface TopProduct {
  descripcion: string
  cantidad: number
  total: number
}

/**
 * Resumen de ventas: total facturado (suma de `total` de comprobantes aceptados),
 * número de comprobantes y ticket promedio.
 */
export async function getSummary(companyId: string): Promise<SalesSummary> {
  const { data, error } = await supabase
    .from('documents')
    .select('total')
    .eq('company_id', companyId)
    .eq('estado_sunat', ACEPTADO)
  if (error) throw error

  const rows = (data ?? []) as { total: number }[]
  const totalFacturado = rows.reduce((acc, r) => acc + Number(r.total), 0)
  const numComprobantes = rows.length
  const ticketPromedio = numComprobantes ? totalFacturado / numComprobantes : 0
  return { totalFacturado, numComprobantes, ticketPromedio }
}

/**
 * Ventas agrupadas por día (últimos `days` días). Trae los comprobantes del rango
 * y agrupa en JS por fecha local. El orden ascendente de `created_at` garantiza
 * que los buckets del Map queden en orden cronológico.
 */
export async function getSalesByDay(companyId: string, days = 14): Promise<SalesByDay[]> {
  const since = new Date()
  since.setDate(since.getDate() - (days - 1))
  since.setHours(0, 0, 0, 0)

  const { data, error } = await supabase
    .from('documents')
    .select('total, created_at')
    .eq('company_id', companyId)
    .eq('estado_sunat', ACEPTADO)
    .gte('created_at', since.toISOString())
    .order('created_at', { ascending: true })
  if (error) throw error

  const rows = (data ?? []) as { total: number; created_at: string }[]
  const byDay = new Map<string, SalesByDay>()
  for (const r of rows) {
    const fecha = new Date(r.created_at).toLocaleDateString('es-PE')
    const bucket = byDay.get(fecha) ?? { fecha, total: 0, cantidad: 0 }
    bucket.total += Number(r.total)
    bucket.cantidad += 1
    byDay.set(fecha, bucket)
  }
  return [...byDay.values()]
}

/**
 * Productos más vendidos: trae los ítems de la empresa (join con `documents`
 * por `company_id`, solo aceptados), agrupa por descripción sumando cantidad y
 * total, y ordena por total descendente.
 */
export async function getTopProducts(companyId: string, limit = 10): Promise<TopProduct[]> {
  const { data, error } = await supabase
    .from('document_items')
    .select('descripcion, cantidad, total, documents!inner(company_id, estado_sunat)')
    .eq('documents.company_id', companyId)
    .eq('documents.estado_sunat', ACEPTADO)
  if (error) throw error

  const rows = (data ?? []) as unknown as {
    descripcion: string
    cantidad: number
    total: number
  }[]

  const byDesc = new Map<string, TopProduct>()
  for (const r of rows) {
    const bucket = byDesc.get(r.descripcion) ?? {
      descripcion: r.descripcion,
      cantidad: 0,
      total: 0,
    }
    bucket.cantidad += Number(r.cantidad)
    bucket.total += Number(r.total)
    byDesc.set(r.descripcion, bucket)
  }
  return [...byDesc.values()].sort((a, b) => b.total - a.total).slice(0, limit)
}
