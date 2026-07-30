<template>
  <q-page class="q-pa-md">
    <div class="text-h5 q-mb-md">Inicio</div>

    <SubscriptionBanner />

    <div class="row q-col-gutter-md">
      <div v-for="s in stats" :key="s.label" class="col-12 col-sm-4">
        <q-card>
          <q-card-section>
            <div class="text-caption text-muted">
              {{ s.label }}
            </div>
            <div class="text-h4">
              {{ s.value }}
            </div>
          </q-card-section>
        </q-card>
      </div>
    </div>

    <q-card class="q-mt-md">
      <q-card-section>
        <div class="text-subtitle1">Empresa actual</div>
        <div v-if="company.current">
          {{ company.current.razon_social }} — RUC {{ company.current.ruc }}
          <q-badge class="q-ml-sm" color="secondary" :label="company.current.regimen" />
        </div>
      </q-card-section>
      <q-card-actions>
        <q-btn
          color="primary"
          icon="receipt_long"
          label="Emitir comprobante"
          :to="{ name: 'emit' }"
        />
      </q-card-actions>
    </q-card>
  </q-page>
</template>

<script setup lang="ts">
import { ref, watch } from 'vue'
import { notify } from '@/lib/toast'
import { useCompanyStore } from '@/stores/company'
import { supabase } from '@/lib/supabase'
import { cachedQuery } from '@/stores/queryCache'
import SubscriptionBanner from '@/components/SubscriptionBanner.vue'

const company = useCompanyStore()
const stats = ref<{ label: string; value: number }[]>([
  { label: 'Productos', value: 0 },
  { label: 'Clientes', value: 0 },
  { label: 'Comprobantes', value: 0 },
])

// Cuenta EXACTA sin traer filas (head: true): no queda topada por el límite de
// paginación (antes usaba d.length con limit 500) ni descarga datos.
async function countOf(table: 'products' | 'customers' | 'documents', id: string): Promise<number> {
  const { count, error } = await supabase
    .from(table)
    .select('*', { count: 'exact', head: true })
    .eq('company_id', id)
  if (error) throw error // antes se tragaba el error y mostraba "0" (enmascaraba fallos)
  return count ?? 0
}
async function loadStats(id: string) {
  try {
    const [p, c, d] = await cachedQuery(
      ['dashboard-counts', id],
      ['dashboard', `company:${id}`],
      () =>
        Promise.all([countOf('products', id), countOf('customers', id), countOf('documents', id)]),
    )
    stats.value = [
      { label: 'Productos', value: p },
      { label: 'Clientes', value: c },
      { label: 'Comprobantes', value: d },
    ]
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  }
}
// Refresca al montar Y al cambiar de empresa (multiempresa / marca blanca).
watch(
  () => company.current?.id,
  (id) => {
    if (id) void loadStats(id)
  },
  { immediate: true },
)
</script>
