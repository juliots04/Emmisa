// Importe en letras para la representación impresa del comprobante (obligatorio SUNAT).
// Devuelve la leyenda estándar: "SON: <letras> CON XX/100 <MONEDA>".

const UNI = [
  '', 'UNO', 'DOS', 'TRES', 'CUATRO', 'CINCO', 'SEIS', 'SIETE', 'OCHO', 'NUEVE',
  'DIEZ', 'ONCE', 'DOCE', 'TRECE', 'CATORCE', 'QUINCE', 'DIECISÉIS', 'DIECISIETE', 'DIECIOCHO', 'DIECINUEVE',
  'VEINTE', 'VEINTIUNO', 'VEINTIDÓS', 'VEINTITRÉS', 'VEINTICUATRO', 'VEINTICINCO', 'VEINTISÉIS', 'VEINTISIETE', 'VEINTIOCHO', 'VEINTINUEVE',
]
const DECENAS = ['', '', '', 'TREINTA', 'CUARENTA', 'CINCUENTA', 'SESENTA', 'SETENTA', 'OCHENTA', 'NOVENTA']
const CENTENAS = ['', 'CIENTO', 'DOSCIENTOS', 'TRESCIENTOS', 'CUATROCIENTOS', 'QUINIENTOS', 'SEISCIENTOS', 'SETECIENTOS', 'OCHOCIENTOS', 'NOVECIENTOS']

// 0..999
function centena(n: number): string {
  if (n === 100) return 'CIEN'
  let out = ''
  const c = Math.floor(n / 100)
  const resto = n % 100
  if (c) out += CENTENAS[c] + ' '
  if (resto <= 29) out += UNI[resto]
  else {
    const d = Math.floor(resto / 10)
    const u = resto % 10
    out += DECENAS[d]
    if (u) out += ' Y ' + UNI[u]
  }
  return out.trim()
}

// 0..999999
function miles(n: number): string {
  if (n < 1000) return centena(n)
  const m = Math.floor(n / 1000)
  const resto = n % 1000
  let out = m === 1 ? 'MIL' : centena(m) + ' MIL'
  if (resto) out += ' ' + centena(resto)
  return out.trim()
}

// 0..999_999_999
function millones(n: number): string {
  if (n < 1_000_000) return miles(n)
  const mm = Math.floor(n / 1_000_000)
  const resto = n % 1_000_000
  let out = mm === 1 ? 'UN MILLÓN' : miles(mm) + ' MILLONES'
  if (resto) out += ' ' + miles(resto)
  return out.trim()
}

export function numeroALetras(monto: number, moneda = 'PEN'): string {
  const abs = Math.abs(Number(monto) || 0)
  // Trabajar en céntimos enteros para que el redondeo ACARREE al entero
  // (antes: 1.995 → "UNO CON 100/100"; ahora → "DOS CON 00/100").
  const cents = Math.round(abs * 100)
  const entero = Math.floor(cents / 100)
  const centavos = cents % 100
  const letras = entero === 0 ? 'CERO' : millones(entero)
  const unidad = moneda === 'USD' ? 'DÓLARES AMERICANOS' : 'SOLES'
  return `SON: ${letras} CON ${String(centavos).padStart(2, '0')}/100 ${unidad}`
}
