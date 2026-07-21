import { describe, it, expect } from 'vitest'
import { computeLine, computeTotals } from './tax'

describe('tax (IGV)', () => {
  it('descompone el IGV de un precio con IGV incluido', () => {
    const r = computeLine({ cantidad: 1, precioUnitario: 118 })
    expect(r.total).toBe(118)
    expect(r.gravado).toBe(100)
    expect(r.igv).toBe(18)
  })

  it('multiplica por cantidad', () => {
    const r = computeLine({ cantidad: 2, precioUnitario: 118 })
    expect(r.total).toBe(236)
    expect(r.gravado).toBe(200)
    expect(r.igv).toBe(36)
  })

  it('suma varios ítems', () => {
    const t = computeTotals([
      { cantidad: 2, precioUnitario: 118 },
      { cantidad: 1, precioUnitario: 59 },
    ])
    expect(t.total).toBe(295)
    expect(t.gravado).toBe(250)
    expect(t.igv).toBe(45)
  })
})
