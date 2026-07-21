import { supabase } from '@/lib/supabase'

// ==================== Tipos del módulo de inventario ====================
export type MovementType = 'ingreso' | 'salida' | 'ajuste'

export interface Category {
  id: string
  company_id: string
  nombre: string
  created_at: string
}

export interface Warehouse {
  id: string
  company_id: string
  nombre: string
  created_at: string
}

export interface StockRow {
  id: string
  product_id: string
  warehouse_id: string
  cantidad: number
  producto: string
  almacen: string
}

export interface InventoryMovement {
  id: string
  company_id: string
  product_id: string
  warehouse_id: string
  tipo: MovementType
  cantidad: number
  motivo: string | null
  created_at: string
}

export interface ProductOption {
  id: string
  nombre: string
}

// ==================== Categorías ====================
export async function listCategories(companyId: string): Promise<Category[]> {
  const { data, error } = await supabase
    .from('categories')
    .select('*')
    .eq('company_id', companyId)
    .order('nombre')
  if (error) throw error
  return (data ?? []) as Category[]
}

export async function createCategory(companyId: string, nombre: string): Promise<Category> {
  const { data, error } = await supabase
    .from('categories')
    .insert({ company_id: companyId, nombre })
    .select()
    .single()
  if (error) throw error
  return data as Category
}

// ==================== Almacenes ====================
export async function listWarehouses(companyId: string): Promise<Warehouse[]> {
  const { data, error } = await supabase
    .from('warehouses')
    .select('*')
    .eq('company_id', companyId)
    .order('nombre')
  if (error) throw error
  return (data ?? []) as Warehouse[]
}

export async function createWarehouse(companyId: string, nombre: string): Promise<Warehouse> {
  const { data, error } = await supabase
    .from('warehouses')
    .insert({ company_id: companyId, nombre })
    .select()
    .single()
  if (error) throw error
  return data as Warehouse
}

// ==================== Productos (para el select) ====================
export async function listProductOptions(companyId: string): Promise<ProductOption[]> {
  const { data, error } = await supabase
    .from('products')
    .select('id,nombre')
    .eq('company_id', companyId)
    .order('nombre')
  if (error) throw error
  return (data ?? []) as ProductOption[]
}

// ==================== Stock ====================
interface StockJoinRow {
  id: string
  product_id: string
  warehouse_id: string
  cantidad: number
  products: { nombre: string } | { nombre: string }[] | null
  warehouses: { nombre: string } | { nombre: string }[] | null
}

function relName(rel: { nombre: string } | { nombre: string }[] | null): string {
  if (!rel) return ''
  return Array.isArray(rel) ? (rel[0]?.nombre ?? '') : rel.nombre
}

export async function listStock(companyId: string): Promise<StockRow[]> {
  // Se filtra por el producto de la empresa (join !inner) y se traen los nombres.
  const { data, error } = await supabase
    .from('stock')
    .select('id, product_id, warehouse_id, cantidad, products!inner(nombre, company_id), warehouses!inner(nombre)')
    .eq('products.company_id', companyId)
    .order('cantidad', { ascending: false })
  if (error) throw error
  const rows = (data ?? []) as unknown as StockJoinRow[]
  return rows.map((r) => ({
    id: r.id,
    product_id: r.product_id,
    warehouse_id: r.warehouse_id,
    cantidad: Number(r.cantidad),
    producto: relName(r.products),
    almacen: relName(r.warehouses),
  }))
}

// ==================== Movimientos ====================
export interface NewMovement {
  productId: string
  warehouseId: string
  tipo: MovementType
  cantidad: number
  motivo?: string | null
}

/**
 * Ajusta la fila de stock del par (producto, almacén) según el tipo de movimiento:
 * ingreso suma, salida resta y ajuste fija el valor absoluto. Usa upsert por el
 * unique(product_id, warehouse_id).
 */
async function applyStockDelta(input: NewMovement): Promise<void> {
  const { data: existing, error: readErr } = await supabase
    .from('stock')
    .select('cantidad')
    .eq('product_id', input.productId)
    .eq('warehouse_id', input.warehouseId)
    .maybeSingle()
  if (readErr) throw readErr

  const actual = existing ? Number((existing as { cantidad: number }).cantidad) : 0
  let cantidad: number
  if (input.tipo === 'ingreso') cantidad = actual + input.cantidad
  else if (input.tipo === 'salida') cantidad = actual - input.cantidad
  else cantidad = input.cantidad // ajuste: valor absoluto

  const { error: upErr } = await supabase.from('stock').upsert(
    { product_id: input.productId, warehouse_id: input.warehouseId, cantidad },
    { onConflict: 'product_id,warehouse_id' },
  )
  if (upErr) throw upErr
}

export async function registerMovement(
  companyId: string,
  input: NewMovement,
): Promise<InventoryMovement> {
  const { data, error } = await supabase
    .from('inventory_movements')
    .insert({
      company_id: companyId,
      product_id: input.productId,
      warehouse_id: input.warehouseId,
      tipo: input.tipo,
      cantidad: input.cantidad,
      motivo: input.motivo ?? null,
    })
    .select()
    .single()
  if (error) throw error

  // Además, refleja el movimiento en la fila de stock.
  await applyStockDelta(input)

  return data as InventoryMovement
}

export async function listMovements(companyId: string): Promise<InventoryMovement[]> {
  const { data, error } = await supabase
    .from('inventory_movements')
    .select('*')
    .eq('company_id', companyId)
    .order('created_at', { ascending: false })
    .limit(200)
  if (error) throw error
  return (data ?? []) as InventoryMovement[]
}
