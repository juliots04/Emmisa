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
}

export interface NewPurchase {
  supplier_id?: string | null
  tipo_doc?: string
  serie_numero?: string | null
  fecha?: string
  items: NewPurchaseItem[]
}

export async function createPurchase(companyId: string, input: NewPurchase): Promise<Purchase> {
  const items = input.items.map((it) => ({
    descripcion: it.descripcion,
    cantidad: it.cantidad,
    costo: it.costo,
    total: Number((it.cantidad * it.costo).toFixed(2)),
  }))
  const total = Number(items.reduce((acc, it) => acc + it.total, 0).toFixed(2))

  const { data, error } = await supabase
    .from('purchases')
    .insert({
      company_id: companyId,
      supplier_id: input.supplier_id ?? null,
      tipo_doc: input.tipo_doc ?? '01',
      serie_numero: input.serie_numero ?? null,
      fecha: input.fecha ?? new Date().toISOString().slice(0, 10),
      total,
    })
    .select()
    .single()
  if (error) throw error

  const purchase = data as Purchase

  if (items.length > 0) {
    const { error: itemsError } = await supabase
      .from('purchase_items')
      .insert(items.map((it) => ({ purchase_id: purchase.id, ...it })))
    if (itemsError) throw itemsError
  }

  return purchase
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
