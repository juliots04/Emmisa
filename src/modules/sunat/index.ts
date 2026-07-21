import { MockProvider } from './mock'
import type { EmisorProvider } from './provider'

export * from './provider'
export * from './tax'

// 🔌 Punto único para cambiar de proveedor.
// Hoy: Mock (sin conexión). Mañana: new ApisunatProvider(env...) / new NubefactProvider(...).
export const emisor: EmisorProvider = new MockProvider()
