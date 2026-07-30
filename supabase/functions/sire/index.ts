// Edge Function: sire
// Conecta con la API SIRE de SUNAT (RVIE ventas + RCE compras) usando las credenciales
// de CADA empresa (guardadas en sire_credentials). Acciones:
//   • test       → prueba que las credenciales autentican (obtiene token).
//   • propuesta  → solicita la propuesta del periodo (RVIE/RCE) → numTicket.
//   • consultar  → consulta el estado del ticket y el archivo.
// Deploy: supabase functions deploy sire
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders, json } from '../_shared/cors.ts'
import { getToken, solicitarPropuesta, aceptarPropuesta, consultarTicket, type SireCred } from './sunat.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405)

  try {
    const authHeader = req.headers.get('Authorization') ?? ''
    const { companyId, accion, tipo, periodo, numTicket, procesoId } = await req.json()
    if (!companyId || !accion) return json({ error: 'Falta companyId o accion' }, 400)

    // 1) Autorización: el usuario debe ser miembro de la empresa (RLS sobre companies).
    const userClient = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: authHeader } } })
    const { data: comp, error: authErr } = await userClient
      .from('companies').select('id, ruc').eq('id', companyId).maybeSingle()
    if (authErr || !comp) return json({ error: 'No autorizado o empresa inexistente' }, 403)

    // 2) Credenciales SIRE de la empresa (service_role: la tabla no se lee por Data API).
    const svc = createClient(SUPABASE_URL, SERVICE_KEY)
    const { data: cred } = await svc
      .from('sire_credentials').select('*').eq('company_id', companyId).eq('activo', true).maybeSingle()
    if (!cred) return json({ error: 'Esta empresa no tiene SIRE configurado (ve a Configuración → SIRE).' }, 400)

    const sireCred: SireCred = {
      client_id: cred.client_id, client_secret: cred.client_secret,
      sol_usuario: cred.sol_usuario, sol_clave: cred.sol_clave,
    }

    // Token OAuth2 (común a todas las acciones).
    const token = await getToken(sireCred, comp.ruc)

    if (accion === 'test') {
      return json({ ok: true, mensaje: 'Conexión con SUNAT SIRE correcta.' })
    }

    if (accion === 'propuesta') {
      if (!tipo || !periodo) return json({ error: 'Falta tipo (RVIE/RCE) o periodo (AAAAMM)' }, 400)
      const ticket = await solicitarPropuesta(token, tipo, periodo)
      const { data: proc } = await svc.from('sire_procesos').insert({
        company_id: companyId, tipo, periodo, num_ticket: ticket, estado: 'procesando',
      }).select().single()
      return json({ ok: true, proceso: proc, numTicket: ticket })
    }

    if (accion === 'aceptar') {
      if (!tipo || !periodo) return json({ error: 'Falta tipo (RVIE/RCE) o periodo (AAAAMM)' }, 400)
      const ticket = await aceptarPropuesta(token, tipo, periodo)
      const { data: proc } = await svc.from('sire_procesos').insert({
        company_id: companyId, tipo, periodo, num_ticket: ticket, estado: 'procesando',
        mensaje: 'Aceptación de propuesta (registro definitivo)',
      }).select().single()
      return json({ ok: true, proceso: proc, numTicket: ticket })
    }

    if (accion === 'consultar') {
      if (!tipo || !numTicket) return json({ error: 'Falta tipo o numTicket' }, 400)
      const r = await consultarTicket(token, tipo, numTicket)
      if (procesoId) {
        await svc.from('sire_procesos').update({
          estado: r.estado, archivo_url: r.archivoUrl ?? null, resumen: r.resumen ?? null, updated_at: new Date().toISOString(),
        }).eq('id', procesoId)
      }
      return json({ ok: true, ...r })
    }

    return json({ error: 'Acción no reconocida' }, 400)
  } catch (e) {
    return json({ error: String(e?.message ?? e) }, 500)
  }
})
