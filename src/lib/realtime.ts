import { onBeforeUnmount, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import type { RealtimeChannel } from '@supabase/supabase-js'
import { invalidateQueryCache } from '@/stores/queryCache'

/**
 * Suscribe una vista a los cambios en tiempo real de una tabla (Supabase Realtime),
 * filtrados por la empresa activa. Cuando llega cualquier INSERT/UPDATE/DELETE de esa
 * empresa, llama a `onChange` (con debounce, para no recargar N veces en ráfaga).
 *
 * Requiere que la tabla esté en la publicación `supabase_realtime` (migración 0023)
 * y que tenga columna `company_id` (por eso stock/cash_movements se cubren vía
 * inventory_movements y documents, que sí la tienen).
 * Se limpia solo al desmontar el componente (sin fugas de canales).
 *
 * @example
 *   useRealtime('documents', () => company.current?.id, () => { void load() })
 */
export function useRealtime(
  table: string,
  companyId: () => string | undefined,
  onChange: () => void,
  debounceMs = 500,
): { unsubscribe: () => void } {
  let channel: RealtimeChannel | null = null
  let timer: ReturnType<typeof setTimeout> | null = null

  const trigger = () => {
    if (timer) clearTimeout(timer)
    timer = setTimeout(() => {
      invalidateQueryCache()
      onChange()
    }, debounceMs)
  }

  const subscribe = () => {
    const cid = companyId()
    if (!cid || channel) return
    channel = supabase
      .channel(`rt-${table}-${cid}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table, filter: `company_id=eq.${cid}` },
        trigger,
      )
      .subscribe()
  }

  const unsubscribe = () => {
    if (timer) {
      clearTimeout(timer)
      timer = null
    }
    if (channel) {
      void supabase.removeChannel(channel)
      channel = null
    }
  }

  onMounted(subscribe)
  onBeforeUnmount(unsubscribe)
  return { unsubscribe }
}
