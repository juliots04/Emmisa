import { describe, it, expect } from 'vitest'
import { numeroALetras } from './numeroALetras'

describe('numeroALetras (importe en letras SUNAT)', () => {
  it('usa la leyenda SON: ... CON XX/100 SOLES', () => {
    expect(numeroALetras(118)).toBe('SON: CIENTO DIECIOCHO CON 00/100 SOLES')
  })

  it('cero', () => {
    expect(numeroALetras(0)).toBe('SON: CERO CON 00/100 SOLES')
  })

  it('decimales (centavos)', () => {
    expect(numeroALetras(10.5)).toBe('SON: DIEZ CON 50/100 SOLES')
    expect(numeroALetras(0.9)).toBe('SON: CERO CON 90/100 SOLES')
    expect(numeroALetras(1.05)).toBe('SON: UNO CON 05/100 SOLES')
  })

  it('cien vs ciento', () => {
    expect(numeroALetras(100)).toContain('CIEN CON')
    expect(numeroALetras(101)).toContain('CIENTO UNO')
    expect(numeroALetras(200)).toContain('DOSCIENTOS')
  })

  it('decenas con Y y rango veinti-', () => {
    expect(numeroALetras(45)).toContain('CUARENTA Y CINCO')
    expect(numeroALetras(15)).toContain('QUINCE')
    expect(numeroALetras(21)).toContain('VEINTIUNO')
    expect(numeroALetras(30)).toContain('TREINTA')
  })

  it('miles y millones', () => {
    expect(numeroALetras(1000)).toContain('MIL CON')
    expect(numeroALetras(1500)).toContain('MIL QUINIENTOS')
    expect(numeroALetras(2000)).toContain('DOS MIL')
    expect(numeroALetras(1_000_000)).toContain('UN MILLÓN')
    expect(numeroALetras(2_000_000)).toContain('DOS MILLONES')
  })

  it('moneda USD', () => {
    expect(numeroALetras(50, 'USD')).toBe('SON: CINCUENTA CON 00/100 DÓLARES AMERICANOS')
  })

  it('acarreo de céntimos (fracción ≥ .995 no produce 100/100)', () => {
    expect(numeroALetras(1.995)).toBe('SON: DOS CON 00/100 SOLES')
    expect(numeroALetras(0.999)).toBe('SON: UNO CON 00/100 SOLES')
    expect(numeroALetras(118.995)).toBe('SON: CIENTO DIECINUEVE CON 00/100 SOLES')
  })
})
