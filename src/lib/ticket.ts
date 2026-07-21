// Impresión de ticket térmico (80mm) para el POS y reimpresión de comprobantes.
// Abre una ventana con el ticket y dispara print(); si el navegador bloquea el
// popup, no rompe la venta (se puede reimprimir desde el comprobante).
import type { DocumentRow } from '@/types'

export interface TicketLine {
  descripcion: string
  cantidad: number
  precioUnitario: number
}

export interface TicketData {
  empresa: { razon_social: string; ruc: string; direccion?: string | null }
  doc: Pick<DocumentRow, 'tipo_doc' | 'serie' | 'correlativo' | 'total' | 'total_gravado' | 'total_igv' | 'fecha_emision' | 'codigo_qr' | 'hash'>
  cliente: { denominacion: string; numDoc?: string | null }
  lines: TicketLine[]
  formaPago?: string
  efectivo?: number | null
  vuelto?: number | null
}

const TIPO_LABEL: Record<string, string> = {
  '01': 'FACTURA ELECTRÓNICA',
  '03': 'BOLETA DE VENTA ELECTRÓNICA',
  '07': 'NOTA DE CRÉDITO ELECTRÓNICA',
  '08': 'NOTA DE DÉBITO ELECTRÓNICA',
}

function esc(s: string): string {
  return String(s).replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c] as string)
}
function money(n: number): string {
  return Number(n || 0).toFixed(2)
}

export function ticketHtml(d: TicketData): string {
  const numero = `${d.doc.serie}-${String(d.doc.correlativo).padStart(8, '0')}`
  const rows = d.lines
    .map((l) => {
      const total = money(l.cantidad * l.precioUnitario)
      return `<tr><td class="l">${esc(l.descripcion)}<br><span class="s">${l.cantidad} x ${money(l.precioUnitario)}</span></td><td class="r">${total}</td></tr>`
    })
    .join('')
  return `<!doctype html><html><head><meta charset="utf-8"><title>${numero}</title>
<style>
  @page { size: 80mm auto; margin: 0; }
  * { font-family: 'Courier New', monospace; }
  body { width: 80mm; margin: 0; padding: 6px 8px; color: #000; font-size: 12px; }
  .c { text-align: center; }
  .b { font-weight: bold; }
  .s { font-size: 10px; color: #333; }
  hr { border: none; border-top: 1px dashed #000; margin: 6px 0; }
  table { width: 100%; border-collapse: collapse; }
  td.l { text-align: left; padding: 2px 0; }
  td.r { text-align: right; padding: 2px 0; white-space: nowrap; }
  .tot td { padding: 1px 0; }
  .big { font-size: 15px; font-weight: bold; }
</style></head><body>
  <div class="c b">${esc(d.empresa.razon_social)}</div>
  <div class="c">RUC ${esc(d.empresa.ruc)}</div>
  ${d.empresa.direccion ? `<div class="c s">${esc(d.empresa.direccion)}</div>` : ''}
  <hr>
  <div class="c b">${TIPO_LABEL[d.doc.tipo_doc] ?? 'COMPROBANTE'}</div>
  <div class="c b">${numero}</div>
  <div class="s">Fecha: ${esc(d.doc.fecha_emision ?? '')}</div>
  <div class="s">Cliente: ${esc(d.cliente.denominacion)}${d.cliente.numDoc ? ' · ' + esc(d.cliente.numDoc) : ''}</div>
  <hr>
  <table>${rows}</table>
  <hr>
  <table class="tot">
    <tr><td class="l">Op. Gravada</td><td class="r">S/ ${money(d.doc.total_gravado)}</td></tr>
    <tr><td class="l">IGV (18%)</td><td class="r">S/ ${money(d.doc.total_igv)}</td></tr>
    <tr><td class="l big">TOTAL</td><td class="r big">S/ ${money(d.doc.total)}</td></tr>
    ${d.formaPago ? `<tr><td class="l">Pago</td><td class="r">${esc(d.formaPago)}</td></tr>` : ''}
    ${d.efectivo ? `<tr><td class="l">Recibido</td><td class="r">S/ ${money(d.efectivo)}</td></tr>` : ''}
    ${d.vuelto != null && d.vuelto > 0 ? `<tr><td class="l">Vuelto</td><td class="r">S/ ${money(d.vuelto)}</td></tr>` : ''}
  </table>
  <hr>
  ${d.doc.codigo_qr ? `<div class="c s" style="word-break:break-all">${esc(d.doc.codigo_qr)}</div>` : ''}
  ${d.doc.hash ? `<div class="c s">Hash: ${esc(d.doc.hash)}</div>` : ''}
  <div class="c s">Representación impresa del comprobante electrónico</div>
  <div class="c s">¡Gracias por su compra!</div>
</body></html>`
}

export function printTicket(d: TicketData): void {
  try {
    const w = window.open('', '_blank', 'width=380,height=640')
    if (!w) return
    w.document.write(ticketHtml(d))
    w.document.close()
    w.focus()
    // Espera breve a que renderice antes de imprimir.
    setTimeout(() => {
      w.print()
    }, 250)
  } catch {
    /* impresión best-effort: nunca bloquea la venta */
  }
}
