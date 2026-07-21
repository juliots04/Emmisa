import { SimuladoProvider } from './mock'
import type { EmisorProvider } from './provider'

export * from './provider'
export * from './tax'
export * from './mock'

// 🔌 Punto único para cambiar de proveedor.
// Hoy: Simulado (sin conexión). Mañana: new ApisunatProvider(env...) / new NubefactProvider(...).
export const emisor: EmisorProvider = new SimuladoProvider()
