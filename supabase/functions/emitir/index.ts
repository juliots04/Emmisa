// Edge Function: emitir
// Flujo único: Vue -> Supabase Edge Function -> Emmisa Fiscal API -> SUNAT.
// La API key es un secret server-side y nunca se entrega al navegador.
//
// Deploy:
//   supabase functions deploy emitir
//   supabase secrets set FISCAL_API_URL=https://fiscal.tudominio.pe \
//     FISCAL_API_KEY=kfa_... REQUIRE_REAL_EMITTER=true
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders, json } from '../_shared/cors.ts'
import {
  createFiscalDocument,
  findIssuer,
  getFiscalDocument,
  waitForFiscalDocument,
  type CreateFiscalDocument,
  type FiscalDocument,
} from '../_shared/fiscal-api.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!

type DbRecord = Record<string, unknown>

function amount(value: unknown): string {
  const number = Number(value ?? 0)
  if (!Number.isFinite(number) || number < 0) throw new Error('Importe fiscal inválido')
  return number.toFixed(2)
}

function quantity(value: unknown): string {
  const number = Number(value ?? 0)
  if (!Number.isFinite(number) || number <= 0) throw new Error('Cantidad fiscal inválida')
  return number.toFixed(6)
}

function exchangeRate(value: unknown): string {
  const number = Number(value ?? 0)
  if (!Number.isFinite(number) || number <= 0) throw new Error('Tipo de cambio inválido')
  return number.toFixed(6)
}

function assertSupportedDocument(doc: DbRecord, items: DbRecord[]): void {
  if (!['01', '03', '07', '08'].includes(String(doc.tipo_doc))) {
    throw new Error(
      `Tipo de comprobante ${String(doc.tipo_doc)} no soportado para emisión directa`,
    )
  }
  if (Number(doc.total_icbper ?? 0) !== 0 || Number(doc.total_isc ?? 0) !== 0) {
    throw new Error('Fiscal API aún no soporta ICBPER ni ISC; el comprobante no fue enviado')
  }
  if (
    Number(doc.total_exportacion ?? 0) !== 0
    || Number(doc.total_gratuito ?? 0) !== 0
    || Number(doc.descuento_global ?? 0) !== 0
  ) {
    throw new Error(
      'Fiscal API aún no soporta exportaciones, operaciones gratuitas ni descuento global; el comprobante no fue enviado',
    )
  }
  const unsupported = items.find((item) => !['10', '20', '30'].includes(String(item.tipo_afectacion || '10')))
  if (unsupported) {
    throw new Error(
      `Afectación SUNAT ${String(unsupported.tipo_afectacion)} aún no soportada por Fiscal API`,
    )
  }
}

function buildPayload(
  doc: DbRecord,
  items: DbRecord[],
  issuerId: string,
  environment: 'beta' | 'production',
): CreateFiscalDocument {
  assertSupportedDocument(doc, items)
  const credit = doc.condicion_pago === 'credito'
  if (credit && !doc.fecha_vencimiento) {
    throw new Error('Un comprobante al crédito requiere fecha de vencimiento')
  }
  const documentNumber = String(doc.receptor_num_doc ?? '').trim()
  const defaultDocType = doc.tipo_doc === '01' ? '6' : documentNumber.length === 11 ? '6' : documentNumber.length === 8 ? '1' : '0'
  const customerDocType = String(doc.receptor_tipo_doc || defaultDocType)

  const payload: CreateFiscalDocument = {
    issuerId,
    environment,
    documentType: doc.tipo_doc as '01' | '03' | '07' | '08',
    operationType: String(doc.tipo_operacion || '0101'),
    series: String(doc.serie),
    number: String(doc.correlativo),
    issueDate: String(doc.fecha_emision),
    currency: String(doc.moneda || 'PEN'),
    paymentTerms: credit ? 'credit' : 'cash',
    customer: {
      documentType: customerDocType,
      ...(documentNumber ? { documentNumber } : {}),
      name: String(doc.receptor_denominacion || (customerDocType === '0' ? 'CLIENTE VARIOS' : 'CLIENTE')),
      ...(doc.receptor_direccion ? { address: String(doc.receptor_direccion) } : {}),
    },
    items: items.map((item) => ({
      ...(item.codigo_producto ? { productCode: String(item.codigo_producto) } : {}),
      description: String(item.descripcion),
      unitCode: String(item.unidad_medida || 'NIU'),
      quantity: quantity(item.cantidad),
      unitPrice: amount(item.precio_unitario),
      priceIncludesTax: true,
      affectationCode: String(item.tipo_afectacion || '10'),
      ...(Number(item.descuento ?? 0) > 0
        ? { discountAmount: amount(item.descuento) }
        : {}),
    })),
  }
  if (payload.currency !== 'PEN') payload.exchangeRate = exchangeRate(doc.tipo_cambio)
  if (credit) {
    payload.installments = [{
      dueDate: String(doc.fecha_vencimiento),
      amount: amount(doc.total),
    }]
  }
  return payload
}

function appStatus(fiscal: FiscalDocument): 'aceptado' | 'rechazado' | 'pendiente' {
  if (['accepted', 'accepted_with_observations'].includes(fiscal.sunatStatus)) {
    return 'aceptado'
  }
  if (fiscal.sunatStatus === 'rejected' || fiscal.processingStatus === 'failed') {
    return 'rechazado'
  }
  return 'pendiente'
}

function cdrDescription(fiscal: FiscalDocument): string | null {
  const code = fiscal.sunatResponse?.code?.trim()
  const message = fiscal.sunatResponse?.message?.trim()
  if (!code && !message) return null
  return [code ? `SUNAT ${code}` : '', message ?? ''].filter(Boolean).join(': ')
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405)

  try {
    const authHeader = req.headers.get('Authorization') ?? ''
    const { documentId } = await req.json()
    if (!documentId) return json({ error: 'Falta documentId' }, 400)

    // La consulta con JWT + RLS confirma que el usuario pertenece a la empresa.
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: docAuth, error: authError } = await userClient
      .from('documents')
      .select('id, company_id')
      .eq('id', documentId)
      .maybeSingle()
    if (authError || !docAuth) {
      return json({ error: 'No autorizado o documento inexistente' }, 403)
    }

    const service = createClient(SUPABASE_URL, SERVICE_KEY)
    const { data: canEmit } = await service.rpc('suscripcion_permite_emitir', {
      p_company_id: docAuth.company_id,
    })
    if (canEmit === false) {
      return json({
        error:
          'La suscripción de esta empresa no está activa. Regulariza el pago para volver a emitir comprobantes.',
      }, 402)
    }

    const [{ data: doc, error: docError }, { data: items, error: itemsError }, {
      data: company,
      error: companyError,
    }, { data: integration, error: integrationError }] = await Promise.all([
      service.from('documents').select('*').eq('id', documentId).single(),
      service.from('document_items').select('*').eq('document_id', documentId),
      service.from('companies').select('ruc, razon_social').eq('id', docAuth.company_id).single(),
      service
        .from('fiscal_integrations')
        .select('issuer_id, environment')
        .eq('company_id', docAuth.company_id)
        .eq('active', true)
        .maybeSingle(),
    ])
    if (docError || itemsError || companyError) {
      throw new Error(
        docError?.message || itemsError?.message || companyError?.message || 'Datos incompletos',
      )
    }
    if (integrationError || !integration) {
      return json({
        error:
          'La empresa aún no está vinculada con un emisor de Fiscal API. El backend debe completar el provisionamiento.',
      }, 400)
    }

    // Defensa multiempresa: el UUID configurado debe pertenecer al mismo RUC.
    const issuer = await findIssuer(String(integration.issuer_id))
    if (!issuer || issuer.status !== 'active') {
      return json({ error: 'El emisor configurado no existe o está inactivo en Fiscal API' }, 400)
    }
    if (issuer.ruc !== String(company.ruc).trim()) {
      return json({ error: 'El RUC del emisor de Fiscal API no coincide con la empresa' }, 409)
    }

    let fiscal: FiscalDocument
    if (doc.fiscal_document_id) {
      fiscal = await getFiscalDocument(String(doc.fiscal_document_id))
    } else {
      const payload = buildPayload(
        doc as DbRecord,
        (items ?? []) as DbRecord[],
        String(integration.issuer_id),
        integration.environment as 'beta' | 'production',
      )
      fiscal = await createFiscalDocument(`emmisa-app-document-${documentId}`, payload)
      const { error: linkError } = await service
        .from('documents')
        .update({ fiscal_document_id: fiscal.id })
        .eq('id', documentId)
      if (linkError) throw new Error(`No se pudo vincular Fiscal API: ${linkError.message}`)
    }

    if (['queued', 'processing'].includes(fiscal.processingStatus)) {
      fiscal = await waitForFiscalDocument(fiscal.id)
    }

    if (fiscal.sunatStatus === 'simulated') {
      await service.from('documents').update({
        estado_sunat: 'pendiente',
        fiscal_sunat_status: fiscal.sunatStatus,
        sunat_error:
          'Fiscal API está usando un driver simulado. Configure EMISSION_DRIVER=sunat para emitir realmente.',
      }).eq('id', documentId)
      return json({
        error:
          'Fiscal API respondió en modo simulado; el comprobante no fue marcado como aceptado.',
      }, 502)
    }

    const estado = appStatus(fiscal)
    const cdr = cdrDescription(fiscal)
    const fiscalError = estado === 'rechazado'
      ? cdr || `Fiscal API terminó con estado ${fiscal.processingStatus}`
      : null
    const { data: updated, error: updateError } = await service
      .from('documents')
      .update({
        estado_sunat: estado,
        fiscal_document_id: fiscal.id,
        fiscal_sunat_status: fiscal.sunatStatus,
        fiscal_artifacts: fiscal.artifacts ?? [],
        cdr,
        sunat_ticket: fiscal.sunatResponse?.ticket ?? doc.sunat_ticket ?? null,
        sunat_error: fiscalError,
      })
      .eq('id', documentId)
      .select()
      .single()
    if (updateError || !updated) {
      throw new Error(`No se pudo persistir el resultado: ${updateError?.message ?? 'sin datos'}`)
    }

    return json({
      document: updated,
      result: {
        estado,
        cdr: cdr ?? undefined,
        ticket: fiscal.sunatResponse?.ticket ?? undefined,
        mensaje:
          estado === 'pendiente'
            ? 'Fiscal API continúa procesando; vuelve a consultar el estado.'
            : cdr || `${fiscal.fullNumber}: ${fiscal.sunatStatus}`,
        simulado: false,
        fiscalDocumentId: fiscal.id,
        sunatStatus: fiscal.sunatStatus,
        artifacts: fiscal.artifacts ?? [],
      },
    })
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : String(error) }, 500)
  }
})
