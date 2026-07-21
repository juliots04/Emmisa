<template>
  <button
    type="button"
    class="theme-toggle"
    role="switch"
    :aria-checked="isDark"
    :aria-label="isDark ? 'Activar modo claro' : 'Activar modo oscuro'"
    :title="isDark ? 'Modo claro' : 'Modo oscuro'"
    @click="toggle"
  >
    <span class="theme-toggle__track" :class="{ 'is-dark': isDark }">
      <span class="theme-toggle__knob">
        <!-- Sol -->
        <svg
          class="icon icon--sun"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <circle cx="12" cy="12" r="4" />
          <path
            d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"
          />
        </svg>
        <!-- Luna -->
        <svg
          class="icon icon--moon"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" />
        </svg>
      </span>
    </span>
  </button>
</template>

<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { useQuasar } from 'quasar'

const $q = useQuasar()
const STORAGE_KEY = 'konversa-theme'

const isDark = computed(() => $q.dark.isActive)

function persist(dark: boolean): void {
  try {
    localStorage.setItem(STORAGE_KEY, dark ? 'dark' : 'light')
  } catch {
    /* localStorage puede no estar disponible (modo privado / SSR) */
  }
}

function toggle(): void {
  $q.dark.toggle()
  persist($q.dark.isActive)
}

onMounted(() => {
  let saved: string | null = null
  try {
    saved = localStorage.getItem(STORAGE_KEY)
  } catch {
    saved = null
  }
  if (saved === 'dark' || saved === 'light') {
    $q.dark.set(saved === 'dark')
  }
})
</script>

<style scoped>
.theme-toggle {
  appearance: none;
  border: none;
  background: transparent;
  padding: 0;
  margin: 0;
  cursor: pointer;
  display: inline-flex;
  line-height: 0;
  border-radius: 999px;
}
.theme-toggle:focus-visible {
  outline: 2px solid var(--q-primary);
  outline-offset: 2px;
}

.theme-toggle__track {
  position: relative;
  width: 56px;
  height: 30px;
  border-radius: 999px;
  background: var(--k-surface-2);
  border: 1px solid var(--k-border);
  transition:
    background 200ms ease,
    border-color 200ms ease;
}

.theme-toggle__knob {
  position: absolute;
  top: 2px;
  left: 2px;
  width: 24px;
  height: 24px;
  border-radius: 50%;
  background: #ffffff;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.25);
  display: grid;
  place-items: center;
  transition: transform 220ms cubic-bezier(0.4, 0, 0.2, 1);
}
.theme-toggle__track.is-dark .theme-toggle__knob {
  transform: translateX(26px);
}

.icon {
  position: absolute;
  width: 15px;
  height: 15px;
  transition:
    opacity 200ms ease,
    transform 220ms cubic-bezier(0.4, 0, 0.2, 1);
}
.icon--sun {
  color: #f59e0b;
  opacity: 1;
  transform: rotate(0) scale(1);
}
.icon--moon {
  color: #6366f1;
  opacity: 0;
  transform: rotate(90deg) scale(0.4);
}
.theme-toggle__track.is-dark .icon--sun {
  opacity: 0;
  transform: rotate(-90deg) scale(0.4);
}
.theme-toggle__track.is-dark .icon--moon {
  opacity: 1;
  transform: rotate(0) scale(1);
}

@media (prefers-reduced-motion: reduce) {
  .theme-toggle__knob,
  .icon,
  .theme-toggle__track {
    transition: none;
  }
}
</style>
