import { supabase } from '@/lib/supabase'
import { cachedQuery, invalidateQueryCache } from '@/stores/queryCache'
import type { Customer } from '@/types'

export async function listCustomers(companyId: string): Promise<Customer[]> {
  return cachedQuery(['customers', companyId], ['customers', `company:${companyId}`], async () => {
    const { data, error } = await supabase
      .from('customers')
      .select('*')
      .eq('company_id', companyId)
      .order('denominacion')
    if (error) throw error
    return (data ?? []) as Customer[]
  })
}

export interface NewCustomer {
  denominacion: string
  tipo_doc?: string
  num_doc?: string | null
  direccion?: string | null
  email?: string | null
}

export async function createCustomer(companyId: string, input: NewCustomer): Promise<Customer> {
  const { data, error } = await supabase
    .from('customers')
    .insert({
      company_id: companyId,
      denominacion: input.denominacion,
      tipo_doc: input.tipo_doc ?? '1',
      num_doc: input.num_doc ?? null,
      direccion: input.direccion ?? null,
      email: input.email ?? null,
    })
    .select()
    .single()
  if (error) throw error
  invalidateQueryCache()
  return data as Customer
}

export async function updateCustomer(id: string, input: NewCustomer): Promise<Customer> {
  const { data, error } = await supabase
    .from('customers')
    .update({
      denominacion: input.denominacion,
      tipo_doc: input.tipo_doc ?? '1',
      num_doc: input.num_doc ?? null,
      direccion: input.direccion ?? null,
      email: input.email ?? null,
    })
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  invalidateQueryCache()
  return data as Customer
}

export async function deleteCustomer(id: string): Promise<void> {
  // .select() devuelve las filas borradas: si RLS lo bloquea (DELETE solo admin) viene vacío
  // y NO lanza error → lo tratamos como permiso denegado, no como un "éxito" falso.
  const { data, error } = await supabase.from('customers').delete().eq('id', id).select('id')
  if (error) throw error
  if (!data || data.length === 0)
    throw new Error('No se pudo eliminar el cliente (requiere permiso de administrador).')
  invalidateQueryCache()
}
