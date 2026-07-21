import type { EmisorProvider, EmitInput, EmitResult } from './provider'

// Proveedor SIMULADO: permite emitir sin conexión real a SUNAT.
// Úsalo para desarrollar toda la app; luego lo cambias por el proveedor real
// (APISUNAT / Nubefact) en modules/sunat/index.ts sin tocar nada más.
export class MockProvider implements EmisorProvider {
  async emitir(input: EmitInput): Promise<EmitResult> {
    await new Promise((resolve) => setTimeout(resolve, 600)) // simula latencia
    const numero = `${input.serie}-${String(input.correlativo).padStart(8, '0')}`
    return {
      estado: 'aceptado',
      cdr: `MOCK-CDR-${numero}`,
      pdfUrl: `#/mock-pdf/${numero}`,
      mensaje: `Comprobante ${numero} aceptado (SIMULADO)`,
    }
  }
}
