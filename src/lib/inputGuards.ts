/**
 * Guards globales para <input type="number"> en toda la app.
 *
 * Impide INGRESAR números negativos (y notación científica) en cualquier campo
 * numérico: bloquea las teclas -, +, e/E y limpia el signo si se pega texto.
 * Se instala una sola vez en el arranque (main.ts) y aplica a todos los campos,
 * presentes y futuros, porque escucha en el documento en fase de captura.
 */
export function installNumberInputGuards(): void {
  // 1) Bloquea las teclas que producen valores negativos / científicos.
  document.addEventListener(
    'keydown',
    (e) => {
      const el = e.target
      if (el instanceof HTMLInputElement && el.type === 'number') {
        if (e.key === '-' || e.key === '+' || e.key === 'e' || e.key === 'E') {
          e.preventDefault()
        }
      }
    },
    true,
  )

  // 2) Red de seguridad para pegado/arrastre: quita cualquier signo negativo.
  document.addEventListener(
    'input',
    (e) => {
      const el = e.target
      if (el instanceof HTMLInputElement && el.type === 'number' && el.value.includes('-')) {
        el.value = el.value.replace(/-/g, '')
        // Re-emite el evento para que el v-model de Vue/Quasar tome el valor limpio.
        el.dispatchEvent(new Event('input', { bubbles: true }))
      }
    },
    true,
  )
}
