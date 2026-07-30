import { computed, ref, watch, type Ref } from 'vue'
import { listSeries, type Serie } from '@/modules/settings/settings.api'

/** Serie por defecto por tipo de comprobante si la empresa aún no configuró ninguna. */
const SERIE_DEFAULT: Record<string, string> = {
  '01': 'F001', // Factura
  '03': 'B001', // Boleta
  '07': 'FC01', // Nota de crédito
  '08': 'FD01', // Nota de débito
}

function lsGet(key: string): string | null {
  try {
    return typeof localStorage !== 'undefined' ? localStorage.getItem(key) : null
  } catch {
    return null
  }
}
function lsSet(key: string, value: string): void {
  try {
    if (typeof localStorage !== 'undefined') localStorage.setItem(key, value)
  } catch {
    /* almacenamiento no disponible: no es crítico */
  }
}

/**
 * Maneja la serie del comprobante para una pantalla de emisión (Emitir / POS).
 * - Carga las series configuradas de la empresa (Ajustes → Series).
 * - Filtra por el tipo de comprobante activo.
 * - Recuerda la última serie elegida POR DISPOSITIVO y tipo. Útil para multi-caja:
 *   cada terminal se queda con su serie y no chocan los correlativos.
 */
export function useSeries(companyId: Ref<string | undefined>, tipoDoc: Ref<string>) {
  const series = ref<Serie[]>([])
  const serie = ref<string>('')

  const serieOptions = computed<string[]>(() => {
    const list = series.value.filter((s) => s.tipo_doc === tipoDoc.value).map((s) => s.serie)
    if (list.length) return list
    const def = SERIE_DEFAULT[tipoDoc.value]
    return def ? [def] : []
  })

  function key(): string {
    return `emmisa-serie:${companyId.value ?? '_'}:${tipoDoc.value}`
  }

  function pickForTipo(): void {
    const opts = serieOptions.value
    const remembered = lsGet(key())
    serie.value =
      remembered && opts.includes(remembered)
        ? remembered
        : opts[0] ?? SERIE_DEFAULT[tipoDoc.value] ?? ''
  }

  async function loadSeries(): Promise<void> {
    if (companyId.value) {
      try {
        series.value = await listSeries(companyId.value)
      } catch {
        series.value = []
      }
    }
    pickForTipo()
  }

  // Al cambiar el tipo de comprobante, ajusta a la serie recordada/primera de ese tipo.
  watch(tipoDoc, pickForTipo)
  // Al elegir una serie, recuérdala en este dispositivo para ese tipo.
  watch(serie, (v) => {
    if (v) lsSet(key(), v)
  })

  return { series, serie, serieOptions, loadSeries }
}
