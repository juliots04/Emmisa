<template>
  <button
    type="button"
    class="k-switch"
    role="switch"
    :aria-checked="modelValue"
    :aria-label="label"
    :disabled="disable"
    :style="{ '--sw-on': color }"
    @click="toggle"
  >
    <span
      class="k-switch-track"
      :class="{ 'is-on': modelValue }"
    >
      <span class="k-switch-knob">
        <svg
          class="k-switch-ic"
          viewBox="0 0 24 24"
          aria-hidden="true"
        >
          <path :d="modelValue ? 'M20 6 9 17l-5-5' : 'M6 6l12 12M18 6 6 18'" />
        </svg>
      </span>
    </span>
    <span class="k-switch-text">
      <span class="k-switch-name">{{ label }}</span>
      <span
        class="k-switch-state"
        :class="{ 'is-on': modelValue }"
      >{{ modelValue ? onText : offText }}</span>
    </span>
  </button>
</template>

<script setup lang="ts">
// Switch personalizado (v-model). Muestra SIEMPRE un descriptor fijo (qué controla)
// y debajo el estado actual (Sí/No), que cambia de texto y color según on/off.
// El color de acento es por switch.
const props = withDefaults(
  defineProps<{
    modelValue: boolean
    /** Descriptor fijo, siempre visible (p.ej. "Incluye IGV", "Habilitado"). */
    label: string
    /** Texto de estado ENCENDIDO (por defecto "Sí"). */
    onText?: string
    /** Texto de estado APAGADO (por defecto "No"). */
    offText?: string
    /** Color de acento al encender (por switch, no hay un "verde" fijo). */
    color?: string
    disable?: boolean
  }>(),
  { onText: 'Sí', offText: 'No', color: '#6366f1', disable: false },
)
const emit = defineEmits<{ 'update:modelValue': [boolean] }>()

function toggle(): void {
  if (props.disable) return
  emit('update:modelValue', !props.modelValue)
}
</script>

<style scoped>
.k-switch {
  display: inline-flex;
  align-items: center;
  gap: 11px;
  border: none;
  background: none;
  padding: 0;
  cursor: pointer;
  font-family: inherit;
  text-align: left;
  -webkit-tap-highlight-color: transparent;
}
.k-switch:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
.k-switch:focus-visible {
  outline: none;
}
.k-switch:focus-visible .k-switch-track {
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--sw-on) 55%, transparent);
}

.k-switch-track {
  position: relative;
  width: 46px;
  height: 26px;
  border-radius: 999px;
  background: var(--k-surface-2);
  box-shadow: inset 0 0 0 1px var(--k-border-hover);
  transition: background 0.25s ease, box-shadow 0.25s ease;
  flex-shrink: 0;
}
.k-switch-track.is-on {
  background: var(--sw-on);
  box-shadow: 0 2px 10px color-mix(in srgb, var(--sw-on) 42%, transparent);
}
.k-switch-knob {
  position: absolute;
  top: 3px;
  left: 3px;
  width: 20px;
  height: 20px;
  border-radius: 50%;
  background: #ffffff;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.35);
  display: flex;
  align-items: center;
  justify-content: center;
  transition: transform 0.26s cubic-bezier(0.34, 1.56, 0.64, 1);
}
.k-switch-track.is-on .k-switch-knob {
  transform: translateX(20px);
}
.k-switch-ic {
  width: 12px;
  height: 12px;
  fill: none;
  stroke: var(--sw-on);
  stroke-width: 3.2;
  stroke-linecap: round;
  stroke-linejoin: round;
  transition: stroke 0.2s ease;
}
.k-switch-track:not(.is-on) .k-switch-ic {
  stroke: var(--k-muted);
}

.k-switch-text {
  display: flex;
  flex-direction: column;
  line-height: 1.25;
}
/* Descriptor fijo: SIEMPRE visible, dice qué controla el switch. */
.k-switch-name {
  font-size: 13.5px;
  font-weight: 600;
  color: var(--k-text);
}
/* Estado actual: cambia texto y color según on/off. */
.k-switch-state {
  font-size: 11px;
  font-weight: 600;
  color: var(--k-muted);
  transition: color 0.2s ease;
}
.k-switch-state.is-on {
  color: var(--sw-on);
}

@media (prefers-reduced-motion: reduce) {
  .k-switch-track,
  .k-switch-knob,
  .k-switch-ic,
  .k-switch-state {
    transition: none;
  }
}
</style>
