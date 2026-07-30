import { defineStore } from 'pinia'
import { ref } from 'vue'
import { supabase } from '@/lib/supabase'

// Tipo de cambio USD→PEN, GLOBAL para toda la app.
// Fuente 1 (confiable): SUNAT vía Edge Function `tipo-cambio` (apis.net.pe no da CORS).
// Fuente 2 (respaldo, CORS directo): mercado (open.er-api.com).
// Fuente 3: último valor conocido / default.
const DEFAULT = 3.75

export type OrigenTC = 'SUNAT' | 'mercado' | 'defecto'

export const useTipoCambioStore = defineStore('tipoCambio', () => {
  const venta = ref(DEFAULT) // el que se usa para emitir (venta SBS/SUNAT)
  const compra = ref(DEFAULT)
  const fecha = ref<string | null>(null)
  const origen = ref<OrigenTC>('defecto')
  const loading = ref(false)
  const cargado = ref(false)

  // 1) SUNAT vía Edge Function (server-side, sin problemas de CORS).
  async function desdeSunat(): Promise<boolean> {
    try {
      const { data, error } = await supabase.functions.invoke('tipo-cambio')
      const v = Number((data as { venta?: number } | null)?.venta)
      if (error || !v || Number.isNaN(v)) return false
      const d = data as { venta: number; compra?: number; fecha?: string | null }
      venta.value = v
      compra.value = Number(d.compra ?? v)
      fecha.value = d.fecha ?? null
      origen.value = 'SUNAT'
      return true
    } catch {
      return false
    }
  }

  // 2) Respaldo: tipo de cambio de mercado (CORS abierto desde el navegador).
  async function desdeMercado(): Promise<boolean> {
    try {
      const res = await fetch('https://open.er-api.com/v6/latest/USD')
      if (!res.ok) return false
      const data = await res.json()
      const pen = Number(data?.rates?.PEN)
      if (!pen || Number.isNaN(pen)) return false
      venta.value = pen
      compra.value = pen
      fecha.value = data?.time_last_update_utc
        ? new Date(data.time_last_update_utc).toISOString().slice(0, 10)
        : null
      origen.value = 'mercado'
      return true
    } catch {
      return false
    }
  }

  async function refresh(): Promise<void> {
    if (loading.value) return
    loading.value = true
    try {
      const ok = (await desdeSunat()) || (await desdeMercado())
      if (ok) cargado.value = true
    } finally {
      loading.value = false
    }
  }

  // Carga perezosa: solo la primera vez que alguien lo necesita.
  function ensure(): void {
    if (!cargado.value && !loading.value) void refresh()
  }

  return { venta, compra, fecha, origen, loading, cargado, refresh, ensure }
})
