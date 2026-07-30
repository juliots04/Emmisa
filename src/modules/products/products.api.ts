import { supabase } from '@/lib/supabase'
import { uid } from '@/lib/uid'
import { processImage } from '@/lib/image'
import { cachedQuery, invalidateQueryCache } from '@/stores/queryCache'
import type { Product, ProductSerial } from '@/types'

export async function listProducts(companyId: string): Promise<Product[]> {
  return cachedQuery(['products', companyId], ['products', `company:${companyId}`], async () => {
    const { data, error } = await supabase
      .from('products')
      .select('*')
      .eq('company_id', companyId)
      .order('nombre')
    if (error) throw error
    return (data ?? []) as Product[]
  })
}

export interface NewProduct {
  nombre: string
  precio: number
  tipo?: 'bien' | 'servicio'
  unidad_medida?: string
  sku?: string | null
  descripcion?: string | null
  modelo?: string | null
  barcode?: string | null
  tipo_afectacion?: string
  moneda?: string
  costo?: number
  incluye_igv?: boolean
  /** ICBPER (bolsa plástica): cobra el impuesto fijo por unidad en la venta. */
  icbper?: boolean
  /** Si controla stock (bienes) o no (servicios). */
  controla_stock?: boolean
  stock_minimo?: number
  codigo_sunat?: string | null
  linea_producto?: string | null
  registro_sanitario?: string | null
  codigo_digemid?: string | null
  codigo_fabrica?: string | null
  imagen_url?: string | null
  activo?: boolean
  category_id?: string | null
  brand_id?: string | null
  // Compra / margen
  tipo_afectacion_compra?: string | null
  aplica_ganancia?: boolean
  porcentaje_ganancia?: number
  incluye_isc?: boolean
  // Tributos / restricciones del comprobante
  detraccion?: boolean
  percepcion?: boolean
  restringir_cpe?: boolean
  canje_puntos?: boolean
  // Trazabilidad de existencias
  fecha_vencimiento?: string | null
  maneja_lotes?: boolean
  maneja_series?: boolean
  // Precios por almacén: { [warehouse_id]: precio }
  precios_almacen?: Record<string, number>
}

/** Sube una imagen de producto al bucket 'productos': validada, saneada y comprimida a
 *  WebP por el pipeline central (@/lib/image). Devuelve su URL pública. */
export async function uploadProductImage(companyId: string, file: File): Promise<string> {
  const { blob, ext, contentType } = await processImage(file)
  const path = `${companyId}/${uid()}.${ext}`
  const { error } = await supabase.storage.from('productos').upload(path, blob, {
    upsert: true,
    contentType,
  })
  if (error) throw error
  return supabase.storage.from('productos').getPublicUrl(path).data.publicUrl
}

/** Borra del bucket el objeto de una imagen (evita huérfanos). Deriva el path de la URL pública. */
export async function removeProductImage(imageUrl?: string | null): Promise<void> {
  if (!imageUrl) return
  const m = imageUrl.match(/\/productos\/(.+)$/)
  if (!m) return
  await supabase.storage
    .from('productos')
    .remove([m[1]])
    .catch(() => {})
}

export async function createProduct(companyId: string, input: NewProduct): Promise<Product> {
  const { data, error } = await supabase
    .from('products')
    .insert({
      company_id: companyId,
      nombre: input.nombre,
      // Coerción numérica: un campo vacío ('') rompería la columna numeric en PostgREST.
      precio: Number(input.precio) || 0,
      tipo: input.tipo ?? 'bien',
      unidad_medida: input.unidad_medida ?? 'NIU',
      sku: input.sku ?? null,
      descripcion: input.descripcion ?? null,
      modelo: input.modelo ?? null,
      barcode: input.barcode ?? null,
      tipo_afectacion: input.tipo_afectacion ?? '10',
      moneda: input.moneda ?? 'PEN',
      costo: Number(input.costo) || 0,
      incluye_igv: input.incluye_igv ?? true,
      icbper: input.icbper ?? false,
      controla_stock: input.controla_stock ?? (input.tipo === 'servicio' ? false : true),
      stock_minimo: Number(input.stock_minimo) || 0,
      codigo_sunat: input.codigo_sunat ?? null,
      linea_producto: input.linea_producto ?? null,
      registro_sanitario: input.registro_sanitario ?? null,
      codigo_digemid: input.codigo_digemid ?? null,
      codigo_fabrica: input.codigo_fabrica ?? null,
      imagen_url: input.imagen_url ?? null,
      activo: input.activo ?? true,
      category_id: input.category_id ?? null,
      brand_id: input.brand_id ?? null,
      tipo_afectacion_compra: input.tipo_afectacion_compra ?? null,
      aplica_ganancia: input.aplica_ganancia ?? false,
      porcentaje_ganancia: Number(input.porcentaje_ganancia) || 0,
      incluye_isc: input.incluye_isc ?? false,
      detraccion: input.detraccion ?? false,
      percepcion: input.percepcion ?? false,
      restringir_cpe: input.restringir_cpe ?? false,
      canje_puntos: input.canje_puntos ?? false,
      fecha_vencimiento: input.fecha_vencimiento ?? null,
      maneja_lotes: input.maneja_lotes ?? false,
      maneja_series: input.maneja_series ?? false,
      precios_almacen: input.precios_almacen ?? {},
    })
    .select()
    .single()
  if (error) throw error
  invalidateQueryCache()
  return data as Product
}

export async function updateProduct(
  id: string,
  patch: Partial<NewProduct>,
  expectedUpdatedAt?: string | null,
): Promise<void> {
  // Coerce los campos numéricos: un input vacío ('') rompería la columna numeric.
  const clean: Record<string, unknown> = { ...patch }
  for (const k of ['precio', 'costo', 'stock_minimo', 'porcentaje_ganancia'] as const) {
    if (k in clean) clean[k] = Number(clean[k]) || 0
  }
  let q = supabase.from('products').update(clean).eq('id', id)
  // Control optimista: si se pasa el updated_at leído al abrir, el UPDATE solo procede
  // si nadie más lo cambió mientras tanto (evita pisar cambios ajenos en silencio).
  if (expectedUpdatedAt) q = q.eq('updated_at', expectedUpdatedAt)
  const { data, error } = await q.select('id')
  if (error) throw error
  if (expectedUpdatedAt && (!data || data.length === 0)) {
    throw new Error(
      'Este producto fue modificado por otra sesión. Vuelve a abrirlo para no pisar esos cambios.',
    )
  }
  invalidateQueryCache()
}

/**
 * Elimina un producto de forma SEGURA para la trazabilidad fiscal:
 *  - Si ya tiene historial (líneas de comprobante o movimientos de inventario/kardex),
 *    hace BAJA LÓGICA (activo=false) para NO destruir el Registro de Inventario Permanente
 *    ni romper comprobantes emitidos.
 *  - Si nunca se usó, sí lo borra físicamente (y limpia su imagen del bucket).
 * Devuelve si fue baja lógica, para que la UI lo comunique.
 */
export async function deleteProduct(
  id: string,
  imageUrl?: string | null,
): Promise<{ softDeleted: boolean }> {
  const [items, movs] = await Promise.all([
    supabase
      .from('document_items')
      .select('id', { count: 'exact', head: true })
      .eq('product_id', id),
    supabase
      .from('inventory_movements')
      .select('id', { count: 'exact', head: true })
      .eq('product_id', id),
  ])
  const referenced = (items.count ?? 0) > 0 || (movs.count ?? 0) > 0
  if (referenced) {
    const { error } = await supabase.from('products').update({ activo: false }).eq('id', id)
    if (error) throw error
    invalidateQueryCache()
    return { softDeleted: true }
  }
  // .select() para verificar que SÍ se borró una fila: si RLS lo filtra (p. ej. un
  // no-admin), delete devuelve 0 filas SIN error → antes reportaba "eliminado" y
  // destruía la imagen mientras el producto seguía existiendo.
  const { data, error } = await supabase.from('products').delete().eq('id', id).select('id')
  if (error) throw error
  if (!data || data.length === 0) {
    throw new Error('No se eliminó el producto (no tienes permiso o ya no existe).')
  }
  await removeProductImage(imageUrl)
  invalidateQueryCache()
  return { softDeleted: false }
}

// ==================== Números de serie (product_serials) ====================
/**
 * Serial con datos resueltos para la tabla de Series:
 *  - producto: nombre del producto,
 *  - origen: la compra que lo ingresó (serie-número) o 'Carga manual' si se cargó a mano,
 *  - comprobante: la venta por la que salió (serie-correlativo) o '—'.
 */
export interface ProductSerialRow extends ProductSerial {
  producto: string
  origen: string
  comprobante: string
}

interface SerialJoinRow extends ProductSerial {
  purchase_id: string | null
  document_id: string | null
  products: { nombre: string } | { nombre: string }[] | null
  purchases: { serie_numero: string | null } | { serie_numero: string | null }[] | null
  documents:
    { serie: string; correlativo: number } | { serie: string; correlativo: number }[] | null
}

// Desenvuelve una relación embebida de PostgREST (viene como objeto o como array de 1).
function firstRel<T>(rel: T | T[] | null): T | null {
  if (!rel) return null
  return Array.isArray(rel) ? (rel[0] ?? null) : rel
}

/** Lista los seriales de la empresa con producto + origen (compra) + comprobante (venta). */
export async function listSerials(companyId: string): Promise<ProductSerialRow[]> {
  return cachedQuery(
    ['product-serials', companyId],
    ['product_serials', `company:${companyId}`],
    async () => {
      const { data, error } = await supabase
        .from('product_serials')
        .select('*, products!inner(nombre), purchases(serie_numero), documents(serie, correlativo)')
        .eq('company_id', companyId)
        .order('created_at', { ascending: false })
      if (error) throw error
      const rows = (data ?? []) as unknown as SerialJoinRow[]
      return rows.map((r) => {
        const pur = firstRel(r.purchases)
        const doc = firstRel(r.documents)
        return {
          id: r.id,
          company_id: r.company_id,
          product_id: r.product_id,
          serie: r.serie,
          estado: r.estado,
          activo: r.activo,
          nota: r.nota,
          created_at: r.created_at,
          producto: firstRel(r.products)?.nombre ?? '',
          origen: pur?.serie_numero ?? (r.purchase_id ? '—' : 'Carga manual'),
          comprobante: doc ? `${doc.serie}-${String(doc.correlativo).padStart(4, '0')}` : '—',
        }
      })
    },
  )
}

/**
 * Números de serie DISPONIBLES (en stock) de un producto, para la pestaña «Ver stock»
 * del historial. Devuelve solo los `serie` con estado 'disponible', ordenados. Las
 * series son a nivel de producto (product_serials no tiene almacén), no por inventario.
 */
export async function listAvailableSerials(
  companyId: string,
  productId: string,
): Promise<string[]> {
  return cachedQuery(['available-serials', companyId, productId], ['product_serials'], async () => {
    const { data, error } = await supabase
      .from('product_serials')
      .select('serie')
      .eq('company_id', companyId)
      .eq('product_id', productId)
      .eq('estado', 'disponible')
      .order('serie')
    if (error) throw error
    return (data ?? []).map((r) => (r as { serie: string }).serie)
  })
}

/**
 * Registra varios números de serie para un producto (uno por línea en la UI).
 * Ignora vacíos y duplicados exactos del propio lote; los ya existentes en BD
 * los filtra el UNIQUE (company_id, product_id, serie) → se informa cuántos entraron.
 * Devuelve las filas efectivamente insertadas.
 */
export async function createSerials(
  companyId: string,
  productId: string,
  series: string[],
): Promise<ProductSerial[]> {
  const limpias = Array.from(new Set(series.map((s) => s.trim()).filter((s) => s.length > 0)))
  if (!limpias.length) return []
  const { data, error } = await supabase
    .from('product_serials')
    .upsert(
      limpias.map((serie) => ({ company_id: companyId, product_id: productId, serie })),
      { onConflict: 'company_id,product_id,serie', ignoreDuplicates: true },
    )
    .select()
  if (error) throw error
  invalidateQueryCache()
  return (data ?? []) as ProductSerial[]
}

export async function updateSerialEstado(
  id: string,
  estado: ProductSerial['estado'],
): Promise<void> {
  const { error } = await supabase.from('product_serials').update({ estado }).eq('id', id)
  if (error) throw error
  invalidateQueryCache()
}

/** Edita la nota de un serial (garantía, IMEI, cliente, etc.). */
export async function updateSerialNota(id: string, nota: string | null): Promise<void> {
  const { error } = await supabase
    .from('product_serials')
    .update({ nota: nota || null })
    .eq('id', id)
  if (error) throw error
  invalidateQueryCache()
}

/** Activa/desactiva un serial (baja lógica manual, no toca el ciclo disponible/vendido/baja). */
export async function setSerialActivo(id: string, activo: boolean): Promise<void> {
  const { error } = await supabase.from('product_serials').update({ activo }).eq('id', id)
  if (error) throw error
  invalidateQueryCache()
}

export async function deleteSerial(id: string): Promise<void> {
  const { data, error } = await supabase.from('product_serials').delete().eq('id', id).select('id')
  if (error) throw error
  if (!data || data.length === 0) {
    throw new Error('No se eliminó el serial (no tienes permiso o ya no existe).')
  }
  invalidateQueryCache()
}
