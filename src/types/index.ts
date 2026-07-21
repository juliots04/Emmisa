// Tipos del dominio (reflejan el esquema de la base de datos).

export type Regimen = 'RER' | 'RMT' | 'GENERAL' | 'NRUS'
export type TipoDoc = '01' | '03' // 01 = Factura, 03 = Boleta
export type EstadoSunat = 'pendiente' | 'aceptado' | 'rechazado' | 'anulado'

export interface Company {
  id: string
  owner_id: string
  ruc: string
  razon_social: string
  regimen: Regimen
  direccion: string | null
  estado: string
  created_at: string
}

export interface Product {
  id: string
  company_id: string
  sku: string | null
  nombre: string
  nombre_secundario: string | null
  descripcion: string | null
  modelo: string | null
  barcode: string | null
  tipo: 'bien' | 'servicio'
  unidad_medida: string
  tipo_afectacion: string
  moneda: string
  precio: number
  costo: number
  incluye_igv: boolean
  stock_minimo: number
  controla_stock: boolean
  activo: boolean
  codigo_sunat: string | null
  linea_producto: string | null
  registro_sanitario: string | null
  codigo_digemid: string | null
  codigo_fabrica: string | null
}

export interface Customer {
  id: string
  company_id: string
  tipo_doc: string // 1 = DNI, 6 = RUC
  num_doc: string | null
  denominacion: string
  direccion: string | null
  email: string | null
}

export interface DocumentRow {
  id: string
  company_id: string
  customer_id: string | null
  tipo_doc: string // 01 factura, 03 boleta, 07 NC, 08 ND
  serie: string
  correlativo: number
  moneda: string
  total_gravado: number
  total_igv: number
  total: number
  estado_sunat: EstadoSunat
  cdr: string | null
  pdf_url: string | null
  created_at: string
  // Venta transaccional (0009)
  user_id?: string | null
  cash_session_id?: string | null
  forma_pago?: string | null
  monto_recibido?: number | null
  vuelto?: number | null
  // Cumplimiento SUNAT ampliado (0011+)
  establishment_id?: string | null
  tipo_cambio?: number
  total_exonerado?: number
  total_inafecto?: number
  total_gratuito?: number
  fecha_emision?: string
  fecha_vencimiento?: string | null
  hash?: string | null
  codigo_qr?: string | null
  xml_url?: string | null
  sunat_ticket?: string | null
  sunat_error?: string | null
  receptor_tipo_doc?: string | null
  receptor_num_doc?: string | null
  receptor_denominacion?: string | null
  receptor_direccion?: string | null
  condicion_pago?: string
  estado_pago?: 'pagado' | 'pendiente' | 'parcial'
  saldo?: number
  ref_document_id?: string | null
  motivo_codigo?: string | null
  motivo_desc?: string | null
}
