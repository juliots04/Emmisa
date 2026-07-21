// Sonda de solo-lectura del estado real de la BD. NO imprime secretos.
// Uso: node scripts/probe-db.mjs
import { readFileSync } from 'node:fs'

function loadEnv(path) {
  const env = {}
  for (const line of readFileSync(path, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^([A-Z0-9_]+)=(.*)$/)
    if (m) env[m[1]] = m[2].replace(/^["']|["']$/g, '')
  }
  return env
}

const env = loadEnv(new URL('../.env', import.meta.url))
const URL_ = env.VITE_SUPABASE_URL
const KEY = env.SUPABASE_SERVICE_ROLE_KEY
if (!URL_ || !KEY) {
  console.error('Faltan VITE_SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY')
  process.exit(1)
}
const H = { apikey: KEY, Authorization: `Bearer ${KEY}` }

async function main() {
  // 1) Esquema vía OpenAPI de PostgREST
  const specRes = await fetch(`${URL_}/rest/v1/`, { headers: { ...H, Accept: 'application/openapi+json' } })
  const spec = await specRes.json()
  const defs = spec.definitions || {}
  const tables = Object.keys(defs).sort()
  console.log('==================== ESQUEMA VIVO (PostgREST) ====================')
  console.log(`Tablas expuestas: ${tables.length}\n`)
  for (const t of tables) {
    const props = defs[t].properties || {}
    const cols = Object.entries(props).map(([name, p]) => {
      const pk = /Primary Key/i.test(p.description || '') ? ' PK' : ''
      const fk = (p.description || '').match(/foreign key to ([^`]+)/i)
      return `${name}:${p.format || p.type}${pk}${fk ? ' ->' + fk[1] : ''}`
    })
    console.log(`### ${t}\n  ${cols.join('\n  ')}`)
  }

  // 2) Conteo de filas por tabla (Prefer count)
  console.log('\n==================== CONTEO DE FILAS ====================')
  for (const t of tables) {
    try {
      const r = await fetch(`${URL_}/rest/v1/${t}?select=*&limit=1`, { headers: { ...H, Prefer: 'count=exact', Range: '0-0' } })
      const cr = r.headers.get('content-range') || '?'
      const total = cr.includes('/') ? cr.split('/')[1] : '?'
      console.log(`${t.padEnd(24)} ${total}`)
    } catch (e) {
      console.log(`${t.padEnd(24)} ERROR ${e.message}`)
    }
  }

  // 3) Muestras de tablas núcleo (sin datos sensibles)
  console.log('\n==================== MUESTRAS NUCLEO ====================')
  const sampleTables = ['companies', 'series', 'products', 'documents', 'memberships', 'establishments', 'customers', 'cash_sessions']
  for (const t of sampleTables) {
    if (!tables.includes(t)) { console.log(`\n### ${t}: (no existe)`); continue }
    const r = await fetch(`${URL_}/rest/v1/${t}?select=*&limit=3`, { headers: H })
    const rows = await r.json()
    console.log(`\n### ${t} (muestra ${Array.isArray(rows) ? rows.length : 0}):`)
    console.log(JSON.stringify(rows, null, 1))
  }
}
main().catch((e) => { console.error('FALLO:', e.message); process.exit(1) })
