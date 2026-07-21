// ============================================================
// Sistema de notificaciones global de Konversa.
// Reemplaza a $q.notify con toasts animados (ver components/ToastHost.vue).
// API compatible con la firma que ya usa la app: { type, message, caption }.
//
//   import { notify } from '@/lib/toast'
//   notify({ type: 'positive', message: 'Guardado', caption: 'Detalle…' })
//   notify('Mensaje simple')                     // info por defecto
//   const id = notify({ type: 'ongoing', message: 'Procesando…', timeout: 0 })
//   dismiss(id)                                   // cerrar manualmente
// ============================================================
import { reactive } from 'vue'

export type ToastType = 'positive' | 'negative' | 'warning' | 'info' | 'ongoing'

export interface ToastOptions {
  type?: ToastType
  message: string
  caption?: string
  /** ms hasta autocerrar. 0 = permanece hasta cerrar/dismiss. */
  timeout?: number
  /** icono material opcional; por defecto según el tipo. */
  icon?: string
}

export interface Toast {
  id: number
  type: ToastType
  message: string
  caption?: string
  timeout: number
  icon: string
  paused: boolean
}

const state = reactive<{ items: Toast[] }>({ items: [] })
/** Lista reactiva que consume ToastHost.vue. */
export const toasts = state

// Máximo 2 visibles a la vez: al llegar una 3ª, la más antigua se va (y explota).
const MAX_VISIBLE = 2

const ICONS: Record<ToastType, string> = {
  positive: 'check_circle',
  negative: 'error',
  warning: 'warning',
  info: 'info',
  ongoing: 'hourglass_top',
}

const DEFAULT_TIMEOUT: Record<ToastType, number> = {
  positive: 3500,
  info: 3500,
  warning: 5000,
  negative: 6000,
  ongoing: 0,
}

let seq = 0

interface TimerRef {
  handle: ReturnType<typeof setTimeout>
  startedAt: number
  remaining: number
}
const timers = new Map<number, TimerRef>()

function find(id: number): Toast | undefined {
  return state.items.find((t) => t.id === id)
}

function arm(id: number, ms: number) {
  const handle = setTimeout(() => dismiss(id), ms)
  timers.set(id, { handle, startedAt: performance.now(), remaining: ms })
}

function clearTimer(id: number) {
  const t = timers.get(id)
  if (t) {
    clearTimeout(t.handle)
    timers.delete(id)
  }
}

/** Crea una notificación y devuelve su id (para dismiss/update manual). */
function createToast(opts: ToastOptions | string): number {
  const o: ToastOptions = typeof opts === 'string' ? { message: opts } : opts
  const type: ToastType = o.type ?? 'info'
  const id = ++seq
  const timeout = o.timeout ?? DEFAULT_TIMEOUT[type]

  state.items.push({
    id,
    type,
    message: o.message,
    caption: o.caption,
    timeout,
    icon: o.icon ?? ICONS[type],
    paused: false,
  })

  // Limita la pila visible: descarta el más antiguo.
  while (state.items.length > MAX_VISIBLE) {
    dismiss(state.items[0].id)
  }

  if (timeout > 0) arm(id, timeout)
  return id
}

/**
 * API global de notificaciones. Es INVOCABLE y además tiene atajos por tipo,
 * al estilo de librerías como sonner / react-hot-toast:
 *   notify({ type: 'positive', message: 'Guardado' })   // forma completa
 *   notify.success('Guardado', 'Detalle opcional')       // atajo
 *   notify.error('Algo falló')
 * Cambiar el sistema entero (animación, posición, sonido) = editar solo este archivo.
 */
export interface NotifyApi {
  (opts: ToastOptions | string): number
  success(message: string, caption?: string): number
  error(message: string, caption?: string): number
  warning(message: string, caption?: string): number
  info(message: string, caption?: string): number
  /** Persistente (timeout 0) hasta dismiss(): útil para procesos en curso. */
  ongoing(message: string, caption?: string): number
}

export const notify: NotifyApi = Object.assign(createToast, {
  success: (message: string, caption?: string) => createToast({ type: 'positive', message, caption }),
  error: (message: string, caption?: string) => createToast({ type: 'negative', message, caption }),
  warning: (message: string, caption?: string) => createToast({ type: 'warning', message, caption }),
  info: (message: string, caption?: string) => createToast({ type: 'info', message, caption }),
  ongoing: (message: string, caption?: string) =>
    createToast({ type: 'ongoing', message, caption, timeout: 0 }),
})

/** Cierra una notificación por id. */
export function dismiss(id: number) {
  const i = state.items.findIndex((t) => t.id === id)
  if (i !== -1) state.items.splice(i, 1)
  clearTimer(id)
}

export function dismissAll() {
  for (const t of [...state.items]) dismiss(t.id)
}

/** Pausa el autocierre (hover). Congela también la barra de progreso. */
export function pause(id: number) {
  const toast = find(id)
  if (toast) toast.paused = true
  const t = timers.get(id)
  if (!t) return
  clearTimeout(t.handle)
  // Mutamos la entrada en el mapa: queda el tiempo restante, sin timer activo.
  t.remaining -= performance.now() - t.startedAt
}

/** Reanuda el autocierre con el tiempo restante (mouse leave). */
export function resume(id: number) {
  const toast = find(id)
  if (toast) toast.paused = false
  const t = timers.get(id)
  if (!t) return
  if (t.remaining <= 0) {
    dismiss(id)
    return
  }
  arm(id, t.remaining)
}
