import { describe, it, expect } from 'vitest'
import { pleRegistroVentas, pleRegistroCompras, type PurchasePle } from './ple'
import type { DocumentRow } from '@/types'

function doc(p: Partial<DocumentRow>): DocumentRow {
  return {
    id: 'x',
    company_id: 'c',
    customer_id: null,
    tipo_doc: '03',
    serie: 'B001',
    correlativo: 1,
    moneda: 'PEN',
    total_gravado: 0,
    total_igv: 0,
    total: 0,
    estado_sunat: 'aceptado',
    cdr: null,
    pdf_url: null,
    created_at: '2026-07-15T10:00:00Z',
    fecha_emision: '2026-07-15',
    ...p,
  } as DocumentRow
}

describe('PLE · Registro de Ventas (14.1)', () => {
  it('genera 35 campos con el formato correcto', () => {
    const docs = [
      doc({
        tipo_doc: '03',
        serie: 'B001',
        correlativo: 5,
        total_gravado: 100,
        total_igv: 18,
        total: 118,
        receptor_tipo_doc: '1',
        receptor_num_doc: '12345678',
        receptor_denominacion: 'JUAN PEREZ',
      }),
    ]
    const file = pleRegistroVentas(docs, '2026-07', '20123456789')
    const lines = file.content.trim().split('\r\n')
    expect(lines).toHaveLength(1)

    const parts = lines[0].split('|')
    expect(parts).toHaveLength(36) // 35 campos + '' final por el '|' de cierre
    const f = parts

    expect(f[0]).toBe('20260700') // periodo AAAAMM00
    expect(f[3]).toBe('15/07/2026') // fecha emisión DD/MM/AAAA
    expect(f[5]).toBe('03') // tipo comprobante
    expect(f[6]).toBe('B001') // serie
    expect(f[7]).toBe('5') // número
    expect(f[9]).toBe('1') // tipo doc cliente (DNI)
    expect(f[10]).toBe('12345678') // número doc cliente
    expect(f[13]).toBe('100.00') // base imponible gravada
    expect(f[15]).toBe('18.00') // IGV
    expect(f[24]).toBe('118.00') // importe total
    expect(f[25]).toBe('PEN') // moneda
    expect(f[34]).toBe('1') // estado (anotación oportuna)

    expect(file.filename.startsWith('LE20123456789')).toBe(true)
    expect(file.filename).toContain('140100') // libro Registro de Ventas
    expect(file.filename.endsWith('.txt')).toBe(true)
  })

  it('registra las notas de crédito (07) en NEGATIVO', () => {
    const docs = [doc({ tipo_doc: '07', total_gravado: 50, total_igv: 9, total: 59 })]
    const f = pleRegistroVentas(docs, '2026-07', '20123456789').content.trim().split('|')
    expect(f[13]).toBe('-50.00') // base gravada negativa
    expect(f[15]).toBe('-9.00') // IGV negativo
    expect(f[24]).toBe('-59.00') // total negativo
  })

  it('excluye SOLO los rechazados; anulados van con Estado=3 (sin saltos de correlativo)', () => {
    const docs = [
      doc({ correlativo: 1, estado_sunat: 'aceptado' }),
      doc({ correlativo: 2, estado_sunat: 'anulado' }),
      doc({ correlativo: 3, estado_sunat: 'rechazado' }),
    ]
    const file = pleRegistroVentas(docs, '2026-07', '20123456789')
    const lines = file.content.trim().split('\r\n')
    // El rechazado se excluye (nunca fue válido); aceptado y anulado sí se registran.
    expect(lines).toHaveLength(2)
    const anulado = lines.find((l) => l.split('|')[7] === '2')!
    expect(anulado.split('|')[34]).toBe('3') // Estado 3 = anulado
    const aceptado = lines.find((l) => l.split('|')[7] === '1')!
    expect(aceptado.split('|')[34]).toBe('1') // Estado 1 = anotación oportuna
    expect(file.filename).toContain('140100')
  })
})

describe('PLE · Registro de Compras (8.1)', () => {
  it('genera 36 campos y el libro 080100', () => {
    const compras: PurchasePle[] = [
      {
        fecha: '2026-07-10',
        tipo_doc: '01',
        serie_numero: 'F001-123',
        total: 118,
        total_gravado: 100,
        total_igv: 18,
        moneda: 'PEN',
        tipo_cambio: 1,
        proveedor_ruc: '20777777777',
        proveedor_nombre: 'DISTRIBUIDORA SAC',
      },
    ]
    const file = pleRegistroCompras(compras, '2026-07', '20123456789')
    const parts = file.content.trim().split('|')
    expect(parts).toHaveLength(37) // 36 campos + '' final

    const f = parts
    expect(f[0]).toBe('20260700') // periodo
    expect(f[3]).toBe('10/07/2026') // fecha emisión
    expect(f[5]).toBe('01') // tipo comprobante
    expect(f[6]).toBe('F001') // serie
    expect(f[8]).toBe('123') // número
    expect(f[9]).toBe('6') // tipo doc proveedor (RUC)
    expect(f[10]).toBe('20777777777') // número doc proveedor
    expect(f[12]).toBe('100.00') // base imponible
    expect(f[13]).toBe('18.00') // IGV
    expect(f[22]).toBe('118.00') // importe total
    expect(f[35]).toBe('1') // estado

    expect(file.filename).toContain('080100') // libro Registro de Compras
  })
})
