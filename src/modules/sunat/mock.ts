// Proveedor SIMULADO de alta fidelidad: emula el flujo real de SUNAT
// (estado, CDR, hash, ticket) SIN conexión ni credenciales. Ideal para
// desarrollar y demostrar toda la app "por mientras".
//
// Escenarios de prueba (según el nº de documento del CLIENTE, al estilo de las
// tarjetas de prueba de Stripe):
//   • termina en "99"  -> RECHAZADO (con código de error SUNAT simulado)
//   • termina en "88"  -> PENDIENTE (genera ticket; al reintentar pasa a aceptado)
//   • cualquier otro   -> ACEPTADO
import type { EmisorProvider, EmitInput, EmitResult } from './provider'

const TIPO_NOMBRE: Record<string, string> = {
  '01': 'Factura',
  '03': 'Boleta',
  '07': 'Nota de Crédito',
  '08': 'Nota de Débito',
}

const ERRORES_SUNAT = [
  '2335|El comprobante fue rechazado: el RUC del receptor no existe o no está activo.',
  '3105|El comprobante fue rechazado: el importe total no coincide con la sumatoria de los ítems.',
  '1033|El comprobante fue informado anteriormente a la SUNAT (documento duplicado).',
]

export type EstadoSimulado = 'aceptado' | 'rechazado' | 'pendiente'

/** Elige el escenario de prueba según el nº de documento del cliente. */
export function escenarioSimulado(numDoc?: string | null): EstadoSimulado {
  const n = (numDoc ?? '').trim()
  if (n.endsWith('99')) return 'rechazado'
  if (n.endsWith('88')) return 'pendiente'
  return 'aceptado'
}

/** Hash base64 pseudo-real, estable por comprobante (NO criptográfico; solo simula). */
function hashSimulado(seed: string): string {
  const b64 = typeof btoa === 'function' ? btoa(unescape(encodeURIComponent(seed))) : seed
  return (b64 + 'K9d2fAqZ7xR').replace(/=+$/g, '').slice(0, 27) + '='
}

export interface SimInput {
  tipoDoc: string
  serie: string
  correlativo: number
  numDoc?: string | null
  total?: number
  ruc?: string
}

export interface SimResult {
  estado: EstadoSimulado
  cdr?: string
  hash?: string
  ticket?: string
  mensaje: string
  simulado: true
}

/** Simula la respuesta del PSE/SUNAT para un comprobante ya armado. */
export function simular(input: SimInput, opts?: { resolverPendiente?: boolean }): SimResult {
  const numero = `${input.serie}-${String(input.correlativo).padStart(8, '0')}`
  const nombre = TIPO_NOMBRE[input.tipoDoc] ?? 'Comprobante'
  const ticket = `SIM-${(input.serie || '').replace(/\W/g, '')}-${String(input.correlativo).padStart(8, '0')}`
  const hash = hashSimulado(`${input.ruc ?? ''}|${numero}|${input.total ?? ''}`)

  let estado = escenarioSimulado(input.numDoc)
  if (estado === 'pendiente' && opts?.resolverPendiente) estado = 'aceptado' // reintento -> SUNAT ya "terminó"

  if (estado === 'rechazado') {
    const [code, msg] = ERRORES_SUNAT[Math.abs(input.correlativo) % ERRORES_SUNAT.length].split('|')
    return { estado, hash, ticket, mensaje: `Error ${code}: ${msg}`, simulado: true }
  }
  if (estado === 'pendiente') {
    return {
      estado,
      ticket,
      mensaje: `${nombre} ${numero} EN PROCESO (ticket ${ticket}). Reintenta para consultar el estado.`,
      simulado: true,
    }
  }
  return {
    estado,
    hash,
    ticket,
    cdr: `La ${nombre} numero ${numero}, ha sido aceptada`,
    mensaje: `${nombre} ${numero} aceptada por SUNAT (SIMULADO)`,
    simulado: true,
  }
}

/** Implementación del contrato EmisorProvider usando la simulación. */
export class SimuladoProvider implements EmisorProvider {
  async emitir(input: EmitInput): Promise<EmitResult> {
    // Latencia realista (0.5–1.1 s) para ver spinners y estados en la UI.
    await new Promise((r) => setTimeout(r, 500 + (Math.abs(input.correlativo) % 6) * 100))
    return {
      ...simular({
        tipoDoc: input.tipoDoc,
        serie: input.serie,
        correlativo: input.correlativo,
        numDoc: input.cliente?.numDoc,
      }),
    }
  }
}

/** Alias de compatibilidad con el nombre anterior. */
export { SimuladoProvider as MockProvider }
