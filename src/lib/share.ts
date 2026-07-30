import type { DocumentRow } from '@/types'

const TIPO_NOMBRE: Record<string, string> = {
  '01': 'Factura',
  '03': 'Boleta',
  '07': 'Nota de crédito',
  '08': 'Nota de débito',
}

type ShareDoc = Pick<DocumentRow, 'tipo_doc' | 'serie' | 'correlativo' | 'total' | 'moneda' | 'pdf_url'>

function numero(doc: Pick<DocumentRow, 'serie' | 'correlativo'>): string {
  return `${doc.serie}-${String(doc.correlativo).padStart(8, '0')}`
}

/** Construye el mensaje de WhatsApp para enviar un comprobante al cliente. */
export function whatsappMensaje(empresa: string, doc: ShareDoc, pdfUrl?: string | null): string {
  const simbolo = doc.moneda === 'USD' ? 'US$' : 'S/'
  const tipo = TIPO_NOMBRE[doc.tipo_doc] ?? 'Comprobante'
  const lineas = [
    `Hola 👋, gracias por tu compra en *${empresa}*.`,
    `Aquí está tu ${tipo} *${numero(doc)}* por ${simbolo} ${Number(doc.total || 0).toFixed(2)}.`,
  ]
  const url = pdfUrl ?? doc.pdf_url
  if (url) lineas.push(`Descárgala aquí: ${url}`)
  return lineas.join('\n')
}

/**
 * Abre WhatsApp (app o web) con el mensaje del comprobante listo para enviar.
 * Sin claves ni cuentas: usa el enlace universal wa.me.
 * `telefono` opcional (solo dígitos con código país); si se omite, el usuario
 * elige el contacto en WhatsApp.
 */
export function compartirWhatsApp(empresa: string, doc: ShareDoc, opts?: { pdfUrl?: string | null; telefono?: string | null }): void {
  const texto = encodeURIComponent(whatsappMensaje(empresa, doc, opts?.pdfUrl))
  const tel = (opts?.telefono ?? '').replace(/\D/g, '')
  const url = tel ? `https://wa.me/${tel}?text=${texto}` : `https://wa.me/?text=${texto}`
  try {
    window.open(url, '_blank', 'noopener')
  } catch {
    /* best-effort: nunca bloquea el flujo */
  }
}
