<template>
  <q-banner
    v-if="visible"
    :class="tono"
    rounded
    class="q-mb-md"
  >
    <template #avatar>
      <q-icon :name="icono" />
    </template>
    <div class="text-weight-medium">
      {{ titulo }}
    </div>
    <div class="text-caption">
      {{ detalle }}
    </div>
  </q-banner>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useCompanyStore } from '@/stores/company'
import { estadoSuscripcion, type EstadoSuscripcion } from '@/modules/reseller/reseller.api'

const company = useCompanyStore()
const estado = ref<EstadoSuscripcion | null>(null)

async function cargar() {
  estado.value = null
  if (!company.current) return
  try {
    estado.value = await estadoSuscripcion(company.current.id)
  } catch {
    // La RPC estado_suscripcion aún no existe (migración 0031 sin aplicar): no mostramos nada.
    estado.value = null
  }
}

// Solo mostramos el banner cuando hay algo que avisar: bloqueado, vencido, o por vencer (<= 7 días).
const visible = computed(() => {
  const e = estado.value
  if (!e || !e.tiene_suscripcion) return false
  if (!e.puede_emitir) return true
  return e.dias_restantes !== null && e.dias_restantes <= 7
})

const bloqueado = computed(() => estado.value != null && !estado.value.puede_emitir)

const tono = computed(() => (bloqueado.value ? 'k-banner--danger' : 'k-banner--warn'))
const icono = computed(() => (bloqueado.value ? 'lock' : 'schedule'))

const titulo = computed(() => {
  const e = estado.value
  if (!e) return ''
  if (!e.puede_emitir) return 'Tu suscripción no está activa'
  const d = e.dias_restantes
  if (d !== null && d <= 0) return 'Tu plan vence hoy'
  return `Tu plan vence en ${d} día${d === 1 ? '' : 's'}`
})

const detalle = computed(() => {
  const e = estado.value
  if (!e) return ''
  if (!e.puede_emitir) {
    return 'No podrás emitir nuevos comprobantes hasta regularizar el pago. Contacta a tu proveedor.'
  }
  return 'Renueva tu suscripción para no interrumpir la emisión de comprobantes.'
})

onMounted(cargar)
watch(() => company.current?.id, cargar)
</script>

<style scoped>
.k-banner--warn {
  background: color-mix(in srgb, #f59e0b 14%, transparent);
  color: var(--k-text);
  border: 1px solid color-mix(in srgb, #f59e0b 40%, transparent);
}
.k-banner--warn :deep(.q-icon) {
  color: #d97706;
}
.k-banner--danger {
  background: color-mix(in srgb, #ef4444 14%, transparent);
  color: var(--k-text);
  border: 1px solid color-mix(in srgb, #ef4444 42%, transparent);
}
.k-banner--danger :deep(.q-icon) {
  color: #dc2626;
}
</style>
