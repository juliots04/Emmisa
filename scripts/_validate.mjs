// Valida las RPC reescritas en 0023 con transacciones ROLLBACK (no persisten).
const REF = 'uhslnkjepedwvizpcgpq'
const MGMT = process.env.MGMT_TOKEN
const CO = '365cec10-00c9-48c0-acfc-c843144554dd'
const q = async (sql) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST', headers: { Authorization: `Bearer ${MGMT}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  })
  return r.json()
}
const claim = async () => {
  const u = await q("select id from auth.users where email='hola@gmail.com'")
  return '{"sub":"' + u[0].id + '","role":"authenticated"}'
}

async function main() {
  const c = await claim()
  const setc = "select set_config('request.jwt.claims','" + c + "', true);"

  console.log('=== registrar_compra (idempotencia M17/A11) ===')
  // Primera compra + segunda con el MISMO serie_numero → debe devolver reused=true.
  let sql = 'begin;' + setc +
    "select (registrar_compra('" + CO + "'::uuid, null, '01', 'FVAL-1', current_date, " +
    "'[{\"descripcion\":\"item val\",\"cantidad\":1,\"costo\":118}]'::jsonb))->>'id' as id1;" +
    "select (registrar_compra('" + CO + "'::uuid, null, '01', 'FVAL-1', current_date, " +
    "'[{\"descripcion\":\"item val\",\"cantidad\":1,\"costo\":118}]'::jsonb))->'reused' as reused2;" +
    'rollback;'
  console.log('res:', JSON.stringify(await q(sql)))

  console.log('\n=== registrar_abono (valida caja A12/A14: sesión falsa → debe FALLAR) ===')
  sql = 'begin;' + setc +
    "select registrar_abono('" + CO + "'::uuid, 10, " +
    "(select id from documents where company_id='" + CO + "' and serie='B001' and correlativo=7), " +
    "null, 'efectivo', null, gen_random_uuid());" +
    'rollback;'
  const ab = await q(sql)
  console.log('res:', JSON.stringify(ab).slice(0, 220))

  console.log('\n=== anular_documento (lock + conserva payments, sobre B001-7) ===')
  sql = 'begin;' + setc +
    "select anular_documento('" + CO + "'::uuid, " +
    "(select id from documents where company_id='" + CO + "' and serie='B001' and correlativo=7), 'Prueba validación');" +
    "select count(*) as pagos_conservados from payments where document_id=" +
    "(select id from documents where company_id='" + CO + "' and serie='B001' and correlativo=7);" +
    'rollback;'
  console.log('res:', JSON.stringify(await q(sql)))
}
main().catch((e) => console.error('ERR', e))
