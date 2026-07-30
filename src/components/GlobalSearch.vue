<template>
  <div class="k-gsearch">
    <q-input
      ref="inputRef"
      v-model="query"
      dense
      outlined
      type="search"
      name="k-module-search"
      autocomplete="off"
      class="k-gsearch-input"
      placeholder="Buscar módulo…"
      @focus="open = true"
      @blur="open = false"
      @keydown.down.prevent="move(1)"
      @keydown.up.prevent="move(-1)"
      @keydown.enter.prevent="choose(results[active])"
      @keydown.esc="reset"
    >
      <template #prepend>
        <q-icon
          name="search"
          size="18px"
        />
      </template>
      <template #append>
        <span class="k-gsearch-kbd">{{ kbdHint }}</span>
      </template>
    </q-input>

    <!-- Dropdown de resultados (navegación) · transición líquida al abrir/cerrar -->
    <Transition name="k-liquid">
      <div
        v-if="open && query.trim()"
        class="k-gsearch-panel"
      >
      <template v-if="results.length">
        <button
          v-for="(item, i) in results"
          :key="item.to"
          type="button"
          class="k-gsearch-item"
          :class="{ 'is-active': i === active }"
          @mousedown.prevent="choose(item)"
          @mouseenter="active = i"
        >
          <q-icon
            :name="item.icon"
            size="18px"
            class="k-gsearch-item-ico"
          />
          <span class="k-gsearch-item-label">{{ item.label }}</span>
          <q-icon
            name="north_east"
            size="15px"
            class="k-gsearch-item-go"
          />
        </button>
      </template>
      <div
        v-else
        class="k-gsearch-empty"
      >
        Sin resultados para «{{ query.trim() }}»
      </div>
      </div>
    </Transition>
  </div>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { QInput } from 'quasar'

interface SearchItem {
  to: string
  label: string
  icon: string
}

const props = defineProps<{ items: SearchItem[] }>()

const router = useRouter()
const inputRef = ref<QInput | null>(null)
const query = ref('')
const open = ref(false)
const active = ref(0)

// Normaliza para comparar sin acentos ni mayúsculas ("categorias" → "Categorías").
const norm = (s: string) => s.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase()

const results = computed<SearchItem[]>(() => {
  const q = norm(query.value.trim())
  if (!q) return []
  return props.items.filter((it) => norm(it.label).includes(q)).slice(0, 8)
})

// Al cambiar los resultados, el resaltado vuelve al primero.
watch(results, () => { active.value = 0 })

function move(dir: number) {
  const n = results.value.length
  if (!n) return
  open.value = true
  active.value = (active.value + dir + n) % n
}

function choose(item: SearchItem | undefined) {
  if (!item) return
  void router.push(item.to)
  reset()
}

function reset() {
  query.value = ''
  open.value = false
  active.value = 0
  inputRef.value?.blur()
}

// Atajo global Ctrl/⌘ + K → enfoca el buscador.
const isMac = /Mac|iPhone|iPad|iPod/.test(navigator.platform)
const kbdHint = isMac ? '⌘K' : 'Ctrl K'
function onKeydown(e: KeyboardEvent) {
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
    e.preventDefault()
    inputRef.value?.focus()
  }
}
onMounted(() => document.addEventListener('keydown', onKeydown))
onBeforeUnmount(() => document.removeEventListener('keydown', onKeydown))
</script>

<style scoped>
.k-gsearch {
  position: relative;
}
.k-gsearch-input {
  width: 240px;
}
/* Compacta el input al alto del header (mismo lenguaje que los otros controles). */
.k-gsearch-input :deep(.q-field__control) {
  border-radius: 12px;
  height: 38px;
  min-height: 38px;
}
.k-gsearch-input :deep(.q-field__marginal) {
  height: 38px;
  color: var(--k-muted);
}
.k-gsearch-kbd {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 10.5px;
  font-weight: 600;
  color: var(--k-muted);
  border: 1px solid var(--k-border);
  border-radius: 6px;
  padding: 1px 6px;
  white-space: nowrap;
}

/* Panel de resultados */
.k-gsearch-panel {
  position: absolute;
  top: calc(100% + 6px);
  left: 0;
  right: 0;
  z-index: 30;
  background: var(--k-surface);
  border: 1px solid var(--k-border);
  border-radius: var(--k-radius-sm);
  box-shadow: 0 14px 34px rgba(0, 0, 0, 0.22);
  padding: 6px;
  overflow: hidden;
  transform-origin: top center;
}

/* Transición líquida al abrir/cerrar (mismo easing/feel del resto del sistema:
   desenfoque → nítido, con deslizamiento y escala). */
.k-liquid-enter-active {
  transition:
    opacity 0.28s cubic-bezier(0.22, 1, 0.36, 1),
    transform 0.28s cubic-bezier(0.22, 1, 0.36, 1),
    filter 0.28s ease;
}
.k-liquid-leave-active {
  transition:
    opacity 0.18s ease,
    transform 0.18s cubic-bezier(0.4, 0, 1, 1),
    filter 0.18s ease;
}
.k-liquid-enter-from {
  opacity: 0;
  transform: translateY(-6px) scale(0.985);
}
.k-liquid-leave-to {
  opacity: 0;
  transform: translateY(-6px) scale(0.98);
  filter: blur(2px);
}
@media (prefers-reduced-motion: reduce) {
  .k-liquid-enter-active,
  .k-liquid-leave-active {
    transition: none;
  }
}
.k-gsearch-item {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
  border: none;
  background: transparent;
  color: var(--k-text);
  font-family: inherit;
  font-size: 13.5px;
  font-weight: 500;
  text-align: left;
  padding: 9px 10px;
  border-radius: 10px;
  cursor: pointer;
  /* Efecto "ola": cada resultado entra en cascada (reusa el keyframe global). */
  animation: k-wave-in 0.4s cubic-bezier(0.22, 1, 0.36, 1) both;
}
.k-gsearch-item:nth-child(1) { animation-delay: 0.02s; }
.k-gsearch-item:nth-child(2) { animation-delay: 0.06s; }
.k-gsearch-item:nth-child(3) { animation-delay: 0.10s; }
.k-gsearch-item:nth-child(4) { animation-delay: 0.14s; }
.k-gsearch-item:nth-child(5) { animation-delay: 0.18s; }
.k-gsearch-item:nth-child(6) { animation-delay: 0.22s; }
.k-gsearch-item:nth-child(7) { animation-delay: 0.26s; }
.k-gsearch-item:nth-child(8) { animation-delay: 0.30s; }
@media (prefers-reduced-motion: reduce) {
  .k-gsearch-item { animation: none; }
}
.k-gsearch-item.is-active {
  background: var(--k-active-bg);
}
.k-gsearch-item-ico {
  color: var(--k-muted);
  flex-shrink: 0;
}
.k-gsearch-item.is-active .k-gsearch-item-ico {
  color: var(--k-text);
}
.k-gsearch-item-label {
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.k-gsearch-item-go {
  color: var(--k-muted);
  opacity: 0;
  transition: opacity 0.12s ease;
}
.k-gsearch-item.is-active .k-gsearch-item-go {
  opacity: 1;
}
.k-gsearch-empty {
  padding: 12px 10px;
  font-size: 13px;
  color: var(--k-muted);
}
</style>
