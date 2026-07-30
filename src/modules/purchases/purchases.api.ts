import { supabase } from '@/lib/supabase'
import { todayLocal } from '@/lib/date'
import { cachedQuery, invalidateQueryCache } from '@/stores/queryCache'
import type { PurchasePle } from '@/lib/ple'

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
  return cachedQuery(['suppliers', companyId], ['suppliers', `company:${companyId}`], async () => {
    const { data, error } = await supabase
      .from('suppliers')
      .select('*')
      .eq('company_id', companyId)
      .order('razon_social')
    if (error) throw error
    return (data ?? []) as Supplier[]
  })
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
  invalidateQueryCache()
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
  invalidateQueryCache()
  return data as Supplier
}

export async function deleteSupplier(id: string): Promise<void> {
  // .select() devuelve las filas borradas: si RLS lo bloquea (DELETE solo admin), viene vacío
  // y NO lanza error → lo tratamos como permiso denegado en vez de un "éxito" falso.
  const { data, error } = await supabase.from('suppliers').delete().eq('id', id).select('id')
  if (error) throw error
  if (!data || data.length === 0)
    throw new Error('No se pudo eliminar el proveedor (requiere permiso de administrador).')
  invalidateQueryCache()
}

// ==================== COMPRAS ====================
export async function listPurchases(companyId: string): Promise<Purchase[]> {
  return cachedQuery(['purchases', companyId], ['purchases', `company:${companyId}`], async () => {
    const { data, error } = await supabase
      .from('purchases')
      .select('*')
      .eq('company_id', companyId)
      .order('fecha', { ascending: false })
    if (error) throw error
    return (data ?? []) as Purchase[]
  })
}

export interface NewPurchaseItem {
  descripcion: string
  cantidad: number
  costo: number
  productId?: string | null
  /** Si false, la línea NO da crédito fiscal (exonerada/inafecta). Por defecto true. */
  afecto?: boolean
  /** Números de serie de las unidades que ingresan (solo productos que «manejan series»). */
  series?: string[]
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
  /** Tipo de cambio (obligatorio si moneda ≠ PEN). */
  tipo_cambio?: number
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
      afecto: it.afecto ?? true,
      // Solo se incluye si la línea trae seriales (el RPC lo ignora si no está).
      ...(it.series && it.series.length ? { series: it.series } : {}),
    })),
    p_moneda: input.moneda ?? 'PEN',
    p_condicion_pago: input.condicion_pago ?? 'contado',
    p_fecha_vencimiento: input.fecha_vencimiento ?? null,
    p_afecta_inventario: input.afecta_inventario ?? false,
    p_warehouse_id: input.warehouse_id ?? null,
    p_tipo_cambio: input.moneda === 'USD' ? (input.tipo_cambio ?? 1) : 1,
  })
  if (error) throw error
  const { id } = res as { id: string }
  const { data: purchase, error: getErr } = await supabase
    .from('purchases')
    .select('*')
    .eq('id', id)
    .single()
  if (getErr) throw getErr
  invalidateQueryCache()
  return purchase as Purchase
}

export async function listPurchaseItems(purchaseId: string): Promise<PurchaseItem[]> {
  return cachedQuery(['purchase-items', purchaseId], ['purchase_items'], async () => {
    const { data, error } = await supabase
      .from('purchase_items')
      .select('*')
      .eq('purchase_id', purchaseId)
    if (error) throw error
    return (data ?? []) as PurchaseItem[]
  })
}

/** Una línea de compra de un producto (para el historial "Últimas compras"). */
export interface ProductPurchaseRow {
  id: string
  fecha: string // YYYY-MM-DD
  comprobante: string // serie_numero o '—'
  tipoDoc: string
  cantidad: number
  costo: number
  total: number
  moneda: string
}

interface PurchaseJoinRow {
  tipo_doc: string
  serie_numero: string | null
  fecha: string
  moneda: string | null
  purchase_items: {
    id: string
    cantidad: number | string
    costo: number | string
    total: number | string
  }[]
}

/**
 * Últimas compras de un producto: líneas de `purchase_items` del producto con la
 * cabecera de la compra (serie/número, fecha, moneda). De la más reciente a la más
 * antigua. Igual que en ventas, `!inner` + el filtro sobre la tabla embebida dejan
 * solo las compras con el producto y sus líneas. RLS aísla por empresa.
 */
async function fetchProductPurchases(
  companyId: string,
  productId: string,
): Promise<ProductPurchaseRow[]> {
  const { data, error } = await supabase
    .from('purchases')
    .select(
      'tipo_doc, serie_numero, fecha, moneda, purchase_items!inner(id, cantidad, costo, total)',
    )
    .eq('company_id', companyId)
    .eq('purchase_items.product_id', productId)
    .order('fecha', { ascending: false })
    .order('created_at', { ascending: false })
    .limit(50)
  if (error) throw error
  const rows = (data ?? []) as unknown as PurchaseJoinRow[]
  return rows.flatMap((p) =>
    (p.purchase_items ?? []).map((it) => ({
      id: it.id,
      fecha: p.fecha,
      comprobante: p.serie_numero || '—',
      tipoDoc: p.tipo_doc,
      cantidad: Number(it.cantidad),
      costo: Number(it.costo),
      total: Number(it.total),
      moneda: p.moneda ?? 'PEN',
    })),
  )
}

export function listProductPurchases(
  companyId: string,
  productId: string,
): Promise<ProductPurchaseRow[]> {
  return cachedQuery(
    ['product-purchases', companyId, productId],
    ['purchases', 'purchase_items', `company:${companyId}`],
    () => fetchProductPurchases(companyId, productId),
  )
}

/** Compras del periodo con datos del proveedor, para el Registro de Compras (PLE 8.1). */
async function fetchPurchasesForPle(
  companyId: string,
  desde: string,
  hasta: string,
): Promise<PurchasePle[]> {
  // Paginado con .range() hasta agotar: PostgREST corta en ~1000 filas por defecto,
  // lo que truncaría el Registro de Compras (subdeclaración de crédito fiscal).
  const CHUNK = 1000
  const rows: {
    supplier_id: string | null
    fecha: string
    tipo_doc: string
    serie_numero: string | null
    total: number | string
    total_gravado: number | string | null
    total_igv: number | string | null
    moneda: string | null
    tipo_cambio: number | string | null
  }[] = []
  for (let from = 0; ; from += CHUNK) {
    const { data, error } = await supabase
      .from('purchases')
      .select(
        'supplier_id, fecha, tipo_doc, serie_numero, total, total_gravado, total_igv, moneda, tipo_cambio',
      )
      .eq('company_id', companyId)
      .gte('fecha', desde)
      .lte('fecha', hasta)
      .order('fecha')
      .range(from, from + CHUNK - 1)
    if (error) throw error
    const batch = data ?? []
    rows.push(...batch)
    if (batch.length < CHUNK) break
  }
  const { data: sups, error: e2 } = await supabase
    .from('suppliers')
    .select('id, ruc, razon_social')
    .eq('company_id', companyId)
  if (e2) throw e2
  const supMap = new Map((sups ?? []).map((s) => [s.id, s]))
  return (rows ?? []).map((r) => {
    const sup = r.supplier_id ? supMap.get(r.supplier_id) : undefined
    return {
      fecha: r.fecha,
      tipo_doc: r.tipo_doc,
      serie_numero: r.serie_numero,
      total: Number(r.total),
      total_gravado: Number(r.total_gravado ?? 0),
      total_igv: Number(r.total_igv ?? 0),
      moneda: r.moneda ?? 'PEN',
      tipo_cambio: r.tipo_cambio != null ? Number(r.tipo_cambio) : null,
      proveedor_ruc: sup?.ruc ?? null,
      proveedor_nombre: sup?.razon_social ?? null,
    }
  })
}

export function listPurchasesForPle(
  companyId: string,
  desde: string,
  hasta: string,
): Promise<PurchasePle[]> {
  return cachedQuery(
    ['purchases-ple', companyId, desde, hasta],
    ['purchases', 'suppliers', `company:${companyId}`],
    () => fetchPurchasesForPle(companyId, desde, hasta),
  )
}

// ==================== GASTOS ====================
export async function listExpenses(companyId: string): Promise<Expense[]> {
  return cachedQuery(['expenses', companyId], ['expenses', `company:${companyId}`], async () => {
    const { data, error } = await supabase
      .from('expenses')
      .select('*')
      .eq('company_id', companyId)
      .order('fecha', { ascending: false })
    if (error) throw error
    return (data ?? []) as Expense[]
  })
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
      fecha: input.fecha ?? todayLocal(),
      categoria: input.categoria ?? null,
    })
    .select()
    .single()
  if (error) throw error
  invalidateQueryCache()
  return data as Expense
}
