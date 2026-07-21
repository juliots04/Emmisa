// Cálculo de impuestos (IGV). Función pura -> fácil de testear.
// En Perú el precio de venta normalmente INCLUYE el IGV (18%).

export const IGV_RATE = 0.18

export function round2(n: number): number {
  return Math.round((n + Number.EPSILON) * 100) / 100
}

export interface LineInput {
  cantidad: number
  precioUnitario: number // precio con IGV incluido
}

export interface LineTotals {
  total: number // precio total (con IGV)
  gravado: number // valor de venta (sin IGV)
  igv: number
}

export function computeLine(line: LineInput): LineTotals {
  const total = round2(line.cantidad * line.precioUnitario)
  const gravado = round2(total / (1 + IGV_RATE))
  const igv = round2(total - gravado)
  return { total, gravado, igv }
}

export interface Totals {
  gravado: number
  igv: number
  total: number
}

export function computeTotals(lines: LineInput[]): Totals {
  return lines.reduce<Totals>(
    (acc, line) => {
      const { total, gravado, igv } = computeLine(line)
      return {
        gravado: round2(acc.gravado + gravado),
        igv: round2(acc.igv + igv),
        total: round2(acc.total + total),
      }
    },
    { gravado: 0, igv: 0, total: 0 },
  )
}
