// Adaptador APISUNAT (PSE/OSE certificado).
// Construye el documento en el formato JSON de APISUNAT y lo envía.
// Doc oficial: https://apisunat.com/  (endpoint back.apisunat.com/personas/v1/sendBill)
//
// NOTA: el mapeo de campos cubre el caso común (factura/boleta con IGV,
// exonerado e inafecto). Valídalo contra tu cuenta APISUNAT (modo beta) antes
// de producción: cada emisor puede requerir catálogos/leyendas adicionales.

export interface Emisor {
  ruc: string
  razon_social: string
  direccion?: string | null
  ubigeo?: string | null
}

export interface DocItem {
  descripcion: string
  cantidad: number
  valor_unitario: number // sin IGV
  precio_unitario: number // con IGV
  igv: number
  total: number
  tipo_afectacion: string // 10 grav, 20 exon, 30 inaf
  unidad_medida: string
  codigo_producto?: string | null
}

export interface DocData {
  tipoDoc: string // 01 factura, 03 boleta, 07 NC, 08 ND
  serie: string
  correlativo: number
  fechaEmision: string // YYYY-MM-DD
  moneda: string
  receptorTipoDoc: string // 6 RUC, 1 DNI, 0/- varios
  receptorNumDoc: string
  receptorDenominacion: string
  receptorDireccion?: string | null
  totalGravado: number
  totalExonerado: number
  totalInafecto: number
  totalIgv: number
  total: number
  items: DocItem[]
  refTipoDoc?: string | null // para notas
  refNumero?: string | null
  motivoCodigo?: string | null
  motivoDesc?: string | null
}

export interface Credentials {
  url: string
  personaId: string
  token: string
}

export interface EmitOutcome {
  estado: 'aceptado' | 'rechazado' | 'pendiente'
  cdr?: string
  xmlUrl?: string
  pdfUrl?: string
  hash?: string
  ticket?: string
  mensaje?: string
  raw?: unknown
}

const T = (v: string | number) => ({ _text: String(v) })

function tipoAfectacionUBL(t: string): { igvCode: string; taxCode: string; taxName: string; percent: number } {
  // Catálogo 07 (afectación IGV) → catálogo 05 (tributo)
  if (t === '20') return { igvCode: '20', taxCode: '9997', taxName: 'EXO', percent: 0 } // Exonerado
  if (t === '30') return { igvCode: '30', taxCode: '9998', taxName: 'INA', percent: 0 } // Inafecto
  return { igvCode: '10', taxCode: '1000', taxName: 'IGV', percent: 18 } // Gravado
}

function buildLines(d: DocData) {
  return d.items.map((it, i) => {
    const af = tipoAfectacionUBL(it.tipo_afectacion)
    const valorVenta = round2(it.valor_unitario * it.cantidad)
    return {
      'cbc:ID': T(i + 1),
      'cbc:InvoicedQuantity': { _attributes: { unitCode: it.unidad_medida || 'NIU' }, _text: String(it.cantidad) },
      'cbc:LineExtensionAmount': { _attributes: { currencyID: d.moneda }, _text: String(valorVenta) },
      'cac:PricingReference': {
        'cac:AlternativeConditionPrice': {
          'cbc:PriceAmount': { _attributes: { currencyID: d.moneda }, _text: String(round2(it.precio_unitario)) },
          'cbc:PriceTypeCode': T('01'),
        },
      },
      'cac:TaxTotal': {
        'cbc:TaxAmount': { _attributes: { currencyID: d.moneda }, _text: String(round2(it.igv)) },
        'cac:TaxSubtotal': {
          'cbc:TaxableAmount': { _attributes: { currencyID: d.moneda }, _text: String(valorVenta) },
          'cbc:TaxAmount': { _attributes: { currencyID: d.moneda }, _text: String(round2(it.igv)) },
          'cac:TaxCategory': {
            'cbc:Percent': T(af.percent),
            'cbc:TaxExemptionReasonCode': T(af.igvCode),
            'cac:TaxScheme': {
              'cbc:ID': T(af.taxCode),
              'cbc:Name': T(af.taxName),
              'cbc:TaxTypeCode': T(af.taxName === 'IGV' ? 'VAT' : 'FRE'),
            },
          },
        },
      },
      'cac:Item': {
        'cbc:Description': T(it.descripcion),
        ...(it.codigo_producto ? { 'cac:SellersItemIdentification': { 'cbc:ID': T(it.codigo_producto) } } : {}),
      },
      'cac:Price': {
        'cbc:PriceAmount': { _attributes: { currencyID: d.moneda }, _text: String(round2(it.valor_unitario)) },
      },
    }
  })
}

function round2(n: number): number {
  return Math.round((n + Number.EPSILON) * 100) / 100
}

function buildDocumentBody(d: DocData, emisor: Emisor) {
  const numero = `${d.serie}-${d.correlativo}`
  const esBoleta = d.tipoDoc === '03'
  const invoiceTypeListID = esBoleta ? '0101' : '0101'
  const lineName = d.tipoDoc === '07' ? 'CreditNote' : d.tipoDoc === '08' ? 'DebitNote' : 'Invoice'

  const receptorTipo = d.receptorTipoDoc && d.receptorNumDoc ? d.receptorTipoDoc : esBoleta ? '1' : '6'

  const body: Record<string, unknown> = {
    'cbc:UBLVersionID': T('2.1'),
    'cbc:CustomizationID': T('2.0'),
    'cbc:ID': T(numero),
    'cbc:IssueDate': T(d.fechaEmision),
    [`cbc:${lineName}TypeCode`]: { _attributes: { listID: invoiceTypeListID }, _text: d.tipoDoc },
    'cbc:DocumentCurrencyCode': T(d.moneda),
    'cac:AccountingSupplierParty': {
      'cac:Party': {
        'cac:PartyIdentification': { 'cbc:ID': { _attributes: { schemeID: '6' }, _text: emisor.ruc } },
        'cac:PartyLegalEntity': {
          'cbc:RegistrationName': T(emisor.razon_social),
          'cac:RegistrationAddress': {
            'cbc:ID': T(emisor.ubigeo || '150101'),
            'cac:AddressLine': { 'cbc:Line': T(emisor.direccion || '-') },
          },
        },
      },
    },
    'cac:AccountingCustomerParty': {
      'cac:Party': {
        'cac:PartyIdentification': { 'cbc:ID': { _attributes: { schemeID: receptorTipo }, _text: d.receptorNumDoc || '00000000' } },
        'cac:PartyLegalEntity': { 'cbc:RegistrationName': T(d.receptorDenominacion || 'Cliente varios') },
      },
    },
    'cac:TaxTotal': {
      'cbc:TaxAmount': { _attributes: { currencyID: d.moneda }, _text: String(round2(d.totalIgv)) },
      'cac:TaxSubtotal': {
        'cbc:TaxableAmount': { _attributes: { currencyID: d.moneda }, _text: String(round2(d.totalGravado)) },
        'cbc:TaxAmount': { _attributes: { currencyID: d.moneda }, _text: String(round2(d.totalIgv)) },
        'cac:TaxCategory': {
          'cbc:TaxScheme': { 'cbc:ID': T('1000'), 'cbc:Name': T('IGV'), 'cbc:TaxTypeCode': T('VAT') },
        },
      },
    },
    'cac:LegalMonetaryTotal': {
      'cbc:LineExtensionAmount': { _attributes: { currencyID: d.moneda }, _text: String(round2(d.totalGravado + d.totalExonerado + d.totalInafecto)) },
      'cbc:TaxInclusiveAmount': { _attributes: { currencyID: d.moneda }, _text: String(round2(d.total)) },
      'cbc:PayableAmount': { _attributes: { currencyID: d.moneda }, _text: String(round2(d.total)) },
    },
    [`cac:${lineName}Line`]: buildLines(d),
  }

  // Referencia para notas (07/08)
  if ((d.tipoDoc === '07' || d.tipoDoc === '08') && d.refNumero) {
    body['cac:BillingReference'] = {
      'cac:InvoiceDocumentReference': {
        'cbc:ID': T(d.refNumero),
        'cbc:DocumentTypeCode': T(d.refTipoDoc || '01'),
      },
    }
    body['cac:DiscrepancyResponse'] = {
      'cbc:ResponseCode': T(d.motivoCodigo || '01'),
      'cbc:Description': T(d.motivoDesc || 'Anulación de la operación'),
    }
  }

  return body
}

export async function emitirApisunat(d: DocData, emisor: Emisor, cred: Credentials): Promise<EmitOutcome> {
  const fileName = `${emisor.ruc}-${d.tipoDoc}-${d.serie}-${d.correlativo}`
  const documentBody = buildDocumentBody(d, emisor)
  const endpoint = (cred.url || 'https://back.apisunat.com').replace(/\/$/, '') + '/personas/v1/sendBill'

  const res = await fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      personaId: cred.personaId,
      personaToken: cred.token,
      fileName,
      documentBody,
    }),
  })
  const raw = await res.json().catch(() => ({}))

  // APISUNAT: status ACEPTADO | RECHAZADO | EXCEPCION | PENDIENTE
  const status = String(raw.status || '').toUpperCase()
  const docId = raw.documentId as string | undefined
  const base = endpoint.replace('/personas/v1/sendBill', '')
  const pdfUrl = docId ? `${base}/documents/${docId}/getPDF/A4/${fileName}.pdf` : undefined
  const xmlUrl = docId ? `${base}/documents/${docId}/getXML/${fileName}.xml` : undefined

  if (status === 'ACEPTADO') {
    return { estado: 'aceptado', cdr: raw.sunatResponse?.cdrResponse?.description ?? 'ACEPTADO', pdfUrl, xmlUrl, hash: raw.hash, ticket: docId, mensaje: 'Aceptado por SUNAT', raw }
  }
  if (status === 'PENDIENTE') {
    return { estado: 'pendiente', ticket: docId, pdfUrl, xmlUrl, mensaje: 'En proceso (ticket generado)', raw }
  }
  return {
    estado: 'rechazado',
    mensaje: raw.error || raw.message || raw.sunatResponse?.error?.message || `Rechazado (${status || res.status})`,
    raw,
  }
}
