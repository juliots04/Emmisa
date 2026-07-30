<template>
  <header class="k-mod-head">
    <div class="k-mod-head-left">
      <span class="text-h5 k-mod-title">{{ title }}</span>
      <div
        v-if="subtitle"
        class="text-caption text-muted k-mod-sub"
      >
        {{ subtitle }}
      </div>
    </div>

    <q-space />

    <div class="k-mod-actions">
      <slot name="actions" />

      <q-btn
        v-if="refreshFn"
        flat
        no-caps
        class="k-mod-refresh"
        aria-label="Refrescar"
        :disable="spinning"
        @click="doRefresh"
      >
        <q-icon
          name="refresh"
          :class="{ 'k-spin': spinning }"
        />
        <q-tooltip>Refrescar</q-tooltip>
      </q-btn>

      <!-- Wrapper para que el tooltip funcione aun con el botón deshabilitado
           (Quasar corta los pointer-events del q-btn deshabilitado). -->
      <div
        v-if="showImport"
        class="k-mod-import"
      >
        <q-btn
          flat
          no-caps
          class="k-mod-btn"
          :disable="importDisabled"
          @click="onImport"
        >
          <q-icon
            name="upload_file"
            size="20px"
          />
          <span class="gt-xs k-mod-btn-label">{{ importLabel }}</span>
        </q-btn>
        <q-tooltip>{{ importDisabled ? importTooltip : importLabel }}</q-tooltip>
      </div>

      <q-btn
        v-if="showExport"
        flat
        no-caps
        class="k-mod-btn"
        @click="onExport"
      >
        <q-icon
          name="download"
          size="20px"
        />
        <span class="gt-xs k-mod-btn-label">{{ exportLabel }}</span>
        <q-tooltip>{{ exportLabel }}</q-tooltip>
      </q-btn>

      <q-btn
        v-if="newLabel"
        flat
        no-caps
        class="k-mod-btn k-mod-new"
        @click="onNew"
      >
        <q-icon :name="newIcon" />
        <span class="gt-xs k-mod-btn-label">{{ newLabel }}</span>
        <q-tooltip class="lt-sm">
          {{ newLabel }}
        </q-tooltip>
      </q-btn>
    </div>
  </header>
</template>

<script setup lang="ts">
import { ref } from 'vue'

const props = withDefaults(
  defineProps<{
    /** Nombre del módulo (título grande, izquierda). */
    title: string
    /** Descripción breve bajo el título. */
    subtitle?: string
    /** Etiqueta del botón primario "Nuevo"; si falta, no se muestra. */
    newLabel?: string
    /** Ícono del botón primario. */
    newIcon?: string
    /** Callback de recarga forzada; si falta, no se muestra el ícono de refresh.
     *  Puede devolver una promesa: el ícono gira mientras se resuelve. */
    refreshFn?: () => unknown | Promise<unknown>
    showImport?: boolean
    showExport?: boolean
    importLabel?: string
    exportLabel?: string
    /** Import "próximamente": deshabilita el botón y muestra el tooltip. */
    importDisabled?: boolean
    importTooltip?: string
  }>(),
  {
    subtitle: '',
    newLabel: '',
    newIcon: 'add',
    showImport: false,
    showExport: false,
    importLabel: 'Importar',
    exportLabel: 'Exportar',
    importDisabled: true,
    importTooltip: 'Próximamente',
  },
)

const emit = defineEmits<{
  (e: 'new'): void
  (e: 'import'): void
  (e: 'export'): void
}>()

const spinning = ref(false)
async function doRefresh() {
  if (spinning.value || !props.refreshFn) return
  spinning.value = true
  try {
    await props.refreshFn()
  } finally {
    spinning.value = false
  }
}

function onNew() {
  emit('new')
}
function onImport() {
  if (!props.importDisabled) emit('import')
}
function onExport() {
  emit('export')
}
</script>

<style scoped>
/* Barra de módulo pegajosa: se ancla justo bajo el header fijo de la app (60px).
   Sangría negativa para cubrir el padding del q-page (q-pa-md = 16px) y quedar a
   sangre; el padding interno realinea el contenido con la tabla de abajo. */
.k-mod-head {
  position: sticky;
  top: 60px;
  z-index: 5;
  display: flex;
  align-items: center;
  gap: 12px;
  margin: -16px -16px 16px;
  padding: 14px 16px;
  background: var(--k-bg);
}

.k-mod-head-left {
  display: flex;
  flex-direction: column;
  gap: 1px;
  min-width: 0;
}
.k-mod-title {
  line-height: 1.2;
}
.k-mod-sub {
  line-height: 1.25;
}

.k-mod-actions {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
}

/* Botones import/export/new: fondo tonal (primario suave), sin borde. */
.k-mod-btn {
  background: color-mix(in srgb, var(--q-primary) 14%, transparent);
  color: var(--q-primary);
}
.k-mod-btn:hover {
  background: color-mix(in srgb, var(--q-primary) 22%, transparent);
}
/* Refresh: sin fondo, va solo (solo el ícono). */
.k-mod-refresh {
  color: var(--k-muted);
}
.k-mod-refresh:hover {
  color: var(--k-text);
}
.k-mod-import {
  display: inline-flex;
}
.k-mod-btn-label {
  margin-left: 6px;
}

.k-spin {
  animation: k-spin 0.7s linear infinite;
}
@keyframes k-spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
