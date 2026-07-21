import { defineStore } from 'pinia'
import { ref } from 'vue'
import { supabase } from '@/lib/supabase'
import type { Company } from '@/types'

export const useCompanyStore = defineStore('company', () => {
  const companies = ref<Company[]>([])
  const current = ref<Company | null>(null)
  const loaded = ref(false)

  async function load() {
    const { data, error } = await supabase.from('companies').select('*').order('created_at')
    if (error) throw error
    companies.value = (data ?? []) as Company[]
    if (!current.value && companies.value.length > 0) current.value = companies.value[0]
    loaded.value = true
  }

  async function create(input: {
    ruc: string
    razon_social: string
    regimen?: string
    direccion?: string
    ubigeo?: string
  }): Promise<Company> {
    // Usamos la SESIÓN (no getUser) para asegurar que hay un token válido:
    // sin sesión, el insert falla con "violates row-level security policy".
    const {
      data: { session },
    } = await supabase.auth.getSession()
    if (!session) {
      throw new Error(
        'Tu sesión no es válida. Toca "Volver al login", cierra sesión y vuelve a entrar.',
      )
    }

    const { data, error } = await supabase
      .from('companies')
      .insert({
        owner_id: session.user.id,
        ruc: input.ruc,
        razon_social: input.razon_social,
        regimen: input.regimen ?? 'RER',
        direccion: input.direccion ?? null,
        ubigeo: input.ubigeo ?? null,
      })
      .select()
      .single()
    if (error) throw error

    const company = data as Company
    companies.value.push(company)
    current.value = company
    return company
  }

  function setCurrent(company: Company) {
    current.value = company
  }

  function reset() {
    companies.value = []
    current.value = null
    loaded.value = false
  }

  return { companies, current, loaded, load, create, setCurrent, reset }
})
