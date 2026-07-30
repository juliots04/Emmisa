export type FiscalEnvironment = 'beta' | 'production'
export type FiscalArtifactKind =
  | 'unsigned_xml'
  | 'signed_xml'
  | 'request_zip'
  | 'cdr_zip'
  | 'cdr_xml'
  | 'pdf'

export interface FiscalIssuer {
  id: string
  ruc: string
  legalName: string
  status: 'active' | 'inactive'
}

export interface FiscalArtifact {
  kind: FiscalArtifactKind
  version: number
  sha256: string
  byteSize: string
  contentType: string
  downloadUrl: string
}

export interface FiscalDocument {
  id: string
  issuerId: string
  environment: FiscalEnvironment
  documentType: string
  series: string
  number: string
  fullNumber: string
  processingStatus: 'queued' | 'processing' | 'completed' | 'failed'
  sunatStatus:
    | 'pending'
    | 'simulated'
    | 'accepted'
    | 'accepted_with_observations'
    | 'rejected'
    | 'void_pending'
    | 'voided'
  sunatResponse?: {
    code?: string | null
    message?: string | null
    ticket?: string | null
  }
  artifacts: FiscalArtifact[]
}

export interface CreateFiscalDocument {
  issuerId: string
  environment: FiscalEnvironment
  documentType: '01' | '03' | '07' | '08'
  operationType: string
  series: string
  number: string
  issueDate: string
  currency: string
  exchangeRate?: string
  paymentTerms: 'cash' | 'credit'
  customer: {
    documentType: string
    documentNumber?: string
    name: string
    address?: string
  }
  items: Array<{
    productCode?: string
    description: string
    unitCode: string
    quantity: string
    unitPrice: string
    priceIncludesTax: true
    affectationCode: string
    discountAmount?: string
  }>
  installments?: Array<{ dueDate: string; amount: string }>
}

interface FiscalProblem {
  title?: string
  detail?: string
  message?: string | string[]
  status?: number
  requestId?: string
}

export class FiscalApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly requestId?: string,
  ) {
    super(message)
    this.name = 'FiscalApiError'
  }
}

function config(): { baseUrl: string; apiKey: string } {
  const rawUrl = Deno.env.get('FISCAL_API_URL')?.trim()
  const apiKey = Deno.env.get('FISCAL_API_KEY')?.trim()
  if (!rawUrl || !apiKey) {
    throw new Error(
      'Fiscal API no está configurada en el backend. Faltan FISCAL_API_URL o FISCAL_API_KEY.',
    )
  }
  const url = new URL(rawUrl)
  const local = ['localhost', '127.0.0.1', 'host.docker.internal'].includes(url.hostname)
  if (url.protocol !== 'https:' && !(local && url.protocol === 'http:')) {
    throw new Error('FISCAL_API_URL debe usar HTTPS fuera del entorno local')
  }
  return { baseUrl: url.toString().replace(/\/$/, ''), apiKey }
}

function problemMessage(problem: FiscalProblem, status: number): string {
  const message = Array.isArray(problem.message)
    ? problem.message.join('; ')
    : problem.detail || problem.message || problem.title
  return message || `Fiscal API respondió HTTP ${status}`
}

async function request(
  path: string,
  init: RequestInit = {},
  timeoutMs = 20_000,
): Promise<Response> {
  const { baseUrl, apiKey } = config()
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), timeoutMs)
  try {
    const response = await fetch(`${baseUrl}${path}`, {
      ...init,
      signal: controller.signal,
      headers: {
        Accept: 'application/json',
        'X-API-Key': apiKey,
        ...(init.body ? { 'Content-Type': 'application/json' } : {}),
        ...(init.headers ?? {}),
      },
    })
    if (!response.ok) {
      const problem = (await response.json().catch(() => ({}))) as FiscalProblem
      throw new FiscalApiError(
        problemMessage(problem, response.status),
        response.status,
        problem.requestId,
      )
    }
    return response
  } catch (error) {
    if (error instanceof FiscalApiError) throw error
    if (error instanceof DOMException && error.name === 'AbortError') {
      throw new Error('Fiscal API no respondió dentro del tiempo permitido')
    }
    throw error
  } finally {
    clearTimeout(timeout)
  }
}

export async function findIssuer(issuerId: string): Promise<FiscalIssuer | null> {
  const response = await request('/v1/issuers')
  const body = (await response.json()) as { data?: FiscalIssuer[] }
  return body.data?.find((issuer) => issuer.id === issuerId) ?? null
}

export async function createFiscalDocument(
  idempotencyKey: string,
  payload: CreateFiscalDocument,
): Promise<FiscalDocument> {
  const response = await request('/v1/documents', {
    method: 'POST',
    headers: { 'Idempotency-Key': idempotencyKey },
    body: JSON.stringify(payload),
  })
  return (await response.json()) as FiscalDocument
}

export async function getFiscalDocument(documentId: string): Promise<FiscalDocument> {
  const response = await request(`/v1/documents/${encodeURIComponent(documentId)}`)
  return (await response.json()) as FiscalDocument
}

export async function waitForFiscalDocument(
  documentId: string,
  maxWaitMs = 10_000,
): Promise<FiscalDocument> {
  const startedAt = Date.now()
  let document = await getFiscalDocument(documentId)
  while (
    ['queued', 'processing'].includes(document.processingStatus)
    && Date.now() - startedAt < maxWaitMs
  ) {
    await new Promise((resolve) => setTimeout(resolve, 500))
    document = await getFiscalDocument(documentId)
  }
  return document
}

export async function downloadFiscalArtifact(
  documentId: string,
  kind: FiscalArtifactKind,
  version = 1,
): Promise<Response> {
  return request(
    `/v1/documents/${encodeURIComponent(documentId)}/artifacts/${kind}?version=${version}`,
    { headers: { Accept: '*/*' } },
    30_000,
  )
}
