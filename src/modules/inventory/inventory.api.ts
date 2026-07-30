import { supabase } from '@/lib/supabase'
import { cachedQuery, invalidateQueryCache } from '@/stores/queryCache'
import type { Brand } from '@/types'

// ==================== Tipos del módulo de inventario ====================
export type MovementType = 'ingreso' | 'salida' | 'ajuste'

export interface Category {
  id: string
  company_id: string
  nombre: string
  descripcion: string | null
  imagen_url: string | null
  activo: boolean
  created_at: string
}

/** Campos editables de una categoría (crear/editar). */
export interface NewCategory {
  nombre: string
  descripcion?: string | null
  imagen_url?: string | null
  activo?: boolean
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
  return cachedQuery(
    ['categories', companyId],
    ['categories', `company:${companyId}`],
    async () => {
      const { data, error } = await supabase
        .from('categories')
        .select('*')
        .eq('company_id', companyId)
        .order('nombre')
      if (error) throw error
      return (data ?? []) as Category[]
    },
  )
}

export async function createCategory(companyId: string, input: NewCategory): Promise<Category> {
  const { data, error } = await supabase
    .from('categories')
    .insert({
      company_id: companyId,
      nombre: input.nombre,
      descripcion: input.descripcion ?? null,
      imagen_url: input.imagen_url ?? null,
      activo: input.activo ?? true,
    })
    .select()
    .single()
  if (error) throw error
  invalidateQueryCache()
  return data as Category
}

export async function updateCategory(id: string, input: NewCategory): Promise<void> {
  const { error } = await supabase
    .from('categories')
    .update({
      nombre: input.nombre,
      descripcion: input.descripcion ?? null,
      imagen_url: input.imagen_url ?? null,
      activo: input.activo ?? true,
    })
    .eq('id', id)
  if (error) throw error
  invalidateQueryCache()
}

/** Activa/desactiva una categoría (baja lógica) desde la tabla, sin abrir el form. */
export async function setCategoryActivo(id: string, activo: boolean): Promise<void> {
  const { error } = await supabase.from('categories').update({ activo }).eq('id', id)
  if (error) throw error
  invalidateQueryCache()
}

export async function deleteCategory(id: string): Promise<void> {
  // .select() para distinguir "0 filas por RLS/no existe" de un borrado real.
  const { data, error } = await supabase.from('categories').delete().eq('id', id).select('id')
  if (error) throw error
  if (!data || data.length === 0) {
    throw new Error('No se eliminó la categoría (no tienes permiso o ya no existe).')
  }
  invalidateQueryCache()
}

// ==================== Marcas ====================
export async function listBrands(companyId: string): Promise<Brand[]> {
  return cachedQuery(['brands', companyId], ['brands', `company:${companyId}`], async () => {
    const { data, error } = await supabase
      .from('brands')
      .select('*')
      .eq('company_id', companyId)
      .order('nombre')
    if (error) throw error
    return (data ?? []) as Brand[]
  })
}

/** Campos editables de una marca (crear/editar). */
export interface NewBrand {
  nombre: string
  descripcion?: string | null
  imagen_url?: string | null
  activo?: boolean
}

export async function createBrand(companyId: string, input: NewBrand): Promise<Brand> {
  const { data, error } = await supabase
    .from('brands')
    .insert({
      company_id: companyId,
      nombre: input.nombre,
      descripcion: input.descripcion ?? null,
      imagen_url: input.imagen_url ?? null,
      activo: input.activo ?? true,
    })
    .select()
    .single()
  if (error) throw error
  invalidateQueryCache()
  return data as Brand
}

export async function updateBrand(id: string, input: NewBrand): Promise<void> {
  const { error } = await supabase
    .from('brands')
    .update({
      nombre: input.nombre,
      descripcion: input.descripcion ?? null,
      imagen_url: input.imagen_url ?? null,
      activo: input.activo ?? true,
    })
    .eq('id', id)
  if (error) throw error
  invalidateQueryCache()
}

/** Activa/desactiva una marca (baja lógica) desde la tabla, sin abrir el form. */
export async function setBrandActivo(id: string, activo: boolean): Promise<void> {
  const { error } = await supabase.from('brands').update({ activo }).eq('id', id)
  if (error) throw error
  invalidateQueryCache()
}

export async function deleteBrand(id: string): Promise<void> {
  const { data, error } = await supabase.from('brands').delete().eq('id', id).select('id')
  if (error) throw error
  if (!data || data.length === 0) {
    throw new Error('No se eliminó la marca (no tienes permiso o ya no existe).')
  }
  invalidateQueryCache()
}

// ==================== Almacenes ====================
export async function listWarehouses(companyId: string): Promise<Warehouse[]> {
  return cachedQuery(
    ['warehouses', companyId],
    ['warehouses', `company:${companyId}`],
    async () => {
      const { data, error } = await supabase
        .from('warehouses')
        .select('*')
        .eq('company_id', companyId)
        .order('nombre')
      if (error) throw error
      return (data ?? []) as Warehouse[]
    },
  )
}

export async function createWarehouse(companyId: string, nombre: string): Promise<Warehouse> {
  const { data, error } = await supabase
    .from('warehouses')
    .insert({ company_id: companyId, nombre })
    .select()
    .single()
  if (error) throw error
  invalidateQueryCache()
  return data as Warehouse
}

// ==================== Productos (para el select) ====================
export async function listProductOptions(companyId: string): Promise<ProductOption[]> {
  return cachedQuery(
    ['product-options', companyId],
    ['products', `company:${companyId}`],
    async () => {
      const { data, error } = await supabase
        .from('products')
        .select('id,nombre')
        .eq('company_id', companyId)
        .order('nombre')
      if (error) throw error
      return (data ?? []) as ProductOption[]
    },
  )
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
  return cachedQuery(['stock', companyId], ['stock', `company:${companyId}`], async () => {
    // Se filtra por el producto de la empresa (join !inner) y se traen los nombres.
    const { data, error } = await supabase
      .from('stock')
      .select(
        'id, product_id, warehouse_id, cantidad, products!inner(nombre, company_id), warehouses!inner(nombre)',
      )
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
  })
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
    invalidateQueryCache()
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
  invalidateQueryCache()
  return { cantidad: Number(data) }
}

export async function listMovements(companyId: string): Promise<InventoryMovement[]> {
  return cachedQuery(
    ['inventory-movements', companyId],
    ['inventory_movements', `company:${companyId}`],
    async () => {
      const { data, error } = await supabase
        .from('inventory_movements')
        .select('*')
        .eq('company_id', companyId)
        .order('created_at', { ascending: false })
        .limit(200)
      if (error) throw error
      return (data ?? []) as InventoryMovement[]
    },
  )
}

/** Historial de movimientos (kardex) de un producto concreto, del más reciente al más antiguo. */
export async function listProductMovements(productId: string): Promise<InventoryMovement[]> {
  return cachedQuery(['product-movements', productId], ['inventory_movements'], async () => {
    const { data, error } = await supabase
      .from('inventory_movements')
      .select('*')
      .eq('product_id', productId)
      .order('created_at', { ascending: false })
      .limit(100)
    if (error) throw error
    return (data ?? []) as InventoryMovement[]
  })
}
