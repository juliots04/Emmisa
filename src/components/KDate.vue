<template>
  <!-- Campo de fecha: TODO el campo es clickeable y abre el calendario estilizado -->
  <div
    class="k-date"
    :class="{ 'k-date--open': open }"
    tabindex="0"
    role="button"
    aria-haspopup="dialog"
    @keydown.enter.prevent="open = true"
    @keydown.space.prevent="open = true"
  >
    <q-icon
      name="event"
      size="20px"
      class="k-date-ic"
    />
    <span
      class="k-date-txt"
      :class="{ 'k-date-ph': !modelValue }"
    >{{ display }}</span>
    <q-icon
      name="expand_more"
      size="18px"
      class="k-date-caret"
    />

    <q-menu
      v-model="open"
      anchor="bottom left"
      self="top left"
      transition-show="scale"
      transition-hide="scale"
    >
      <q-date
        :model-value="modelValue || null"
        mask="YYYY-MM-DD"
        today-btn
        minimal
        color="primary"
        @update:model-value="(v: string | null) => emit('update:modelValue', v ?? '')"
      >
        <div class="row justify-end q-gutter-sm">
          <q-btn
            v-close-popup
            flat
            no-caps
            color="negative"
            label="Quitar"
            @click="emit('update:modelValue', '')"
          />
          <q-btn
            v-close-popup
            unelevated
            no-caps
            color="primary"
            label="Listo"
          />
        </div>
      </q-date>
    </q-menu>
  </div>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue'

const props = defineProps<{
  modelValue: string
  placeholder?: string
}>()
const emit = defineEmits<{ 'update:modelValue': [v: string] }>()

const open = ref(false)
const display = computed(() => {
  if (!props.modelValue) return props.placeholder ?? 'Seleccionar'
  const [y, m, d] = props.modelValue.split('-')
  return `${d}/${m}/${y}`
})
</script>

<style scoped>
.k-date {
  display: flex;
  align-items: center;
  gap: 10px;
  height: 50px;
  padding: 0 14px;
  border-radius: var(--k-radius-sm);
  background: var(--k-surface-2);
  color: var(--k-text);
  cursor: pointer;
  user-select: none;
  transition: box-shadow 0.15s ease;
}
.k-date:hover {
  box-shadow: 0 0 0 1px var(--k-border-hover);
}
.k-date:focus-visible {
  outline: none;
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--q-primary) 55%, transparent);
}
.k-date--open {
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--q-primary) 55%, transparent);
}
.k-date-ic {
  color: var(--k-muted);
  flex-shrink: 0;
}
.k-date-txt {
  flex: 1;
  font-size: 14px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.k-date-ph {
  color: var(--k-muted);
}
.k-date-caret {
  color: var(--k-muted);
  flex-shrink: 0;
}
</style>
