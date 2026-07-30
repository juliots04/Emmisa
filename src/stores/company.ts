import { defineStore } from 'pinia'
import { ref } from 'vue'
import { supabase } from '@/lib/supabase'
import type { Company } from '@/types'

export const useCompanyStore = defineStore('company', () => {
  const companies = ref<Company[]>([])
  const current = ref<Company | null>(null)
  const loaded = ref(false)

  const STORAGE_KEY = 'konversa.current_company'

  async function load(force = false) {
    if (loaded.value && !force) return
    const { data, error } = await supabase.from('companies').select('*').order('created_at')
    if (error) throw error
    companies.value = (data ?? []) as Company[]
    if (companies.value.length > 0) {
      if (current.value) {
        // Ya hay una empresa activa: re-apúntala a la versión fresca (logo, datos…).
        // Si la empresa activa ya no está (eliminada / acceso revocado), cae a la
        // primera disponible en vez de conservar una referencia colgante.
        current.value =
          companies.value.find((c) => c.id === current.value!.id) ?? companies.value[0]
      } else {
        const savedId = localStorage.getItem(STORAGE_KEY)
        current.value = companies.value.find((c) => c.id === savedId) ?? companies.value[0]
      }
    }
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
    // Persistir como empresa activa (igual que setCurrent) para que al recargar
    // no se pierda la recién creada si ya hay otras empresas.
    try {
      localStorage.setItem(STORAGE_KEY, company.id)
    } catch {
      /* almacenamiento no disponible: no es crítico */
    }
    return company
  }

  function setCurrent(company: Company) {
    current.value = company
    try {
      localStorage.setItem(STORAGE_KEY, company.id)
    } catch {
      /* almacenamiento no disponible (modo privado/cuota): no es crítico */
    }
  }

  function reset() {
    companies.value = []
    current.value = null
    loaded.value = false
    localStorage.removeItem(STORAGE_KEY)
  }

  return { companies, current, loaded, load, create, setCurrent, reset }
})
