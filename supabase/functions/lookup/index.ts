// Consulta RUC/DNI para autocompletar nombre/razón social en Emitir y POS.
// Mantiene el token del proveedor en el servidor (secreto DOC_LOOKUP_TOKEN); el
// navegador nunca lo ve. Proveedor por defecto: apis.net.pe v2, configurable con
// DOC_LOOKUP_URL (base). Degrada con gracia: sin token -> { ok:false, reason:'sin_token' }.
//
// Configurar (una sola vez):
//   supabase secrets set DOC_LOOKUP_TOKEN=<tu_token_gratis>
//   (opcional) supabase secrets set DOC_LOOKUP_URL=https://api.apis.net.pe/v2
//   supabase functions deploy lookup

const cors: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
}

function pick(obj: Record<string, unknown>, keys: string[]): string | undefined {
  for (const k of keys) {
    const v = obj[k]
    if (typeof v === 'string' && v.trim()) return v.trim()
  }
  return undefined
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const body = (await req.json().catch(() => ({}))) as { tipo?: string; numero?: string }
    const num = String(body.numero ?? '').replace(/\D/g, '')
    const kind = body.tipo === 'ruc' ? 'ruc' : body.tipo === 'dni' ? 'dni' : ''
    if (!kind || (kind === 'ruc' && num.length !== 11) || (kind === 'dni' && num.length !== 8)) {
      return json({ ok: false, reason: 'numero_invalido' }, 400)
    }

    const token = Deno.env.get('DOC_LOOKUP_TOKEN')
    if (!token) return json({ ok: false, reason: 'sin_token' })

    const base = (Deno.env.get('DOC_LOOKUP_URL') ?? 'https://api.apis.net.pe/v2').replace(/\/$/, '')
    const path = kind === 'ruc' ? `/sunat/ruc?numero=${num}` : `/reniec/dni?numero=${num}`

    // Timeout: si el proveedor cuelga, no dejar la función bloqueada.
    const ctrl = new AbortController()
    const timer = setTimeout(() => ctrl.abort(), 8000)
    let resp: Response
    try {
      resp = await fetch(`${base}${path}`, {
        headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
        signal: ctrl.signal,
      })
    } finally {
      clearTimeout(timer)
    }
    if (!resp.ok) return json({ ok: false, reason: `proveedor_${resp.status}` })

    const raw = (await resp.json().catch(() => ({}))) as Record<string, unknown>
    // Algunos proveedores envuelven la data en { data: {...} }.
    const d = (raw.data && typeof raw.data === 'object' ? raw.data : raw) as Record<string, unknown>
    const denominacion = pick(d, [
      'nombre', 'razonSocial', 'razon_social', 'nombreCompleto', 'nombre_completo', 'full_name', 'name',
    ])
    const direccion = pick(d, ['direccion', 'direccion_completa', 'domicilioFiscal', 'address'])
    if (!denominacion) return json({ ok: false, reason: 'sin_datos' })
    return json({ ok: true, denominacion, direccion })
  } catch {
    // No filtrar detalle interno del error al cliente.
    return json({ ok: false, reason: 'error' })
  }
})
