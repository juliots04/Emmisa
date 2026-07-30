// Utilidades de fecha en HORA LOCAL (Perú UTC-5), no UTC.
// Motivo: new Date().toISOString().slice(0,10) y new Date('YYYY-MM-DD') usan UTC,
// así que de noche (>= ~19:00 en Perú) devuelven/renderizan el día equivocado.

/** Fecha de HOY en formato 'YYYY-MM-DD' según la hora local (no UTC). */
export function todayLocal(): string {
  const d = new Date()
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

/**
 * Parsea un valor de fecha a Date LOCAL. Si viene como 'YYYY-MM-DD' (columna date
 * de Postgres), lo interpreta como medianoche LOCAL (evita el desfase de un día
 * que produce new Date('YYYY-MM-DD'), que asume UTC).
 */
export function parseLocal(v: string): Date {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v)
  if (m) return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
  return new Date(v)
}

/** '21 jul 2026' (fecha corta es-PE, sin desfase). */
export function fmtFecha(v: string): string {
  return parseLocal(v).toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' })
}

/** '21 de julio de 2026, 8:56 p. m.' (fecha + hora larga, siempre en hora de Perú). */
export function fmtFechaHora(v: string): string {
  return new Date(v).toLocaleString('es-PE', {
    dateStyle: 'long',
    timeStyle: 'short',
    timeZone: 'America/Lima',
  })
}

/** '8:56 p. m.' (solo hora, siempre en hora de Perú, no la del navegador). */
export function fmtHora(v: string): string {
  return new Date(v).toLocaleTimeString('es-PE', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'America/Lima',
  })
}
