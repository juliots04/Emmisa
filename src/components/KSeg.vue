<template>
  <div
    class="k-seg"
    role="group"
  >
    <!-- Píldora que se desliza entre opciones (efecto líquido) -->
    <span
      class="k-seg-thumb"
      :style="thumbStyle"
      aria-hidden="true"
    />
    <button
      v-for="o in options"
      :key="o.value"
      type="button"
      class="k-seg-btn"
      :class="{ 'k-seg-btn--on': modelValue === o.value }"
      :aria-pressed="modelValue === o.value"
      @click="$emit('update:modelValue', o.value)"
    >
      {{ o.label }}
    </button>
  </div>
</template>

<script setup lang="ts" generic="T extends string">
import { computed } from 'vue'

const props = defineProps<{
  modelValue: T
  options: { label: string; value: T }[]
}>()
defineEmits<{ 'update:modelValue': [value: T] }>()

const idx = computed(() => Math.max(0, props.options.findIndex((o) => o.value === props.modelValue)))
const thumbStyle = computed(() => ({
  width: `calc((100% - 12px) / ${props.options.length})`,
  transform: `translateX(${idx.value * 100}%)`,
}))
</script>

<style scoped>
.k-seg {
  position: relative;
  display: flex;
  width: 100%;
  padding: 0px; /* aire solo a los lados (inicio/final) */
  border-radius: 999px;
  background: var(--k-surface-2);
  isolation: isolate;
}
/* Píldora deslizante (sin sombra) */
.k-seg-thumb {
  position: absolute;
  top: 0;
  left: 6px;
  bottom: 0;
  border-radius: 999px;
  background: var(--k-surface);
  z-index: 0;
  /* Elástico = sensación líquida (leve rebote al llegar) */
  transition: transform 0.42s cubic-bezier(0.34, 1.4, 0.5, 1);
}
.body--dark .k-seg-thumb {
  background: color-mix(in srgb, var(--k-surface-2) 78%, #ffffff);
}
@media (prefers-reduced-motion: reduce) {
  .k-seg-thumb {
    transition: none;
  }
}
.k-seg-btn {
  position: relative;
  z-index: 1;
  flex: 1;
  border: none;
  background: transparent;
  color: var(--k-muted);
  font-family: inherit;
  font-weight: 600;
  font-size: 13.5px;
  letter-spacing: 0.2px;
  padding: 9px 16px;
  border-radius: 999px;
  cursor: pointer;
  transition: color 0.25s ease, transform 0.12s ease;
}
.k-seg-btn:hover {
  color: var(--k-text);
}
.k-seg-btn:active {
  transform: scale(0.97);
}
.k-seg-btn:focus-visible {
  outline: none;
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--q-primary) 55%, transparent);
}
.k-seg-btn--on {
  color: var(--k-text);
  font-weight: 700;
}
</style>
