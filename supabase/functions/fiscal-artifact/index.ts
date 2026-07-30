// Descarga autenticada de artefactos. El navegador se autentica con su JWT ante
// Supabase; esta función agrega la API key únicamente en la llamada server-to-server.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders, json } from '../_shared/cors.ts'
import {
  downloadFiscalArtifact,
  type FiscalArtifactKind,
} from '../_shared/fiscal-api.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const KINDS = new Set<FiscalArtifactKind>([
  'unsigned_xml',
  'signed_xml',
  'request_zip',
  'cdr_zip',
  'cdr_xml',
  'pdf',
])

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405)

  try {
    const { documentId, kind } = await req.json()
    if (!documentId || !KINDS.has(kind)) {
      return json({ error: 'documentId o tipo de artefacto inválido' }, 400)
    }
    const authHeader = req.headers.get('Authorization') ?? ''
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: document, error } = await userClient
      .from('documents')
      .select('serie, correlativo, fiscal_document_id, fiscal_artifacts')
      .eq('id', documentId)
      .maybeSingle()
    if (error || !document) {
      return json({ error: 'No autorizado o documento inexistente' }, 403)
    }
    if (!document.fiscal_document_id) {
      return json({ error: 'El comprobante no está vinculado con Fiscal API' }, 404)
    }
    const metadata = Array.isArray(document.fiscal_artifacts)
      ? document.fiscal_artifacts.find((artifact: { kind?: string }) => artifact.kind === kind)
      : null
    if (!metadata) return json({ error: 'El artefacto todavía no está disponible' }, 404)

    const upstream = await downloadFiscalArtifact(
      String(document.fiscal_document_id),
      kind,
      Number(metadata.version ?? 1),
    )
    const extension = kind === 'pdf' ? 'pdf' : kind.endsWith('_zip') ? 'zip' : 'xml'
    const filename =
      `${document.serie}-${String(document.correlativo).padStart(8, '0')}-${kind}.${extension}`
    return new Response(upstream.body, {
      status: 200,
      headers: {
        ...corsHeaders,
        'Content-Type': upstream.headers.get('Content-Type') || 'application/octet-stream',
        'Content-Disposition': `attachment; filename="${filename}"`,
        'Cache-Control': 'private, no-store',
        'X-Content-Type-Options': 'nosniff',
      },
    })
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : String(error) }, 500)
  }
})
