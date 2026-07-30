// Tipos compartidos del flujo de facturación.

export interface EmitCliente {
  tipoDoc: string // 1 = DNI, 6 = RUC
  numDoc?: string
  denominacion: string
}

export interface EmitItem {
  descripcion: string
  cantidad: number
  precioUnitario: number
}

export interface EmitInput {
  tipoDoc: string // 01 factura, 03 boleta
  serie: string
  correlativo: number
  cliente: EmitCliente
  items: EmitItem[]
}

export interface EmitResult {
  estado: 'aceptado' | 'rechazado' | 'pendiente' | 'anulado'
  cdr?: string
  xmlUrl?: string
  pdfUrl?: string
  hash?: string
  ticket?: string
  /** Siempre false en el flujo real; se conserva por compatibilidad de interfaz. */
  simulado?: boolean
  mensaje?: string
}

export interface EmisorProvider {
  emitir(input: EmitInput): Promise<EmitResult>
}
