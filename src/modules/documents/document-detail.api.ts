import { supabase } from '@/lib/supabase'
import { cachedQuery } from '@/stores/queryCache'
import type { Customer, DocumentRow } from '@/types'

/**
 * Fila de la tabla `document_items` (línea de un comprobante).
 * El tipo se define aquí (en el propio módulo) para no tocar types/index.ts.
 * Refleja las columnas que inserta documents.api.ts al emitir.
 */
export interface DocumentItemRow {
  id: string
  document_id: string
  product_id: string | null
  descripcion: string
  cantidad: number
  valor_unitario: number
  precio_unitario: number
  igv: number
  total: number
}

/** Resultado de getDocumentDetail: comprobante + ítems + cliente (si aplica). */
export interface DocumentDetail {
  document: DocumentRow
  items: DocumentItemRow[]
  customer: Customer | null
}

/**
 * Trae el detalle completo de un comprobante:
 *  - el documento (`documents`) por id,
 *  - sus ítems (`document_items` where document_id = id),
 *  - el cliente (`customers`) si el documento tiene customer_id.
 * El aislamiento por empresa lo garantiza el RLS en la base de datos.
 */
export async function getDocumentDetail(id: string): Promise<DocumentDetail> {
  return cachedQuery(
    ['document-detail', id],
    ['documents', 'document_items', 'customers'],
    async () => {
      const { data: doc, error } = await supabase
        .from('documents')
        .select('*')
        .eq('id', id)
        .single()
      if (error) throw error
      const document = doc as DocumentRow

      const { data: items, error: itemsError } = await supabase
        .from('document_items')
        .select('*')
        .eq('document_id', id)
      if (itemsError) throw itemsError

      let customer: Customer | null = null
      if (document.customer_id) {
        const { data: cust, error: custError } = await supabase
          .from('customers')
          .select('*')
          .eq('id', document.customer_id)
          .maybeSingle()
        if (custError) throw custError
        customer = (cust as Customer | null) ?? null
      }

      return {
        document,
        items: (items ?? []) as DocumentItemRow[],
        customer,
      }
    },
  )
}
