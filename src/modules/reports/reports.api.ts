import { supabase } from '@/lib/supabase'
import { fmtFecha } from '@/lib/date'
import { cachedQuery } from '@/stores/queryCache'

// Los reportes se agregan en el SERVIDOR (RPCs de la migración 0015) para no
// depender del límite de filas de PostgREST (que causaba subconteo de importes).

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

export async function getSummary(companyId: string): Promise<SalesSummary> {
  return cachedQuery(
    ['report-summary', companyId],
    ['reports', `company:${companyId}`],
    async () => {
      const { data, error } = await supabase.rpc('reporte_resumen', { p_company_id: companyId })
      if (error) throw error
      const r = (data ?? {}) as { ventas?: number; n?: number; ticket_prom?: number }
      return {
        totalFacturado: Number(r.ventas ?? 0),
        numComprobantes: Number(r.n ?? 0),
        ticketPromedio: Number(r.ticket_prom ?? 0),
      }
    },
  )
}

export async function getSalesByDay(companyId: string, days = 14): Promise<SalesByDay[]> {
  return cachedQuery(
    ['report-sales-day', companyId, days],
    ['reports', `company:${companyId}`],
    async () => {
      const { data, error } = await supabase.rpc('reporte_ventas_por_dia', {
        p_company_id: companyId,
        p_dias: days,
      })
      if (error) throw error
      const rows = (data ?? []) as { dia: string; total: number; n: number }[]
      return rows.map((r) => ({
        fecha: fmtFecha(r.dia),
        total: Number(r.total),
        cantidad: Number(r.n),
      }))
    },
  )
}

export async function getTopProducts(companyId: string, limit = 10): Promise<TopProduct[]> {
  return cachedQuery(
    ['report-top-products', companyId, limit],
    ['reports', `company:${companyId}`],
    async () => {
      const { data, error } = await supabase.rpc('reporte_top_productos', {
        p_company_id: companyId,
        p_limit: limit,
      })
      if (error) throw error
      const rows = (data ?? []) as { descripcion: string; cantidad: number; monto: number }[]
      return rows.map((r) => ({
        descripcion: r.descripcion,
        cantidad: Number(r.cantidad),
        total: Number(r.monto),
      }))
    },
  )
}

/** Comprobantes por estado SUNAT (aceptado/rechazado/pendiente/anulado). */
export async function getByEstado(
  companyId: string,
): Promise<Record<string, { n: number; total: number }>> {
  return cachedQuery(
    ['report-by-status', companyId],
    ['reports', `company:${companyId}`],
    async () => {
      const { data, error } = await supabase.rpc('reporte_por_estado', { p_company_id: companyId })
      if (error) throw error
      return (data ?? {}) as Record<string, { n: number; total: number }>
    },
  )
}
