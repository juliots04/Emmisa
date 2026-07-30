// Edge Function: enviar-comprobante
// Envía por correo un comprobante ya emitido y adjunta sus artefactos. Estos se
// descargan server-to-server desde Fiscal API; su API key nunca sale del backend.
// Cada empresa/reseller puede tener su propio remitente; si no, usa el del entorno.
//
// Deploy:  supabase functions deploy enviar-comprobante
// Secrets: supabase secrets set RESEND_API_KEY=re_...  EMAIL_FROM="Emmisa <no-reply@tudominio.com>"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders, json } from '../_shared/cors.ts'
import {
  downloadFiscalArtifact,
  type FiscalArtifactKind,
} from '../_shared/fiscal-api.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')
const EMAIL_FROM = Deno.env.get('EMAIL_FROM') || 'Emmisa <onboarding@resend.dev>'

function esEmail(v: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v)
}

function toBase64(bytes: Uint8Array): string {
  let binary = ''
  const chunkSize = 0x8000
  for (let start = 0; start < bytes.length; start += chunkSize) {
    const chunk = bytes.subarray(start, Math.min(start + chunkSize, bytes.length))
    for (const byte of chunk) binary += String.fromCharCode(byte)
  }
  return btoa(binary)
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405)

  try {
    const authHeader = req.headers.get('Authorization') ?? ''
    const { documentId, email } = await req.json()
    if (!documentId || !email) return json({ error: 'Falta documentId o email' }, 400)
    if (!esEmail(String(email))) return json({ error: 'Email inválido' }, 400)

    // 1) Autorización por RLS: el usuario solo puede leer documentos de su empresa.
    const userClient = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: authHeader } } })
    const { data: docAuth, error: authErr } = await userClient
      .from('documents').select('id, company_id').eq('id', documentId).maybeSingle()
    if (authErr || !docAuth) return json({ error: 'No autorizado o documento inexistente' }, 403)

    // 2) Datos del comprobante (service role).
    const svc = createClient(SUPABASE_URL, SERVICE_KEY)
    const { data: doc, error: docError } = await svc.from('documents')
      .select('tipo_doc, serie, correlativo, moneda, total, estado_sunat, fiscal_document_id, fiscal_artifacts, receptor_denominacion, fecha_emision')
      .eq('id', documentId).single()
    const { data: company } = await svc.from('companies').select('razon_social, ruc').eq('id', docAuth.company_id).single()
    if (docError || !doc) {
      return json({ error: docError?.message || 'Comprobante inexistente' }, 404)
    }

    if (!RESEND_API_KEY) {
      return json({ error: 'Envío de correo no configurado. Falta el secret RESEND_API_KEY en la función.' }, 501)
    }

    const tipoNombre = ({ '01': 'Factura', '03': 'Boleta', '07': 'Nota de crédito', '08': 'Nota de débito' } as Record<string, string>)[doc.tipo_doc] || 'Comprobante'
    const numero = `${doc.serie}-${String(doc.correlativo).padStart(8, '0')}`
    const simbolo = doc.moneda === 'USD' ? 'US$' : doc.moneda === 'EUR' ? '€' : 'S/'
    if (!doc.fiscal_document_id) {
      return json({ error: 'El comprobante no tiene artefactos de Fiscal API' }, 409)
    }
    const available = new Set(
      (Array.isArray(doc.fiscal_artifacts) ? doc.fiscal_artifacts : [])
        .map((artifact: { kind?: string }) => artifact.kind),
    )
    const possibleAttachments: Array<{ kind: FiscalArtifactKind; filename: string }> = [
      { kind: 'pdf', filename: `${numero}.pdf` },
      { kind: 'signed_xml', filename: `${numero}-firmado.xml` },
      { kind: 'cdr_xml', filename: `${numero}-cdr.xml` },
    ]
    const requested = possibleAttachments.filter((artifact) => available.has(artifact.kind))
    const attachments = await Promise.all(requested.map(async ({ kind, filename }) => {
      const artifact = await downloadFiscalArtifact(doc.fiscal_document_id, kind)
      return {
        filename,
        content: toBase64(new Uint8Array(await artifact.arrayBuffer())),
      }
    }))

    const html = `
      <div style="font-family:system-ui,Segoe UI,Roboto,sans-serif;max-width:520px;margin:auto;color:#111">
        <h2 style="margin:0 0 4px">${tipoNombre} ${numero}</h2>
        <p style="color:#555;margin:0 0 16px">${company?.razon_social ?? ''} · RUC ${company?.ruc ?? ''}</p>
        <table style="width:100%;border-collapse:collapse;font-size:14px">
          <tr><td style="padding:6px 0;color:#666">Cliente</td><td style="text-align:right">${doc.receptor_denominacion ?? '—'}</td></tr>
          <tr><td style="padding:6px 0;color:#666">Fecha</td><td style="text-align:right">${doc.fecha_emision ?? ''}</td></tr>
          <tr><td style="padding:6px 0;color:#666">Estado</td><td style="text-align:right">${doc.estado_sunat ?? ''}</td></tr>
          <tr><td style="padding:10px 0;border-top:1px solid #eee;font-weight:700">Total</td>
              <td style="text-align:right;padding:10px 0;border-top:1px solid #eee;font-weight:700">${simbolo} ${Number(doc.total).toFixed(2)}</td></tr>
        </table>
        <p style="margin-top:16px">Se adjuntan el PDF, XML firmado y CDR disponibles.</p>
        <p style="color:#888;font-size:12px;margin-top:24px">Enviado con Emmisa.</p>
      </div>`

    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: EMAIL_FROM,
        to: [email],
        subject: `${tipoNombre} ${numero} - ${company?.razon_social ?? ''}`,
        html,
        attachments,
      }),
    })
    const out = await res.json().catch(() => ({}))
    if (!res.ok) return json({ error: out?.message || `No se pudo enviar (HTTP ${res.status})` }, 502)

    return json({ ok: true, id: out?.id })
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500)
  }
})
