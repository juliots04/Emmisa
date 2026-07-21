import { supabase } from '@/lib/supabase'
import type { Product } from '@/types'

export async function listProducts(companyId: string): Promise<Product[]> {
  const { data, error } = await supabase
    .from('products')
    .select('*')
    .eq('company_id', companyId)
    .order('nombre')
  if (error) throw error
  return (data ?? []) as Product[]
}

export interface NewProduct {
  nombre: string
  precio: number
  tipo?: 'bien' | 'servicio'
  unidad_medida?: string
  sku?: string | null
  nombre_secundario?: string | null
  descripcion?: string | null
  modelo?: string | null
  barcode?: string | null
  tipo_afectacion?: string
  moneda?: string
  costo?: number
  incluye_igv?: boolean
  stock_minimo?: number
  codigo_sunat?: string | null
  linea_producto?: string | null
  registro_sanitario?: string | null
  codigo_digemid?: string | null
  codigo_fabrica?: string | null
}

export async function createProduct(companyId: string, input: NewProduct): Promise<Product> {
  const { data, error } = await supabase
    .from('products')
    .insert({
      company_id: companyId,
      nombre: input.nombre,
      precio: input.precio,
      tipo: input.tipo ?? 'bien',
      unidad_medida: input.unidad_medida ?? 'NIU',
      sku: input.sku ?? null,
      nombre_secundario: input.nombre_secundario ?? null,
      descripcion: input.descripcion ?? null,
      modelo: input.modelo ?? null,
      barcode: input.barcode ?? null,
      tipo_afectacion: input.tipo_afectacion ?? '10',
      moneda: input.moneda ?? 'PEN',
      costo: input.costo ?? 0,
      incluye_igv: input.incluye_igv ?? true,
      stock_minimo: input.stock_minimo ?? 0,
      codigo_sunat: input.codigo_sunat ?? null,
      linea_producto: input.linea_producto ?? null,
      registro_sanitario: input.registro_sanitario ?? null,
      codigo_digemid: input.codigo_digemid ?? null,
      codigo_fabrica: input.codigo_fabrica ?? null,
    })
    .select()
    .single()
  if (error) throw error
  return data as Product
}

export async function updateProduct(id: string, patch: Partial<NewProduct>): Promise<void> {
  const { error } = await supabase.from('products').update(patch).eq('id', id)
  if (error) throw error
}

export async function deleteProduct(id: string): Promise<void> {
  const { error } = await supabase.from('products').delete().eq('id', id)
  if (error) throw error
}
