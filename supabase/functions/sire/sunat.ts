// Cliente de la API SIRE de SUNAT (RVIE ventas + RCE compras).
// Autenticación OAuth2 (api-seguridad) + servicios REST (api-sire). El navegador NO
// puede llamarlos (CORS), por eso todo va por esta Edge Function server-side.
//
// ⚠️ Los endpoints siguen los manuales oficiales de SUNAT (Servicios Web API SIRE
// Ventas/Compras). Al no existir modo de prueba, se VALIDAN con un RUC real; si alguno
// cambió de ruta, se ajusta aquí en un solo lugar.

const SEG_BASE = 'https://api-seguridad.sunat.gob.pe/v1/clientessol'
const SIRE_BASE = 'https://api-sire.sunat.gob.pe/v1/contribuyente/migeigv/libros'
const SCOPE = 'https://api-sire.sunat.gob.pe'

export interface SireCred {
  client_id: string
  client_secret: string
  sol_usuario: string
  sol_clave: string
}

async function fetchTimeout(url: string, opts: RequestInit = {}, ms = 30000): Promise<Response> {
  const ctrl = new AbortController()
  const t = setTimeout(() => ctrl.abort(), ms)
  try {
    return await fetch(url, { ...opts, signal: ctrl.signal })
  } finally {
    clearTimeout(t)
  }
}

/** Token OAuth2 (grant_type=password). username = RUC + usuario SOL. */
export async function getToken(cred: SireCred, ruc: string): Promise<string> {
  const body = new URLSearchParams({
    grant_type: 'password',
    scope: SCOPE,
    client_id: cred.client_id,
    client_secret: cred.client_secret,
    username: `${ruc}${cred.sol_usuario}`,
    password: cred.sol_clave,
  })
  const res = await fetchTimeout(`${SEG_BASE}/${cred.client_id}/oauth2/token/`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  })
  const j = await res.json().catch(() => ({}))
  if (!j.access_token) {
    throw new Error(
      j.error_description || j.error || j.message ||
        'No se pudo autenticar con SUNAT. Revisa client_id, client_secret, usuario y clave SOL.',
    )
  }
  return j.access_token as string
}

const modulo = (tipo: string) => (tipo === 'RCE' ? 'rce' : 'rvie')

/**
 * Solicita la exportación de la PROPUESTA del periodo (AAAAMM). SUNAT responde con un
 * numTicket; el archivo se descarga después consultando ese ticket.
 */
export async function solicitarPropuesta(token: string, tipo: string, periodo: string): Promise<string> {
  // periodo va en el PATH: validar estrictamente AAAAMM evita inyección de ruta/query.
  if (!/^\d{6}$/.test(periodo)) throw new Error('Periodo inválido (debe ser AAAAMM)')
  const url = `${SIRE_BASE}/${modulo(tipo)}/propuesta/web/propuesta/${periodo}/exportapropuesta?codTipoArchivo=0`
  const res = await fetchTimeout(url, { headers: { Authorization: `Bearer ${token}` } })
  const j = await res.json().catch(() => ({}))
  const ticket = j.numTicket ?? j.num_ticket ?? j.ticket
  if (!ticket) {
    throw new Error(j.mensaje ?? j.msg ?? j.error ?? `SUNAT no devolvió ticket (HTTP ${res.status})`)
  }
  return String(ticket)
}

/**
 * ACEPTA/REGISTRA la propuesta del periodo como el registro definitivo (RVIE/RCE).
 * SUNAT responde con un numTicket; el resultado se consulta luego con ese ticket.
 * ⚠️ El endpoint/cuerpo exactos se validan con un RUC real (no hay sandbox SUNAT). Si
 * cambian, se ajustan aquí en un solo lugar.
 */
export async function aceptarPropuesta(token: string, tipo: string, periodo: string): Promise<string> {
  const url = `${SIRE_BASE}/${modulo(tipo)}/propuesta/web/propuesta/${periodo}/registrarpreliminar`
  const res = await fetchTimeout(url, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ perTributario: periodo, indAceptaPropuesta: true }),
  })
  const j = await res.json().catch(() => ({}))
  const ticket = j.numTicket ?? j.num_ticket ?? j.ticket
  if (!ticket) {
    throw new Error(j.mensaje ?? j.msg ?? j.error ?? `SUNAT no devolvió ticket al aceptar (HTTP ${res.status})`)
  }
  return String(ticket)
}

/** Consulta el estado de un ticket (procesando/terminado) y, si aplica, el archivo. */
export async function consultarTicket(token: string, tipo: string, numTicket: string): Promise<{
  estado: string
  archivoUrl?: string
  resumen?: unknown
  raw?: unknown
}> {
  const url = `${SIRE_BASE}/${modulo(tipo)}/ticket/web/ticket/consultaestadotickets?numTicket=${encodeURIComponent(numTicket)}`
  const res = await fetchTimeout(url, { headers: { Authorization: `Bearer ${token}` } })
  const j = await res.json().catch(() => ({}))
  // Estructura típica: { registros: [{ codEstadoTicket, ... , archivoReporte:[{ nomArchivoReporte, ... }] }] }
  const reg = Array.isArray(j?.registros) ? j.registros[0] : j
  const cod = String(reg?.codEstadoTicket ?? reg?.estado ?? '').toUpperCase()
  // 06 = terminado/procesado (según manual). Cualquier otro → procesando.
  const terminado = cod === '06' || cod === 'TERMINADO' || cod === 'PROCESADO'
  const nomArchivo = reg?.archivoReporte?.[0]?.nomArchivoReporte
  return {
    estado: terminado ? 'terminado' : 'procesando',
    archivoUrl: nomArchivo,
    resumen: reg,
    raw: j,
  }
}
