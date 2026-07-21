import { supabase } from '@/lib/supabase'

// Tipos del módulo de compras (reflejan el esquema 0002_compras.sql).

export interface Supplier {
  id: string
  company_id: string
  ruc: string | null
  razon_social: string
  contacto: string | null
  created_at: string
}

export interface Purchase {
  id: string
  company_id: string
  supplier_id: string | null
  tipo_doc: string
  serie_numero: string | null
  fecha: string
  total: number
  created_at: string
}

export interface PurchaseItem {
  id: string
  purchase_id: string
  descripcion: string
  cantidad: number
  costo: number
  total: number
}

export interface Expense {
  id: string
  company_id: string
  concepto: string
  monto: number
  fecha: string
  categoria: string | null
  created_at: string
}

// ==================== PROVEEDORES ====================
export async function listSuppliers(companyId: string): Promise<Supplier[]> {
  const { data, error } = await supabase
    .from('suppliers')
    .select('*')
    .eq('company_id', companyId)
    .order('razon_social')
  if (error) throw error
  return (data ?? []) as Supplier[]
}

export interface NewSupplier {
  razon_social: string
  ruc?: string | null
  contacto?: string | null
}

export async function createSupplier(companyId: string, input: NewSupplier): Promise<Supplier> {
  const { data, error } = await supabase
    .from('suppliers')
    .insert({
      company_id: companyId,
      razon_social: input.razon_social,
      ruc: input.ruc ?? null,
      contacto: input.contacto ?? null,
    })
    .select()
    .single()
  if (error) throw error
  return data as Supplier
}

export async function updateSupplier(id: string, input: NewSupplier): Promise<Supplier> {
  const { data, error } = await supabase
    .from('suppliers')
    .update({
      razon_social: input.razon_social,
      ruc: input.ruc ?? null,
      contacto: input.contacto ?? null,
    })
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as Supplier
}

export async function deleteSupplier(id: string): Promise<void> {
  const { error } = await supabase.from('suppliers').delete().eq('id', id)
  if (error) throw error
}

// ==================== COMPRAS ====================
export async function listPurchases(companyId: string): Promise<Purchase[]> {
  const { data, error } = await supabase
    .from('purchases')
    .select('*')
    .eq('company_id', companyId)
    .order('fecha', { ascending: false })
  if (error) throw error
  return (data ?? []) as Purchase[]
}

export interface NewPurchaseItem {
  descripcion: string
  cantidad: number
  costo: number
  productId?: string | null
}

export interface NewPurchase {
  supplier_id?: string | null
  tipo_doc?: string
  serie_numero?: string | null
  fecha?: string
  items: NewPurchaseItem[]
  moneda?: string
  /** contado | credito (crédito genera cuenta por pagar). */
  condicion_pago?: string
  fecha_vencimiento?: string | null
  /** Si true, la compra INGRESA a inventario (recepción de mercadería). */
  afecta_inventario?: boolean
  warehouse_id?: string | null
}

/**
 * Registra la compra de forma TRANSACCIONAL vía RPC `registrar_compra`:
 * inserta cabecera + ítems, separa IGV, arma la cuenta por pagar (si es a crédito)
 * y — si afecta_inventario — ingresa la mercadería al stock (kardex).
 */
export async function createPurchase(companyId: string, input: NewPurchase): Promise<Purchase> {
  const { data: res, error } = await supabase.rpc('registrar_compra', {
    p_company_id: companyId,
    p_supplier_id: input.supplier_id ?? null,
    p_tipo_doc: input.tipo_doc ?? '01',
    p_serie_numero: input.serie_numero ?? null,
    p_fecha: input.fecha ?? null,
    p_items: input.items.map((it) => ({
      product_id: it.productId ?? null,
      descripcion: it.descripcion,
      cantidad: it.cantidad,
      costo: it.costo,
    })),
    p_moneda: input.moneda ?? 'PEN',
    p_condicion_pago: input.condicion_pago ?? 'contado',
    p_fecha_vencimiento: input.fecha_vencimiento ?? null,
    p_afecta_inventario: input.afecta_inventario ?? false,
    p_warehouse_id: input.warehouse_id ?? null,
  })
  if (error) throw error
  const { id } = res as { id: string }
  const { data: purchase, error: getErr } = await supabase.from('purchases').select('*').eq('id', id).single()
  if (getErr) throw getErr
  return purchase as Purchase
}

export async function listPurchaseItems(purchaseId: string): Promise<PurchaseItem[]> {
  const { data, error } = await supabase
    .from('purchase_items')
    .select('*')
    .eq('purchase_id', purchaseId)
  if (error) throw error
  return (data ?? []) as PurchaseItem[]
}

// ==================== GASTOS ====================
export async function listExpenses(companyId: string): Promise<Expense[]> {
  const { data, error } = await supabase
    .from('expenses')
    .select('*')
    .eq('company_id', companyId)
    .order('fecha', { ascending: false })
  if (error) throw error
  return (data ?? []) as Expense[]
}

export interface NewExpense {
  concepto: string
  monto: number
  fecha?: string
  categoria?: string | null
}

export async function createExpense(companyId: string, input: NewExpense): Promise<Expense> {
  const { data, error } = await supabase
    .from('expenses')
    .insert({
      company_id: companyId,
      concepto: input.concepto,
      monto: input.monto,
      fecha: input.fecha ?? new Date().toISOString().slice(0, 10),
      categoria: input.categoria ?? null,
    })
    .select()
    .single()
  if (error) throw error
  return data as Expense
}
