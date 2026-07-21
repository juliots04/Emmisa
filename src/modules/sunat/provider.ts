// Contrato del "motor" de facturación (SUNAT).
// Cualquier proveedor (Mock, APISUNAT, Nubefact, Greenter...) implementa esta interfaz.
// Así se cambia de proveedor sin tocar el resto de la app.

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
  estado: 'aceptado' | 'rechazado' | 'pendiente'
  cdr?: string
  xmlUrl?: string
  pdfUrl?: string
  mensaje?: string
}

export interface EmisorProvider {
  emitir(input: EmitInput): Promise<EmitResult>
}
