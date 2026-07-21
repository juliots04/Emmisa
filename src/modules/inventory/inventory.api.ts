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
 * Registra un movimiento de inventario de forma ATÓMICA vía RPC de Postgres
 * (crea la fila de stock si falta, actualiza cantidad y registra el kardex en
 * una sola transacción). Evita el race condition del read-modify-write anterior.
 *   ingreso → suma · salida → resta · ajuste → fija el valor absoluto.
 * Devuelve el stock resultante del par (producto, almacén).
 */
export async function registerMovement(
  companyId: string,
  input: NewMovement,
): Promise<{ cantidad: number }> {
  if (input.tipo === 'ajuste') {
    const { data, error } = await supabase.rpc('fijar_stock', {
      p_company_id: companyId,
      p_product_id: input.productId,
      p_warehouse_id: input.warehouseId,
      p_cantidad: input.cantidad,
      p_motivo: input.motivo ?? null,
    })
    if (error) throw error
    return { cantidad: Number(data) }
  }
  const { data, error } = await supabase.rpc('ajustar_stock', {
    p_company_id: companyId,
    p_product_id: input.productId,
    p_warehouse_id: input.warehouseId,
    p_delta: input.tipo === 'ingreso' ? input.cantidad : -input.cantidad,
    p_tipo: input.tipo,
    p_motivo: input.motivo ?? null,
  })
  if (error) throw error
  return { cantidad: Number(data) }
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
