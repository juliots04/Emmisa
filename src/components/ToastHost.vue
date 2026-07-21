<template>
  <Teleport to="body">
    <div ref="region" class="k-toast-region" role="region" aria-live="polite" aria-label="Notificaciones">
      <TransitionGroup
        tag="div"
        class="k-toast-stack"
        :css="false"
        @enter="onEnter"
        @leave="onLeave"
      >
        <div
          v-for="t in toasts.items"
          :key="t.id"
          class="k-toast"
          :class="`k-toast--${t.type}`"
          :role="t.type === 'negative' ? 'alert' : 'status'"
          @mouseenter="pause(t.id)"
          @mouseleave="resume(t.id)"
        >
          <span class="k-toast-accent k-fx" />
          <span class="k-toast-icon-wrap k-fx">
            <q-icon :name="t.icon" size="20px" />
          </span>
          <div class="k-toast-body k-fx">
            <div class="k-toast-msg">{{ t.message }}</div>
            <div v-if="t.caption" class="k-toast-caption">{{ t.caption }}</div>
          </div>
          <button class="k-toast-close k-fx" aria-label="Cerrar" @click="dismiss(t.id)">
            <q-icon name="close" size="15px" />
          </button>
          <span
            v-if="t.timeout > 0"
            class="k-toast-progress"
            :style="{
              animationDuration: `${t.timeout}ms`,
              animationPlayState: t.paused ? 'paused' : 'running',
            }"
          />
        </div>
      </TransitionGroup>
    </div>
  </Teleport>
</template>

<script setup lang="ts">
import gsap from 'gsap'
import { onUnmounted, ref } from 'vue'
import { toasts, dismiss, pause, resume } from '@/lib/toast'

const region = ref<HTMLElement | null>(null)

const reduced =
  typeof window !== 'undefined' &&
  window.matchMedia('(prefers-reduced-motion: reduce)').matches

function fxChildren(el: HTMLElement): HTMLElement[] {
  return Array.from(el.querySelectorAll<HTMLElement>('.k-fx'))
}

/* Entrada: el toast "se arma" — el contenedor entra con rebote y las piezas
   (acento, icono, texto, cerrar) se ensamblan escalonadas.
   autoAlpha = opacity + visibility (mejor que opacity sola: oculta de verdad). */
function onEnter(element: Element, done: () => void) {
  const el = element as HTMLElement
  const children = fxChildren(el)
  gsap.killTweensOf([el, ...children])

  if (reduced) {
    gsap.set(el, { clearProps: 'all' })
    done()
    return
  }

  const tl = gsap.timeline({ onComplete: done })
  tl.from(el, {
    xPercent: 115,
    scale: 0.85,
    autoAlpha: 0,
    duration: 0.5,
    ease: 'back.out(1.5)',
  })
  tl.from(
    children,
    {
      autoAlpha: 0,
      y: 10,
      scale: 0.7,
      duration: 0.34,
      ease: 'back.out(2.2)',
      stagger: 0.055,
    },
    0.1,
  )
}

/* Salida: el toast "se rompe" — se saca del flujo (para que la pila se
   reacomode) y las piezas salen disparadas con giro mientras colapsa. */
function onLeave(element: Element, done: () => void) {
  const el = element as HTMLElement
  const children = fxChildren(el)
  gsap.killTweensOf([el, ...children])

  if (reduced) {
    gsap.to(el, { autoAlpha: 0, duration: 0.12, onComplete: done })
    return
  }

  // Fijar posición actual para desacoplarlo del layout: los hermanos suben
  // suave vía la transición de "move" mientras este se rompe en su sitio.
  gsap.set(el, {
    position: 'absolute',
    top: el.offsetTop,
    left: el.offsetLeft,
    width: el.offsetWidth,
    margin: 0,
    zIndex: 0,
  })

  const tl = gsap.timeline({ onComplete: done })
  tl.to(
    children,
    {
      x: (i: number) => (i - 1.5) * 26,
      y: (i: number) => (i % 2 === 0 ? -20 : 22),
      rotation: (i: number) => (i % 2 === 0 ? -14 : 14),
      autoAlpha: 0,
      duration: 0.32,
      ease: 'power3.in',
      stagger: 0.02,
    },
    0,
  )
  tl.to(
    el,
    {
      scale: 0.86,
      autoAlpha: 0,
      duration: 0.34,
      ease: 'power2.in',
    },
    0.04,
  )
}

// Buenas prácticas GSAP: matar tweens en curso al desmontar (scopeado a la región).
onUnmounted(() => {
  if (region.value) gsap.killTweensOf(region.value.querySelectorAll('*'))
})
</script>

<style scoped>
/* ---------- Región / pila ---------- */
.k-toast-region {
  position: fixed;
  right: 18px;
  bottom: 18px;
  z-index: 9000;
  pointer-events: none;
}
.k-toast-stack {
  display: flex;
  flex-direction: column;
  gap: 10px;
  align-items: flex-end;
}

/* Reacomodo de la pila cuando una desaparece (transform = GPU). */
.k-toast-move {
  transition: transform 0.42s cubic-bezier(0.16, 1, 0.3, 1);
}

/* ---------- Tarjeta ---------- */
.k-toast {
  --accent: var(--q-info);
  position: relative;
  display: flex;
  align-items: flex-start;
  gap: 11px;
  width: 340px;
  max-width: calc(100vw - 36px);
  padding: 13px 12px 13px 16px;
  overflow: hidden;
  pointer-events: auto;
  color: var(--k-text);
  background: var(--k-surface);
  border: 1px solid var(--k-border);
  border-radius: var(--k-radius-sm);
  box-shadow:
    0 10px 30px -10px rgba(0, 0, 0, 0.35),
    0 2px 8px -2px rgba(0, 0, 0, 0.2);
  will-change: transform, opacity;
}
.body--light .k-toast {
  box-shadow:
    0 12px 32px -12px rgba(15, 23, 42, 0.28),
    0 2px 8px -4px rgba(15, 23, 42, 0.12);
}

/* Acento vertical izquierdo */
.k-toast-accent {
  position: absolute;
  left: 0;
  top: 0;
  bottom: 0;
  width: 4px;
  background: var(--accent);
}

.k-toast-icon-wrap {
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 30px;
  height: 30px;
  border-radius: 9px;
  color: var(--accent);
  background: color-mix(in srgb, var(--accent) 16%, transparent);
}

.k-toast-body {
  flex: 1 1 auto;
  min-width: 0;
  padding-top: 2px;
}
.k-toast-msg {
  font-size: 13.5px;
  font-weight: 600;
  line-height: 1.35;
  word-break: break-word;
}
.k-toast-caption {
  margin-top: 2px;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  color: var(--k-muted);
  word-break: break-word;
}

.k-toast-close {
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  margin: -2px -2px 0 0;
  padding: 0;
  border: none;
  border-radius: 7px;
  background: transparent;
  color: var(--k-muted);
  cursor: pointer;
  transition: background 0.15s ease, color 0.15s ease;
}
.k-toast-close:hover {
  background: var(--k-surface-2);
  color: var(--k-text);
}

/* Barra de progreso (countdown lineal, GPU) */
.k-toast-progress {
  position: absolute;
  left: 0;
  bottom: 0;
  height: 3px;
  width: 100%;
  transform-origin: left center;
  background: var(--accent);
  opacity: 0.55;
  animation-name: k-shrink;
  animation-timing-function: linear;
  animation-fill-mode: forwards;
}

/* ---------- Colores por tipo ---------- */
.k-toast--positive {
  --accent: var(--q-positive);
}
.k-toast--negative {
  --accent: var(--q-negative);
}
.k-toast--warning {
  --accent: var(--q-warning);
}
.k-toast--info {
  --accent: var(--q-info);
}
.k-toast--ongoing {
  --accent: var(--q-primary);
}

@keyframes k-shrink {
  from {
    transform: scaleX(1);
  }
  to {
    transform: scaleX(0);
  }
}

/* ---------- Responsive ---------- */
@media (max-width: 600px) {
  .k-toast-region {
    left: 12px;
    right: 12px;
    bottom: 12px;
  }
  .k-toast-stack {
    align-items: stretch;
  }
  .k-toast {
    width: 100%;
  }
}
</style>
