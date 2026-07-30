// ============================================================
// Reglas de validación reutilizables (coherentes en toda la app).
// Uso doble:
//   1) En el template, para feedback en vivo:  :rules="priceRules"
//   2) En el handler, como guarda antes de guardar:
//        const err = validate([[precio.value, priceRules]])
//        if (err) return notifyWarn(err)
// Cada regla es una función (val) => true | string(mensaje de error),
// compatible con la prop :rules de los campos de Quasar.
// ============================================================

export type Rule = (val: unknown) => true | string

function isEmpty(v: unknown): boolean {
  return v === null || v === undefined || (typeof v === 'string' && v.trim() === '')
}

/* ---------------- Reglas base ---------------- */

export const required =
  (msg = 'Campo obligatorio'): Rule =>
  (v) =>
    !isEmpty(v) || msg

/** Número presente y válido (no vacío, no NaN). */
export const requiredNum =
  (msg = 'Ingresa un número'): Rule =>
  (v) =>
    (!isEmpty(v) && !Number.isNaN(Number(v))) || msg

/** Estrictamente mayor que 0. */
export const positive =
  (msg = 'Debe ser mayor que 0'): Rule =>
  (v) =>
    (!isEmpty(v) && Number(v) > 0) || msg

/** Mayor o igual a 0 (rechaza negativos; permite vacío). */
export const nonNegative =
  (msg = 'No puede ser negativo'): Rule =>
  (v) =>
    isEmpty(v) || Number(v) >= 0 || msg

export const minVal =
  (n: number, msg?: string): Rule =>
  (v) =>
    (!isEmpty(v) && Number(v) >= n) || (msg ?? `Debe ser ≥ ${n}`)

export const maxVal =
  (n: number, msg?: string): Rule =>
  (v) =>
    isEmpty(v) || Number(v) <= n || (msg ?? `Debe ser ≤ ${n}`)

export const maxLen =
  (n: number, msg?: string): Rule =>
  (v) =>
    isEmpty(v) || String(v).length <= n || (msg ?? `Máximo ${n} caracteres`)

export const exactLen =
  (n: number, msg?: string): Rule =>
  (v) =>
    String(v ?? '').length === n || (msg ?? `Debe tener ${n} caracteres`)

export const onlyDigits =
  (msg = 'Solo se permiten números'): Rule =>
  (v) =>
    isEmpty(v) || /^\d+$/.test(String(v)) || msg

/* ---------------- Reglas de dominio (Perú / SUNAT) ---------------- */

/** RUC peruano: 11 dígitos, prefijo válido y dígito verificador (módulo 11). */
export function isValidRuc(ruc: string): boolean {
  if (!/^\d{11}$/.test(ruc)) return false
  // Prefijos de RUC válidos en Perú: 10 (persona natural), 15/16/17 (transición/no
   // domiciliados), 20 (persona jurídica). Antes faltaba el 16 → rechazaba RUC legítimos.
  if (!['10', '15', '16', '17', '20'].includes(ruc.slice(0, 2))) return false
  const weights = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2]
  let sum = 0
  for (let i = 0; i < 10; i++) sum += Number(ruc[i]) * weights[i]
  let check = 11 - (sum % 11)
  if (check === 10) check = 0
  if (check === 11) check = 1
  return check === Number(ruc[10])
}

export const ruc: Rule = (v) => isValidRuc(String(v ?? '')) || 'RUC inválido (11 dígitos)'

export const dni: Rule = (v) => /^\d{8}$/.test(String(v ?? '')) || 'DNI inválido (8 dígitos)'

export const email =
  (msg = 'Correo electrónico inválido'): Rule =>
  (v) =>
    isEmpty(v) || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(v)) || msg

/** Documento de identidad según tipo SUNAT (catálogo 06): 1=DNI, 6=RUC. */
export function docByTipo(tipo: string, requerido = false): Rule {
  return (v) => {
    if (isEmpty(v)) return requerido ? 'Documento obligatorio' : true
    if (tipo === '6') return ruc(v)
    if (tipo === '1') return dni(v)
    return /^\d+$/.test(String(v)) || 'Documento inválido'
  }
}

/* ---------------- Conjuntos listos por tipo de campo ---------------- */

export const nameRules: Rule[] = [required(), maxLen(200)]
export const priceRules: Rule[] = [requiredNum(), positive('El precio debe ser mayor que 0')]
export const costRules: Rule[] = [nonNegative('El costo no puede ser negativo')]
export const qtyRules: Rule[] = [requiredNum(), positive('La cantidad debe ser mayor que 0')]
export const stockMinRules: Rule[] = [nonNegative()]
export const rucRules: Rule[] = [required('RUC obligatorio'), ruc]
export const dniRules: Rule[] = [dni]
export const emailRules: Rule[] = [email()]
/** Monto de dinero que debe ser positivo (movimientos, apertura de caja). */
export const montoRules: Rule[] = [requiredNum(), positive('El monto debe ser mayor que 0')]
/** Monto que puede ser 0 pero no negativo (p. ej. monto final de cierre). */
export const montoCeroRules: Rule[] = [requiredNum(), nonNegative()]

/* ---------------- Utilidades para handlers ---------------- */

/** Devuelve el primer mensaje de error de una lista de reglas, o null si todo pasa. */
export function firstError(val: unknown, rules: Rule[]): string | null {
  for (const r of rules) {
    const res = r(val)
    if (res !== true) return res
  }
  return null
}

/**
 * Valida varios campos [valor, reglas] y devuelve el primer error, o null.
 * Pensado como guarda al inicio de un handler de guardado:
 *   const err = validate([[nombre.value, nameRules], [precio.value, priceRules]])
 *   if (err) { notify.warning(err); return }
 */
export function validate(fields: Array<[unknown, Rule[]]>): string | null {
  for (const [val, rules] of fields) {
    const err = firstError(val, rules)
    if (err) return err
  }
  return null
}
