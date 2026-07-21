<template>
  <q-page class="q-pa-md">
    <div class="text-h5 q-mb-md">Inicio</div>

    <div class="row q-col-gutter-md">
      <div v-for="s in stats" :key="s.label" class="col-12 col-sm-4">
        <q-card>
          <q-card-section>
            <div class="text-caption text-grey">{{ s.label }}</div>
            <div class="text-h4">{{ s.value }}</div>
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
        <q-btn color="primary" icon="receipt_long" label="Emitir comprobante" :to="{ name: 'emit' }" />
      </q-card-actions>
    </q-card>
  </q-page>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { notify } from '@/lib/toast'
import { useCompanyStore } from '@/stores/company'
import { listProducts } from '@/modules/products/products.api'
import { listCustomers } from '@/modules/customers/customers.api'
import { listDocuments } from '@/modules/documents/documents.api'

const company = useCompanyStore()
const stats = ref<{ label: string; value: number }[]>([
  { label: 'Productos', value: 0 },
  { label: 'Clientes', value: 0 },
  { label: 'Comprobantes', value: 0 },
])

onMounted(async () => {
  if (!company.current) return
  try {
    const id = company.current.id
    const [p, c, d] = await Promise.all([listProducts(id), listCustomers(id), listDocuments(id)])
    stats.value = [
      { label: 'Productos', value: p.length },
      { label: 'Clientes', value: c.length },
      { label: 'Comprobantes', value: d.length },
    ]
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  }
})
</script>
