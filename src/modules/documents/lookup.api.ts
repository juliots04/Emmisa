import { supabase } from '@/lib/supabase'

export interface DocLookupResult {
  denominacion: string
  direccion?: string
}

/**
 * Consulta RUC/DNI vía Edge Function `lookup` (mantiene el token del proveedor en
 * el servidor, nunca en el navegador). Degrada con gracia: si la función no está
 * desplegada o no hay token configurado, devuelve `null` y el usuario escribe el
 * nombre a mano.
 */
export async function lookupDoc(tipo: 'ruc' | 'dni', numero: string): Promise<DocLookupResult | null> {
  const num = (numero ?? '').replace(/\D/g, '')
  if ((tipo === 'ruc' && num.length !== 11) || (tipo === 'dni' && num.length !== 8)) return null
  try {
    const { data, error } = await supabase.functions.invoke('lookup', { body: { tipo, numero: num } })
    if (error) return null
    const r = data as { ok?: boolean; denominacion?: string; direccion?: string }
    if (!r || r.ok === false || !r.denominacion) return null
    return { denominacion: r.denominacion, direccion: r.direccion }
  } catch {
    return null
  }
}
