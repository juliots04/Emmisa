// TESTER E2E v3 — post-fix (local anexo 3030 + URLs). Series B únicas para boletas.
import { readFileSync } from 'node:fs'
const env = Object.fromEntries(readFileSync('.env', 'utf8').split('\n').filter(Boolean).map((l) => { const i = l.indexOf('='); return [l.slice(0, i).trim(), l.slice(i + 1).trim().replace(/^["']|["']$/g, '')] }))
const SUPA = env.VITE_SUPABASE_URL, ANON = env.VITE_SUPABASE_ANON_KEY
const h = (jwt) => ({ apikey: ANON, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' })
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const n = Number(String(Date.now()).slice(-3))
const pad3 = (x) => String(x % 1000).padStart(3, '0')

async function main() {
  const su = await (await fetch(`${SUPA}/auth/v1/signup`, { method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' }, body: JSON.stringify({ email: `t_${Date.now()}@emmisa-test.com`, password: 'Test123456!' }) })).json()
  const jwt = su.access_token, uid = su.user?.id
  const co = await (await fetch(`${SUPA}/rest/v1/companies`, { method: 'POST', headers: { ...h(jwt), Prefer: 'return=representation' }, body: JSON.stringify({ owner_id: uid, ruc: '20000000001', razon_social: 'TESTER SAC', regimen: 'GENERAL', direccion: 'Av Test 1', ubigeo: '150101' }) })).json()
  const companyId = co[0]?.id
  console.log('empresa:', companyId)
  const docs = []

  const emitir = async (label, body) => {
    const rpc = await (await fetch(`${SUPA}/rest/v1/rpc/emitir_venta`, { method: 'POST', headers: h(jwt), body: JSON.stringify(body) })).json()
    if (!rpc.id) { console.log(`  ${label}: RPC FALLÓ ${JSON.stringify(rpc)}`); return }
    docs.push(rpc.id)
    const em = await (await fetch(`${SUPA}/functions/v1/emitir`, { method: 'POST', headers: h(jwt), body: JSON.stringify({ documentId: rpc.id }) })).json()
    return { ticket: em?.document?.sunat_ticket, xml: em?.document?.xml_url, pdf: em?.document?.pdf_url, numero: rpc.numero, estado0: em?.result?.estado }
  }

  const boleta = await emitir('boleta', { p_company_id: companyId, p_tipo_doc: '03', p_serie: `B${pad3(n)}`, p_cliente: { tipo_doc: '1', num_doc: '12345678', denominacion: 'CLIENTE' }, p_items: [{ descripcion: 'Producto', cantidad: 1, precio_unitario: 118 }] })
  const bolDesc = await emitir('bolDesc', { p_company_id: companyId, p_tipo_doc: '03', p_serie: `B${pad3(n + 1)}`, p_cliente: { tipo_doc: '1', num_doc: '12345678', denominacion: 'CLIENTE' }, p_items: [{ descripcion: 'Producto', cantidad: 2, precio_unitario: 59 }], p_descuento_global: 10 })
  const factura = await emitir('factura', { p_company_id: companyId, p_tipo_doc: '01', p_serie: `F${pad3(n)}`, p_cliente: { tipo_doc: '6', num_doc: '20123456789', denominacion: 'EMPRESA SAC' }, p_items: [{ descripcion: 'Servicio', cantidad: 1, precio_unitario: 236 }], p_condicion_pago: 'credito', p_fecha_vencimiento: '2026-09-30' })

  for (const [label, r] of [['BOLETA simple', boleta], ['BOLETA descuento', bolDesc], ['FACTURA crédito', factura]]) {
    if (!r?.ticket || String(r.ticket).startsWith('SIM-')) { console.log(`\n${label} (${r?.numero}): sin ticket real → estado ${r?.estado0}`); continue }
    let gb
    for (let i = 0; i < 12; i++) { gb = await (await fetch(`https://back.apisunat.com/documents/${r.ticket}/getById`)).json(); if (gb.status && gb.status !== 'PENDIENTE') break; await sleep(3000) }
    const fault = gb.faults?.[0]?.faultstring?._text
    const bodyStr = typeof gb.json === 'string' ? gb.json : JSON.stringify(gb.json || {})
    console.log(`\n>>> ${label} (${r.numero}): SUNAT=${gb.status}${fault ? ' | ' + fault : ''}`)
    console.log(`    body: FormaPago=${bodyStr.includes('FormaPago') ? 'SÍ' : 'no'} Leyenda1000=${bodyStr.includes('"1000"') ? 'SÍ' : 'no'} AllowanceCharge=${bodyStr.includes('AllowanceCharge') ? 'SÍ' : 'no'} Credito=${bodyStr.includes('Credito') ? 'SÍ' : 'no'}`)
    // valida URLs de descarga (fix)
    if (r.pdf) { const pr = await fetch(r.pdf); console.log(`    pdf_url HTTP ${pr.status}`) }
    if (r.xml) { const xr = await fetch(r.xml); console.log(`    xml_url HTTP ${xr.status}`) }
  }

  console.log('\nlimpieza...')
  for (const id of docs) { await fetch(`${SUPA}/rest/v1/document_items?document_id=eq.${id}`, { method: 'DELETE', headers: h(jwt) }); await fetch(`${SUPA}/rest/v1/documents?id=eq.${id}`, { method: 'DELETE', headers: h(jwt) }) }
  await fetch(`${SUPA}/rest/v1/series?company_id=eq.${companyId}`, { method: 'DELETE', headers: h(jwt) })
  await fetch(`${SUPA}/rest/v1/companies?id=eq.${companyId}`, { method: 'DELETE', headers: h(jwt) })
  console.log('listo.')
}
main().catch((e) => console.error('ERR', e))
