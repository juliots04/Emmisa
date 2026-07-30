// E2E: emite un comprobante de PUNTA A PUNTA por el pipeline desplegado (RPC + Edge
// Function real) usando un usuario y una empresa SANDBOX propios (no toca datos reales).
// MGMT_TOKEN se pasa por entorno.
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
  const email = 'e2e_bot@konversa.test', pass = 'E2eTest1234secure!'
  // 1) signup (idempotente)
  const su = await fetch(`${SUPA}/auth/v1/signup`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: pass }),
  })
  console.log('signup HTTP', su.status)
  // 2) confirmar usuario
  await q(`update auth.users set email_confirmed_at=coalesce(email_confirmed_at,now()), confirmed_at=coalesce(confirmed_at,now()) where email=${esc(email)};`)
  const uid = (await q(`select id from auth.users where email=${esc(email)};`))[0]?.id
  console.log('uid', uid)
  // 3) empresa SANDBOX propia (RUC de prueba, serie B900 para no chocar con datos reales).
  //    El trigger on_company_created hace admin al owner de SU PROPIA empresa.
  let co = (await q(`select id from companies where owner_id=${esc(uid)} limit 1;`))[0]?.id
  if (!co) {
    co = (await q(`insert into companies (owner_id, ruc, razon_social, regimen, direccion, ubigeo)
      values (${esc(uid)}, '20000000001', 'SANDBOX E2E SAC', 'GENERAL', 'Av. Test 1, Lima', '150101') returning id;`))[0]?.id
  }
  console.log('sandbox company', co)
  // 4) login -> JWT real
  const lj = await (await fetch(`${SUPA}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: pass }),
  })).json()
  const jwt = lj.access_token
  console.log('JWT', jwt ? 'OK' : 'FALLÓ', lj.error_description || '')
  if (!jwt) return

  // 5) emitir_venta por PostgREST (RPC) con el JWT real → crea el doc pendiente.
  const rpc = await (await fetch(`${SUPA}/rest/v1/rpc/emitir_venta`, {
    method: 'POST', headers: { apikey: ANON, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      p_company_id: co, p_tipo_doc: '03', p_serie: 'B900',
      p_cliente: { tipo_doc: '1', num_doc: '12345678', denominacion: 'CLIENTE E2E' },
      p_items: [{ descripcion: 'Producto E2E', cantidad: 1, precio_unitario: 50 }],
    }),
  })).json()
  console.log('emitir_venta →', JSON.stringify(rpc))
  const docId = rpc.id
  if (!docId) return

  // 6) Edge Function `emitir` (real, envía a APISUNAT) con el JWT.
  const emitRes = await (await fetch(`${SUPA}/functions/v1/emitir`, {
    method: 'POST', headers: { apikey: ANON, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ documentId: docId }),
  })).json()
  console.log('Edge emitir →', JSON.stringify(emitRes).slice(0, 400))

  // 7) Estado real en SUNAT vía getById
  const ticket = emitRes?.document?.sunat_ticket
  if (ticket && !String(ticket).startsWith('SIM-')) {
    const gb = await (await fetch(`https://back.apisunat.com/documents/${ticket}/getById`)).json()
    console.log('\n>>> SUNAT status:', gb.status, '| faults:', JSON.stringify(gb.faults || null))
  }
}
main().catch((e) => console.error('ERR', e))
