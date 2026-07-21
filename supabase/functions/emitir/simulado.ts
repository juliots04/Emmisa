// Simulación de alta fidelidad para la Edge Function `emitir`.
// Se usa cuando la empresa NO tiene credenciales de PSE configuradas, para que
// el flujo completo funcione en desarrollo/demos sin conexión real a SUNAT.
//
// Escenarios (según el nº de doc del receptor): termina en "99" -> rechazado,
// "88" -> pendiente, cualquier otro -> aceptado.
import type { DocData, EmitOutcome } from './apisunat.ts'

const TIPO: Record<string, string> = { '01': 'Factura', '03': 'Boleta', '07': 'Nota de Crédito', '08': 'Nota de Débito' }
const ERRORES = [
  '2335|El comprobante fue rechazado: el RUC del receptor no existe o no está activo.',
  '3105|El comprobante fue rechazado: el importe total no coincide con la sumatoria de los ítems.',
  '1033|El comprobante fue informado anteriormente a la SUNAT (documento duplicado).',
]

function escenario(numDoc?: string): 'aceptado' | 'rechazado' | 'pendiente' {
  const n = (numDoc ?? '').trim()
  if (n.endsWith('99')) return 'rechazado'
  if (n.endsWith('88')) return 'pendiente'
  return 'aceptado'
}

function hashSim(seed: string): string {
  return (btoa(seed) + 'K9d2fAqZ7xR').replace(/=+$/g, '').slice(0, 27) + '='
}

/** Simula la respuesta del PSE/SUNAT. resolverPendiente=true (reintento) => aceptado. */
export function emitirSimulado(d: DocData, resolverPendiente = false): EmitOutcome {
  const numero = `${d.serie}-${String(d.correlativo).padStart(8, '0')}`
  const nombre = TIPO[d.tipoDoc] ?? 'Comprobante'
  const ticket = `SIM-${d.serie}-${String(d.correlativo).padStart(8, '0')}`
  const hash = hashSim(`${d.serie}|${d.correlativo}|${d.total}`)

  let est = escenario(d.receptorNumDoc)
  if (est === 'pendiente' && resolverPendiente) est = 'aceptado'

  if (est === 'rechazado') {
    const [c, m] = ERRORES[Math.abs(d.correlativo) % ERRORES.length].split('|')
    return { estado: 'rechazado', hash, ticket, mensaje: `Error ${c}: ${m} (SIMULADO)` }
  }
  if (est === 'pendiente') {
    return { estado: 'pendiente', ticket, mensaje: `${nombre} ${numero} en proceso (SIMULADO)` }
  }
  return { estado: 'aceptado', hash, ticket, cdr: `La ${nombre} numero ${numero}, ha sido aceptada`, mensaje: 'Aceptado (SIMULADO)' }
}
