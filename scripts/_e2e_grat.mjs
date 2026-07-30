// E2E de GRATUITAS: emite una boleta con 1 ítem normal + 1 ítem gratis (bonificación 13)
// por el pipeline desplegado, y verifica el estado real en SUNAT. Sandbox propio.
const REF = 'uhslnkjepedwvizpcgpq'
const SUPA = 'https://uhslnkjepedwvizpcgpq.supabase.co'
const ANON = 'sb_publishable_XyWh5Lu59rTdGjVqLA1BQQ_j9JOfz7T'
const MGMT = process.env.MGMT_TOKEN
const q = async (sql) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST', headers: { Authorization: `Bearer ${MGMT}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  })
  return r.json()
}
const esc = (s) => (s == null ? 'null' : "'" + String(s).replace(/'/g, "''") + "'")

async function main() {
  const email = 'grat_bot@konversa.test', pass = 'GratTest1234secure!'
  await fetch(`${SUPA}/auth/v1/signup`, { method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: pass }) })
  await q(`update auth.users set email_confirmed_at=coalesce(email_confirmed_at,now()), confirmed_at=coalesce(confirmed_at,now()) where email=${esc(email)};`)
  const uid = (await q(`select id from auth.users where email=${esc(email)};`))[0]?.id
  let co = (await q(`select id from companies where owner_id=${esc(uid)} limit 1;`))[0]?.id
  if (!co) co = (await q(`insert into companies (owner_id, ruc, razon_social, regimen, direccion, ubigeo) values (${esc(uid)}, '20000000001', 'SANDBOX GRAT SAC', 'GENERAL', 'Av. Test 2, Lima', '150101') returning id;`))[0]?.id
  const jwt = (await (await fetch(`${SUPA}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: pass }) })).json()).access_token
  console.log('sandbox', co, 'jwt', jwt ? 'OK' : 'FALLÓ')
  if (!jwt) return

  const rpc = await (await fetch(`${SUPA}/rest/v1/rpc/emitir_venta`, {
    method: 'POST', headers: { apikey: ANON, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      p_company_id: co, p_tipo_doc: '03', p_serie: 'B901',
      p_cliente: { tipo_doc: '1', num_doc: '12345678', denominacion: 'CLIENTE GRAT' },
      p_items: [
        { descripcion: 'Producto pagado', cantidad: 1, precio_unitario: 50 },
        { descripcion: 'Producto de REGALO (bonificacion)', cantidad: 1, precio_unitario: 10, tipo_afectacion: '13' },
      ],
    }),
  })).json()
  console.log('emitir_venta →', JSON.stringify({ total: rpc.total, gratuito: rpc.total_gratuito, gravado: rpc.total_gravado, igv: rpc.total_igv, id: rpc.id }))
  if (!rpc.id) { console.log('RPC error:', JSON.stringify(rpc)); return }

  const emitRes = await (await fetch(`${SUPA}/functions/v1/emitir`, {
    method: 'POST', headers: { apikey: ANON, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ documentId: rpc.id }),
  })).json()
  const ticket = emitRes?.document?.sunat_ticket
  console.log('Edge emitir → estado:', emitRes?.result?.estado, '| ticket:', ticket, '| msg:', emitRes?.result?.mensaje || emitRes?.error)

  if (ticket && !String(ticket).startsWith('SIM-')) {
    for (let i = 0; i < 3; i++) {
      await new Promise((r) => setTimeout(r, 5000))
      const gb = await (await fetch(`https://back.apisunat.com/documents/${ticket}/getById`)).json()
      console.log(`[intento ${i + 1}] SUNAT status:`, gb.status, '| faults:', JSON.stringify(gb.faults || null))
      if (gb.status && gb.status !== 'PENDIENTE') break
    }
  }
  // limpieza del sandbox
  await q(`delete from document_items where document_id in (select id from documents where company_id=${esc(co)});`)
  await q(`delete from payments where company_id=${esc(co)};`)
  await q(`delete from inventory_movements where company_id=${esc(co)};`)
  await q(`delete from documents where company_id=${esc(co)};`)
  await q(`delete from series where company_id=${esc(co)};`)
  await q(`delete from memberships where company_id=${esc(co)};`)
  await q(`delete from audit_events where company_id=${esc(co)};`)
  await q(`delete from companies where id=${esc(co)};`)
  await q(`delete from auth.users where email=${esc(email)};`)
  console.log('sandbox limpiado')
}
main().catch((e) => console.error('ERR', e))
