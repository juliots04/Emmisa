// ============================================================
// Barra de scroll horizontal ARRIBA de cada tabla (global y 100% personalizada).
//
// No usamos la barra nativa (ni la de Quasar ni un `overflow:auto`): esas traen
// flechas/botones y espacios en los extremos que no se pueden quitar de forma
// fiable en todos los navegadores. En su lugar dibujamos NOSOTROS la barra:
// una pista (`.k-topscroll`) con un thumb arrastrable (`.k-topscroll-thumb`),
// sincronizada con el desplazamiento del cuerpo de la tabla.
//   · sin flechas   · sin espacios/padding   · thumb a todo el alto   · redondeada
//
// Es global y automática: engancha cada `.q-table__middle` (el contenedor
// scrolleable de Quasar) según se monta, también al cambiar de ruta
// (MutationObserver). Solo se ve cuando la tabla desborda a lo ancho.
// ============================================================

const MIN_THUMB = 44 // px, ancho mínimo del thumb para que siempre sea fácil de agarrar

function enhance(middle: HTMLElement): void {
  if (middle.dataset.ktopscroll) return
  middle.dataset.ktopscroll = '1'

  const parent = middle.parentElement
  if (!parent) return

  // Evita una barra huérfana si Quasar recreó el contenedor.
  const prev = middle.previousElementSibling
  if (prev && prev.classList.contains('k-topscroll')) prev.remove()

  const track = document.createElement('div')
  track.className = 'k-topscroll'
  const thumb = document.createElement('div')
  thumb.className = 'k-topscroll-thumb'
  track.appendChild(thumb)
  parent.insertBefore(track, middle)

  const thumbWidth = (): number => {
    const sw = middle.scrollWidth
    return Math.max(MIN_THUMB, (middle.clientWidth / sw) * track.clientWidth)
  }

  // Recoloca el thumb según el scroll de la tabla y muestra/oculta la barra.
  const update = (): void => {
    const sw = middle.scrollWidth
    const cw = middle.clientWidth
    const overflow = sw > cw + 1
    const maxScroll = sw - cw
    // Cuando hay barra arriba, la tabla lleva las esquinas superiores cuadradas
    // (para que la barra quede integrada, no "flotando" sobre esquinas redondeadas).
    parent.classList.toggle('k-has-topscroll', overflow)
    if (!overflow) {
      track.style.display = 'none'
      return
    }
    track.style.display = 'block'
    const tw = thumbWidth()
    const maxLeft = track.clientWidth - tw
    const left = maxScroll > 0 ? (middle.scrollLeft / maxScroll) * maxLeft : 0
    thumb.style.width = tw + 'px'
    thumb.style.transform = `translateX(${left}px)`
  }

  // La tabla se desplaza (rueda/trackpad/teclado) → mueve el thumb.
  middle.addEventListener('scroll', update, { passive: true })

  // Arrastre del thumb.
  let dragging = false
  let startX = 0
  let startScroll = 0
  thumb.addEventListener('pointerdown', (e: PointerEvent) => {
    dragging = true
    startX = e.clientX
    startScroll = middle.scrollLeft
    thumb.setPointerCapture(e.pointerId)
    e.preventDefault()
  })
  thumb.addEventListener('pointermove', (e: PointerEvent) => {
    if (!dragging) return
    const maxScroll = middle.scrollWidth - middle.clientWidth
    const maxLeft = track.clientWidth - thumbWidth()
    const deltaScroll = maxLeft > 0 ? ((e.clientX - startX) / maxLeft) * maxScroll : 0
    middle.scrollLeft = startScroll + deltaScroll
  })
  const endDrag = (e: PointerEvent): void => {
    if (!dragging) return
    dragging = false
    try {
      thumb.releasePointerCapture(e.pointerId)
    } catch {
      /* el puntero ya se liberó */
    }
  }
  thumb.addEventListener('pointerup', endDrag)
  thumb.addEventListener('pointercancel', endDrag)

  // Click en la pista (fuera del thumb) → salta a esa posición.
  track.addEventListener('pointerdown', (e: PointerEvent) => {
    if (e.target === thumb) return
    const tw = thumbWidth()
    const clickX = e.clientX - track.getBoundingClientRect().left
    const maxScroll = middle.scrollWidth - middle.clientWidth
    const maxLeft = track.clientWidth - tw
    const target = maxLeft > 0 ? ((clickX - tw / 2) / maxLeft) * maxScroll : 0
    middle.scrollLeft = Math.max(0, Math.min(maxScroll, target))
  })

  // Re-mide ante cambios de tamaño (columnas, ventana, sidebar…).
  const ro = new ResizeObserver(update)
  ro.observe(middle)
  ro.observe(track)
  const table = middle.querySelector('table')
  if (table) ro.observe(table)
  update()
}

function scan(root: ParentNode): void {
  root.querySelectorAll?.('.q-table__middle').forEach((el) => enhance(el as HTMLElement))
}

let started = false

/** Arranca el enhancer global (idempotente). Llamar una vez al montar la app. */
export function startTableTopScroll(): void {
  if (started || typeof document === 'undefined') return
  started = true

  scan(document)

  const mo = new MutationObserver((mutations) => {
    for (const m of mutations) {
      m.addedNodes.forEach((n) => {
        if (!(n instanceof HTMLElement)) return
        if (n.classList.contains('q-table__middle')) enhance(n)
        else scan(n)
      })
    }
  })
  mo.observe(document.body, { childList: true, subtree: true })
}
