// PLE — Programa de Libros Electrónicos (SUNAT). Genera los archivos TXT de:
//   • Registro de Ventas e Ingresos  (Formato 14.1, libro 140100)
//   • Registro de Compras            (Formato 8.1,  libro 080100)
// Campos separados por '|'; cada registro termina en '|' + salto de línea (CRLF).
//
// IMPORTANTE: valida el resultado con el "Validador SUNAT PLE" (herramienta OFFLINE
// y gratuita) antes de presentarlo. Los indicadores del nombre de archivo y algunos
// campos opcionales pueden requerir ajuste según tu régimen; la estructura sigue las
// "Estructuras e información de los libros electrónicos" de SUNAT.
import type { DocumentRow } from '@/types'

export interface PleFile {
  filename: string
  content: string
}

export interface PurchasePle {
  fecha: string
  tipo_doc: string
  serie_numero: string | null
  total: number
  total_gravado: number
  total_igv: number
  moneda: string | null
  tipo_cambio: number | null
  proveedor_ruc: string | null
  proveedor_nombre: string | null
}

// 'YYYY-MM' → 'AAAAMM00' (periodo tributario que exige el PLE)
function periodoTag(periodo: string): string {
  const [y, m] = periodo.split('-')
  return `${y}${m}00`
}

// 'YYYY-MM-DD' → 'DD/MM/AAAA' (o '' si no hay fecha)
function fmtDate(iso?: string | null): string {
  if (!iso) return ''
  const [y, m, d] = iso.slice(0, 10).split('-')
  if (!y || !m || !d) return ''
  return `${d}/${m}/${y}`
}

// Monto con 2 decimales, punto decimal, sin separador de miles.
function num(n: number | null | undefined): string {
  return Number(n ?? 0).toFixed(2)
}

function tipoCambio(tc: number | null | undefined, moneda: string): string {
  const v = Number(tc ?? 0)
  if (v > 0) return v.toFixed(3)
  return moneda === 'USD' ? '0.000' : '1.000'
}

// Divide 'F001-123' en { serie: 'F001', numero: '123' }.
function splitSerieNumero(sn: string | null): { serie: string; numero: string } {
  const s = (sn ?? '').trim()
  const i = s.lastIndexOf('-')
  if (i < 0) return { serie: '', numero: s }
  return { serie: s.slice(0, i), numero: s.slice(i + 1) }
}

// Nomenclatura del archivo PLE:
// LE + RUC(11) + AAAA + MM + '00' + libro(6) + '00' + indOperación + indContenido + indMoneda + indSPC + '.txt'
function pleFilename(ruc: string, periodo: string, libro: string, hasData: boolean): string {
  const [y, m] = periodo.split('-')
  const contenido = hasData ? '1' : '0'
  return `LE${ruc}${y}${m}00${libro}00${'1'}${contenido}${'1'}${'1'}.txt`
}

function joinRecords(records: string[]): string {
  return records.length ? records.join('\r\n') + '\r\n' : ''
}

/**
 * Registro de Ventas e Ingresos (Formato 14.1).
 * Solo comprobantes ACEPTADOS por SUNAT. Las notas de crédito (07) se registran
 * con importes en NEGATIVO (convención SUNAT para netear el total de ventas).
 */
export function pleRegistroVentas(
  docs: DocumentRow[],
  periodo: string,
  ruc: string,
  referencias: DocumentRow[] = [],
): PleFile {
  const pt = periodoTag(periodo)
  // El Registro de Ventas debe contener TODOS los comprobantes emitidos de la serie
  // (sin saltos de correlativo). Los anulados van con Estado=3 (no se omiten); solo se
  // excluyen los 'rechazado' (nunca fueron aceptados y no consumen numeración válida).
  const validos = docs.filter((d) => d.estado_sunat !== 'rechazado')
  // Mapa id → datos, para resolver el documento de referencia de NC/ND. Incluye los
  // docs del periodo Y las `referencias` externas (comprobantes de OTRO periodo que
  // una NC/ND rectifica), para no dejar vacíos los campos 28-31 (doc modificado).
  const refMap = new Map(
    [...docs, ...referencias].map((d) => [
      d.id,
      { fecha: d.fecha_emision ?? d.created_at, tipo: d.tipo_doc, serie: d.serie, correlativo: d.correlativo },
    ]),
  )

  const records = validos.map((d, i) => {
    const sign = d.tipo_doc === '07' ? -1 : 1
    const s = (v: number | null | undefined) => num(sign * Number(v ?? 0))
    const ref = d.ref_document_id ? refMap.get(d.ref_document_id) : undefined
    // Estado (campo 35): 1 = anotación oportuna (emitido/aceptado/pendiente); 3 = anulado (baja).
    const estado = d.estado_sunat === 'anulado' || d.estado_sunat === 'baja_pendiente' ? '3' : '1'
    const f = [
      pt,                                        // 1  Periodo
      `M${String(i + 1).padStart(8, '0')}`,      // 2  Código único de la operación (CUO)
      String(i + 1),                             // 3  Número correlativo del asiento
      fmtDate(d.fecha_emision ?? d.created_at),   // 4  Fecha de emisión
      fmtDate(d.fecha_vencimiento),              // 5  Fecha de vencimiento/pago
      d.tipo_doc,                                // 6  Tipo de comprobante (Tabla 10)
      d.serie,                                   // 7  Serie del comprobante
      String(d.correlativo),                     // 8  Número del comprobante
      '',                                        // 9  Número final (resumen de boletas)
      d.receptor_tipo_doc || '0',                // 10 Tipo doc del cliente (Tabla 2)
      d.receptor_num_doc || '0',                 // 11 Número doc del cliente
      d.receptor_denominacion || 'Cliente varios', // 12 Razón social del cliente
      s(d.total_exportacion),                    // 13 Valor facturado de exportación
      s(d.total_gravado),                        // 14 Base imponible gravada
      '0.00',                                    // 15 Descuento de la base imponible
      s(d.total_igv),                            // 16 IGV / IPM
      '0.00',                                    // 17 Descuento del IGV
      s(d.total_exonerado),                      // 18 Importe exonerado
      s(d.total_inafecto),                       // 19 Importe inafecto
      s(d.total_isc),                            // 20 ISC
      '0.00',                                    // 21 Base imponible IVAP
      '0.00',                                    // 22 IVAP
      s(d.total_icbper),                         // 23 ICBPER
      '0.00',                                    // 24 Otros tributos y cargos
      s(d.total),                                // 25 Importe total
      d.moneda || 'PEN',                         // 26 Código de moneda (Tabla 4)
      tipoCambio(d.tipo_cambio, d.moneda || 'PEN'), // 27 Tipo de cambio
      ref ? fmtDate(ref.fecha) : '',             // 28 Fecha del documento modificado
      ref ? ref.tipo : '',                       // 29 Tipo del documento modificado
      ref ? ref.serie : '',                      // 30 Serie del documento modificado
      ref ? String(ref.correlativo) : '',        // 31 Número del documento modificado
      '',                                        // 32 Identificación del contrato/proyecto
      '',                                        // 33 Error tipo 1 (inconsistencia TC)
      '',                                        // 34 Indicador de comprobante cancelado con medio de pago
      estado,                                    // 35 Estado (1 = anotación oportuna · 3 = anulado)
    ]
    return f.join('|') + '|'
  })

  return { filename: pleFilename(ruc, periodo, '140100', records.length > 0), content: joinRecords(records) }
}

/**
 * Registro de Compras (Formato 8.1). Trata la adquisición como gravada destinada a
 * operaciones gravadas (así la registra `registrar_compra`). El importe no gravado
 * (col. 19) sale de la diferencia con base + IGV.
 */
export function pleRegistroCompras(compras: PurchasePle[], periodo: string, ruc: string): PleFile {
  const pt = periodoTag(periodo)
  const records = compras.map((c, i) => {
    const { serie, numero } = splitSerieNumero(c.serie_numero)
    const noGravado = Math.max(0, Number(c.total) - Number(c.total_gravado) - Number(c.total_igv))
    const tipoDocProv = c.proveedor_ruc ? '6' : '0'
    const f = [
      pt,                                    // 1  Periodo
      `M${String(i + 1).padStart(8, '0')}`,  // 2  CUO
      String(i + 1),                         // 3  Número correlativo del asiento
      fmtDate(c.fecha),                      // 4  Fecha de emisión del comprobante
      '',                                    // 5  Fecha de vencimiento / pago
      c.tipo_doc || '01',                    // 6  Tipo de comprobante (Tabla 10)
      serie,                                 // 7  Serie del comprobante
      '',                                    // 8  Año de emisión de la DUA/DSI
      numero,                                // 9  Número del comprobante
      tipoDocProv,                           // 10 Tipo doc del proveedor (Tabla 2)
      c.proveedor_ruc || '0',                // 11 Número doc del proveedor
      c.proveedor_nombre || 'Proveedor',     // 12 Razón social del proveedor
      num(c.total_gravado),                  // 13 Base imponible (grav. → oper. gravadas)
      num(c.total_igv),                      // 14 IGV de la col. 13
      '0.00',                                // 15 Base imp. (grav. → gravadas y no gravadas)
      '0.00',                                // 16 IGV de la col. 15
      '0.00',                                // 17 Base imp. (grav. → no gravadas)
      '0.00',                                // 18 IGV de la col. 17
      num(noGravado),                        // 19 Valor de adquisiciones no gravadas
      '0.00',                                // 20 ISC
      '0.00',                                // 21 ICBPER
      '0.00',                                // 22 Otros tributos y cargos
      num(c.total),                          // 23 Importe total
      c.moneda || 'PEN',                     // 24 Código de moneda (Tabla 4)
      tipoCambio(c.tipo_cambio, c.moneda || 'PEN'), // 25 Tipo de cambio
      '',                                    // 26 Fecha emisión del doc. modificado
      '',                                    // 27 Tipo del doc. modificado
      '',                                    // 28 Serie del doc. modificado
      '',                                    // 29 Número del doc. modificado
      '',                                    // 30 N° de constancia de depósito de detracción
      '',                                    // 31 Fecha de la constancia de detracción
      '',                                    // 32 Marca del comprobante sujeto a retención
      '',                                    // 33 Clasificación de bienes y servicios
      '',                                    // 34 Identificación del contrato/proyecto
      '',                                    // 35 Error tipo 1
      '1',                                   // 36 Estado (1 = anotación oportuna)
    ]
    return f.join('|') + '|'
  })

  return { filename: pleFilename(ruc, periodo, '080100', records.length > 0), content: joinRecords(records) }
}

/** Descarga el archivo PLE como .txt. */
export function descargarPle(file: PleFile): void {
  // SUNAT espera el PLE en ANSI/Windows-1252 (Latin-1), NO UTF-8. Así ñ/tildes
  // (todas ≤ 255 en Latin-1) se escriben como UN byte y no como multibyte UTF-8,
  // que el validador de SUNAT corrompe.
  const bytes = Uint8Array.from(file.content, (ch) => ch.charCodeAt(0) & 0xff)
  const blob = new Blob([bytes], { type: 'text/plain' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = file.filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  URL.revokeObjectURL(url)
}
