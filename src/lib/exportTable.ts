import type { QTableColumn } from 'quasar'

// Columnas puramente visuales (acciones, thumbnails, popovers) que no aportan al export.
const SKIP_COLS = new Set(['acciones', 'accion', 'imagen', 'avatar', 'historial', 'stock_extra', 'menu'])

// Neutraliza inyección de fórmulas en Excel (=, +, -, @ al inicio se ejecutarían como
// fórmula al abrir el archivo) y escapa entidades HTML de la tabla que Excel interpreta.
function safeCell(v: unknown): string {
  let s = String(v ?? '')
  if (/^[=+\-@\t\r]/.test(s) && isNaN(Number(s))) s = "'" + s
  return s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c] as string)
}

function cellValue(col: QTableColumn, row: unknown): unknown {
  const raw =
    typeof col.field === 'function'
      ? col.field(row)
      : (row as Record<string, unknown>)[col.field as string]
  return col.format ? col.format(raw, row) : raw
}

/**
 * Exporta las filas visibles de una q-table a un .xls (HTML-table) abrible por
 * Excel/Sheets. Reutiliza la definición de columnas de la página (label + field +
 * format) para reflejar exactamente lo que ve el usuario. Se omiten columnas sin
 * etiqueta y las puramente visuales (acciones, imagen, etc.).
 */
export function exportTableXls(baseName: string, columns: QTableColumn[], rows: readonly unknown[]): void {
  const cols = columns.filter(
    (c) => !!c.label && String(c.label).trim() !== '' && !SKIP_COLS.has(c.name),
  )
  const thead = cols.map((c) => `<th>${safeCell(c.label)}</th>`).join('')
  const trs = rows
    .map((r) => `<tr>${cols.map((c) => `<td>${safeCell(cellValue(c, r))}</td>`).join('')}</tr>`)
    .join('')
  const html =
    '<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel">' +
    '<head><meta charset="utf-8"></head><body><table border="1"><thead><tr>' +
    thead +
    '</tr></thead><tbody>' +
    trs +
    '</tbody></table></body></html>'
  const blob = new Blob(['﻿' + html], { type: 'application/vnd.ms-excel' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `${baseName}-${new Date().toISOString().slice(0, 10)}.xls`
  a.click()
  URL.revokeObjectURL(url)
}
