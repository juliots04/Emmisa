import { defineStore } from 'pinia'
import { reactive } from 'vue'

interface CacheEntry {
  data: unknown
  tags: string[]
  updatedAt: number
}

export interface CacheQueryOptions {
  /** Ignora el valor guardado y vuelve a ejecutar la consulta. */
  force?: boolean
  /** Tiempo de vigencia. Por defecto dura toda la sesión, hasta invalidarse. */
  maxAgeMs?: number
}

function stableStringify(value: unknown): string {
  if (value === undefined) return '"__undefined__"'
  if (value === null || typeof value !== 'object') return JSON.stringify(value)
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`
  const record = value as Record<string, unknown>
  return `{${Object.keys(record)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${stableStringify(record[key])}`)
    .join(',')}}`
}

/**
 * Caché global de lecturas remotas.
 *
 * No se persiste en localStorage: los datos empresariales desaparecen al cerrar
 * la sesión/pestaña y nunca quedan expuestos al siguiente usuario del equipo.
 */
export const useQueryCacheStore = defineStore('query-cache', () => {
  const entries = reactive(new Map<string, CacheEntry>())
  const pending = new Map<string, Promise<unknown>>()
  let generation = 0

  async function query<T>(
    keyParts: readonly unknown[],
    tags: readonly string[],
    loader: () => Promise<T>,
    options: CacheQueryOptions = {},
  ): Promise<T> {
    const key = stableStringify(keyParts)
    if (options.force) {
      generation += 1
      entries.delete(key)
      pending.delete(key)
    }
    const cached = entries.get(key)
    const maxAgeMs = options.maxAgeMs ?? Number.POSITIVE_INFINITY

    if (
      !options.force &&
      cached &&
      (maxAgeMs === Number.POSITIVE_INFINITY || Date.now() - cached.updatedAt <= maxAgeMs)
    ) {
      return cached.data as T
    }

    if (!options.force) {
      const inFlight = pending.get(key)
      if (inFlight) return inFlight as Promise<T>
    }

    const requestGeneration = generation
    const request = loader()
      .then((data) => {
        // Una mutación pudo invalidar mientras esta petición estaba en vuelo.
        // En ese caso se devuelve al caller actual, pero no se guarda como vigente.
        if (requestGeneration === generation) {
          entries.set(key, {
            data,
            tags: [...new Set(tags)],
            updatedAt: Date.now(),
          })
        }
        return data
      })
      .finally(() => {
        if (pending.get(key) === request) pending.delete(key)
      })

    pending.set(key, request)
    return request
  }

  /** Invalida solo los recursos relacionados; sin tags limpia todo. */
  function invalidate(...tags: string[]) {
    generation += 1
    pending.clear()
    if (tags.length === 0) {
      entries.clear()
      return
    }
    const wanted = new Set(tags)
    for (const [key, entry] of entries) {
      if (entry.tags.some((tag) => wanted.has(tag))) entries.delete(key)
    }
  }

  function clear() {
    invalidate()
  }

  return { entries, query, invalidate, clear }
})

export function cachedQuery<T>(
  keyParts: readonly unknown[],
  tags: readonly string[],
  loader: () => Promise<T>,
  options?: CacheQueryOptions,
): Promise<T> {
  return useQueryCacheStore().query(keyParts, tags, loader, options)
}

export function invalidateQueryCache(...tags: string[]) {
  useQueryCacheStore().invalidate(...tags)
}
