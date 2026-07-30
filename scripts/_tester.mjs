// Tester/administrador de la BD vía Management API (uso interno de validación).
// Exporta helpers y, si se ejecuta directo, corre una inspección.
import fs from 'fs'

export const REF = 'uhslnkjepedwvizpcgpq'
export const MGMT_TOKEN = process.env.MGMT_TOKEN // se pasa por entorno, NO se guarda en el archivo
export const SUPA_URL = 'https://uhslnkjepedwvizpcgpq.supabase.co'
export const ANON = 'sb_publishable_XyWh5Lu59rTdGjVqLA1BQQ_j9JOfz7T'

export async function q(sql) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${MGMT_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  })
  const t = await r.text()
  try { return JSON.parse(t) } catch { return { _http: r.status, _text: t } }
}

async function inspect() {
  const P = (label, v) => console.log(label, JSON.stringify(v))
  // C1 correctivo: revocar EXECUTE de PUBLIC (authenticated lo hereda). No toca los
  // helpers de RLS (auth_company_ids, etc.) porque solo se revoca de simular_emision.
  await q('revoke execute on function simular_emision(uuid) from public;')
  console.log('=== C1: simular_emision ya NO ejecutable por authenticated ===')
  P('privilegios:', await q(
    "select has_function_privilege('authenticated','simular_emision(uuid)','execute') as auth_ejecuta, " +
    "has_function_privilege('service_role','simular_emision(uuid)','execute') as svc_ejecuta"))
  // Sanity: los helpers de RLS siguen ejecutables por authenticated.
  P('auth_company_ids ejecutable por authenticated:', await q(
    "select has_function_privilege('authenticated','auth_company_ids()','execute') as ok"))
  P('emitir_venta ejecutable por authenticated:', await q(
    "select has_function_privilege('authenticated'," +
    "'emitir_venta(uuid,text,text,jsonb,jsonb,text,numeric,numeric,uuid,text,numeric,text,numeric,text,date,uuid,numeric,numeric)','execute') as ok"))
  console.log('\n=== TODOS los documents (serie, correlativo, estado, ticket, hash) ===')
  P('docs:', await q(
    "select tipo_doc, serie, correlativo, estado_sunat, coalesce(sunat_ticket,'-') ticket, " +
    "coalesce(left(hash,10),'-') hash, coalesce(left(sunat_error,45),'-') err, to_char(created_at,'MM-DD HH24:MI') creado " +
    'from documents order by created_at'))
}

const esc = (s) => (s == null ? 'null' : "'" + String(s).replace(/'/g, "''").slice(0, 400) + "'")

// Resuelve los documentos 'pendiente' con ticket REAL consultando su estado en APISUNAT.
async function resolvePendientes() {
  const P = (l, v) => console.log(l, JSON.stringify(v))
  const docs = await q(
    "select id, serie, correlativo, sunat_ticket from documents " +
    "where estado_sunat = 'pendiente' and sunat_ticket is not null and sunat_ticket not like 'SIM-%'")
  console.log('Pendientes con ticket real:', Array.isArray(docs) ? docs.length : docs)
  for (const d of docs) {
    let gb
    try { gb = await (await fetch('https://back.apisunat.com/documents/' + d.sunat_ticket + '/getById')).json() }
    catch (e) { console.log(d.serie + '-' + d.correlativo, 'error red'); continue }
    const status = String(gb.status || '').toUpperCase()
    const fileName = gb.fileName
    const base = 'https://back.apisunat.com/documents/' + d.sunat_ticket
    const pdf = fileName ? base + '/getPDF/A4/' + fileName + '.pdf' : null
    const xml = fileName ? base + '/getXML/' + fileName + '.xml' : null
    const fault = gb.faults && gb.faults[0] && gb.faults[0].faultstring && gb.faults[0].faultstring._text
    let estado = 'pendiente', cdr = null, err = null
    if (status === 'ACEPTADO') { estado = 'aceptado'; cdr = typeof gb.cdr === 'string' ? gb.cdr : 'Aceptada por SUNAT' }
    else if (status === 'PENDIENTE') { estado = 'pendiente' }
    else { estado = 'rechazado'; err = fault ? '[' + status + '] ' + fault : status }
    await q(
      'update documents set estado_sunat=' + esc(estado) + ', cdr=' + esc(cdr) +
      ', sunat_error=' + esc(err) + ', pdf_url=' + esc(pdf) + ', xml_url=' + esc(xml) +
      ", hash=case when hash like 'SIM-%' then null else hash end where id=" + esc(d.id) + ';')
    console.log(d.serie + '-' + d.correlativo + ' → ' + estado.toUpperCase())
  }
  console.log('\n=== estados finales ===')
  P('estados:', await q('select estado_sunat, count(*) n from documents group by estado_sunat order by n desc'))
}

// Valida que las RPC reescritas en 0023 (emitir_venta / emitir_nota) sigan funcionando,
// dentro de una transacción con ROLLBACK (NO persiste: no crea comprobantes ni mueve stock).
async function validarRpc() {
  const P = (l, v) => console.log(l, JSON.stringify(v))
  const CO = '365cec10-00c9-48c0-acfc-c843144554dd'
  const u = await q("select id from auth.users where email='hola@gmail.com'")
  const uid = u[0] && u[0].id
  console.log('owner uid:', uid)
  // set jwt claim (auth.uid) + role, llamar emitir_venta, y ROLLBACK.
  const claim = '{"sub":"' + uid + '","role":"authenticated"}'
  const items = '[{"descripcion":"PRUEBA 0023 (rollback)","cantidad":2,"precio_unitario":15,"icbper":true}]'
  const cliente = '{"tipo_doc":"1","num_doc":"12345678","denominacion":"CLIENTE PRUEBA"}'
  const sql =
    'begin;' +
    "select set_config('request.jwt.claims','" + claim + "', true);" +
    "select emitir_venta('" + CO + "'::uuid,'03','B001','" + cliente + "'::jsonb,'" + items + "'::jsonb) as r;" +
    'rollback;'
  const res = await q(sql)
  console.log('\n=== emitir_venta (0023) — resultado de prueba (rollback) ===')
  P('res:', res)
}

async function validarNota() {
  const P = (l, v) => console.log(l, JSON.stringify(v))
  const CO = '365cec10-00c9-48c0-acfc-c843144554dd'
  const u = await q("select id from auth.users where email='hola@gmail.com'")
  const uid = u[0] && u[0].id
  const claim = '{"sub":"' + uid + '","role":"authenticated"}'
  const sql =
    'begin;' +
    "select set_config('request.jwt.claims','" + claim + "', true);" +
    "select emitir_nota('" + CO + "'::uuid," +
    "(select id from documents where company_id='" + CO + "' and serie='B001' and correlativo=7)," +
    "'07','01','Anulación de la operación', null, 'test-nota-rollback') as r;" +
    'rollback;'
  console.log('\n=== emitir_nota (0023) — NC sobre B001-7 (rollback) ===')
  P('res:', await q(sql))
}

resolvePendientes().then(validarRpc).then(validarNota).catch((e) => console.error('ERR', e))
