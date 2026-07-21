// Edge Function: emitir
// Emite un comprobante YA creado en `documents` (estado 'pendiente') contra el
// PSE real (APISUNAT) usando el secreto por empresa, y actualiza el estado
// server-side. Si no hay credenciales, cae a modo SIMULADO (para desarrollo).
//
// Deploy:  supabase functions deploy emitir
// Secrets: supabase secrets set APISUNAT_URL=... APISUNAT_PERSONA_ID=... APISUNAT_TOKEN=...
//          (o se configuran por empresa en emisor_credentials vía guardar_credenciales)
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders, json } from '../_shared/cors.ts'
import { emitirApisunat, type DocData, type Emisor } from './apisunat.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!

function qrContent(d: DocData, emisor: Emisor, hash: string): string {
  return [emisor.ruc, d.tipoDoc, d.serie, d.correlativo, round2(d.totalIgv), round2(d.total), d.fechaEmision, d.receptorTipoDoc || '-', d.receptorNumDoc || '-', hash].join('|')
}
function round2(n: number): number {
  return Math.round((n + Number.EPSILON) * 100) / 100
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405)

  try {
    const authHeader = req.headers.get('Authorization') ?? ''
    const { documentId } = await req.json()
    if (!documentId) return json({ error: 'Falta documentId' }, 400)

    // 1) Autorización: cliente con el JWT del usuario; RLS garantiza que solo
    //    puede leer documentos de su propia empresa.
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: docAuth, error: authErr } = await userClient
      .from('documents').select('id, company_id').eq('id', documentId).maybeSingle()
    if (authErr || !docAuth) return json({ error: 'No autorizado o documento inexistente' }, 403)

    // 2) Cliente de servicio (salta RLS) para leer el secreto y actualizar.
    const svc = createClient(SUPABASE_URL, SERVICE_KEY)

    const { data: doc } = await svc.from('documents').select('*').eq('id', documentId).single()
    const { data: items } = await svc.from('document_items').select('*').eq('document_id', documentId)
    const { data: company } = await svc.from('companies').select('ruc, razon_social, direccion, ubigeo').eq('id', doc.company_id).single()

    // 3) Resolver credenciales: por empresa → si no, del entorno (.env global).
    const { data: cred } = await svc
      .from('emisor_credentials').select('*')
      .eq('company_id', doc.company_id).eq('activo', true).maybeSingle()
    const credentials = cred?.token
      ? { url: cred.extra?.url || Deno.env.get('APISUNAT_URL') || 'https://back.apisunat.com', personaId: cred.persona_id, token: cred.token }
      : Deno.env.get('APISUNAT_TOKEN')
        ? { url: Deno.env.get('APISUNAT_URL') || 'https://back.apisunat.com', personaId: Deno.env.get('APISUNAT_PERSONA_ID')!, token: Deno.env.get('APISUNAT_TOKEN')! }
        : null

    const emisor: Emisor = {
      ruc: company.ruc, razon_social: company.razon_social,
      direccion: company.direccion, ubigeo: company.ubigeo,
    }
    const docData: DocData = {
      tipoDoc: doc.tipo_doc, serie: doc.serie, correlativo: doc.correlativo,
      fechaEmision: doc.fecha_emision, moneda: doc.moneda,
      receptorTipoDoc: doc.receptor_tipo_doc, receptorNumDoc: doc.receptor_num_doc,
      receptorDenominacion: doc.receptor_denominacion, receptorDireccion: doc.receptor_direccion,
      totalGravado: Number(doc.total_gravado), totalExonerado: Number(doc.total_exonerado || 0),
      totalInafecto: Number(doc.total_inafecto || 0), totalIgv: Number(doc.total_igv),
      total: Number(doc.total), motivoCodigo: doc.motivo_codigo, motivoDesc: doc.motivo_desc,
      items: (items ?? []).map((it) => ({
        descripcion: it.descripcion, cantidad: Number(it.cantidad),
        valor_unitario: Number(it.valor_unitario), precio_unitario: Number(it.precio_unitario),
        igv: Number(it.igv), total: Number(it.total),
        tipo_afectacion: it.tipo_afectacion || '10', unidad_medida: it.unidad_medida || 'NIU',
        codigo_producto: it.codigo_producto,
      })),
    }

    // 4) Emitir (real o simulado)
    let outcome
    let simulado = false
    if (credentials) {
      outcome = await emitirApisunat(docData, emisor, credentials)
    } else {
      simulado = true
      const numero = `${doc.serie}-${String(doc.correlativo).padStart(8, '0')}`
      outcome = { estado: 'aceptado' as const, cdr: `SIMULADO-${numero}`, mensaje: 'Aceptado (SIMULADO — configura credenciales para emitir de verdad)' }
    }

    const hash = outcome.hash ?? `SIM-${doc.serie}-${doc.correlativo}`
    const qr = qrContent(docData, emisor, hash)

    // 5) Persistir el resultado (server-side, ya no depende del navegador).
    const { data: updated } = await svc.from('documents').update({
      estado_sunat: outcome.estado,
      cdr: outcome.cdr ?? null,
      xml_url: outcome.xmlUrl ?? null,
      pdf_url: outcome.pdfUrl ?? null,
      hash,
      codigo_qr: qr,
      sunat_ticket: outcome.ticket ?? null,
      sunat_error: outcome.estado === 'rechazado' ? outcome.mensaje : null,
    }).eq('id', documentId).select().single()

    return json({ document: updated, result: { ...outcome, simulado } })
  } catch (e) {
    return json({ error: String(e?.message ?? e) }, 500)
  }
})
