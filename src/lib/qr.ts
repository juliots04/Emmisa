import qrcode from 'qrcode-generator'

// Genera un código QR ESCANEABLE a partir del texto (el `codigo_qr` que devuelve
// el PSE con el formato SUNAT). qrcode-generator es síncrono y sin dependencias,
// ideal para incrustarlo tanto en la vista previa como en el HTML del ticket.

/** Data URL (GIF) de un QR, listo para <img :src>. cell = px por módulo. */
export function qrDataUrl(text: string, cell = 3, margin = 2): string {
  if (!text) return ''
  try {
    const qr = qrcode(0, 'M') // typeNumber auto · corrección de errores M
    qr.addData(text)
    qr.make()
    return qr.createDataURL(cell, margin)
  } catch {
    return ''
  }
}
