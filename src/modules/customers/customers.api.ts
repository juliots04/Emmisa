import { supabase } from '@/lib/supabase'
import type { Customer } from '@/types'

export async function listCustomers(companyId: string): Promise<Customer[]> {
  const { data, error } = await supabase
    .from('customers')
    .select('*')
    .eq('company_id', companyId)
    .order('denominacion')
  if (error) throw error
  return (data ?? []) as Customer[]
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
  return data as Customer
}
