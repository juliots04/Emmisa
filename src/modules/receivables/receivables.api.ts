import { supabase } from '@/lib/supabase'

export interface Receivable {
  id: string
  numero: string
  cliente: string | null
  total: number
  saldo: number
  vencimiento: string | null
  estado_pago: string
}

/** Cuentas por cobrar (comprobantes con saldo pendiente), agregadas en el servidor. */
export async function listReceivables(companyId: string): Promise<Receivable[]> {
  const { data, error } = await supabase.rpc('reporte_cuentas_por_cobrar', { p_company_id: companyId })
  if (error) throw error
  return (data ?? []) as Receivable[]
}

/** Registra un abono (cobro) a un comprobante; devuelve el nuevo saldo. */
export async function registrarAbono(input: {
  companyId: string
  documentId: string
  monto: number
  medio: string
  referencia?: string
  cashSessionId?: string | null
}): Promise<{ tipo: string; saldo: number }> {
  const { data, error } = await supabase.rpc('registrar_abono', {
    p_company_id: input.companyId,
    p_monto: input.monto,
    p_document_id: input.documentId,
    p_purchase_id: null,
    p_medio: input.medio,
    p_referencia: input.referencia ?? null,
    p_cash_session_id: input.cashSessionId ?? null,
  })
  if (error) throw error
  return data as { tipo: string; saldo: number }
}
