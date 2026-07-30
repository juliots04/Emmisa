// ============================================================
// Edge Function · Tipo de cambio SUNAT
// apis.net.pe no permite CORS desde el navegador, así que lo consultamos
// server-side y lo devolvemos con CORS para toda la app.
// Deploy:  supabase functions deploy tipo-cambio --no-verify-jwt
// ============================================================
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  try {
    const res = await fetch('https://api.apis.net.pe/v1/tipo-cambio-sunat')
    const data = await res.json()
    const venta = Number(data?.venta)
    if (!venta || Number.isNaN(venta)) throw new Error('respuesta inválida de SUNAT')
    return new Response(
      JSON.stringify({
        venta,
        compra: Number(data?.compra ?? venta),
        fecha: data?.fecha ?? null,
        origen: 'SUNAT',
      }),
      { headers: { ...CORS, 'Content-Type': 'application/json' } },
    )
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 502,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
})
