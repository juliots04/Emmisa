<template>
  <q-page class="q-pa-md">
    <div class="text-h5 q-mb-md">Reportes</div>

    <div class="row q-col-gutter-md">
      <div v-for="k in kpis" :key="k.label" class="col-12 col-sm-4">
        <q-card>
          <q-card-section>
            <div class="text-caption text-grey">{{ k.label }}</div>
            <div class="text-h4">{{ k.value }}</div>
          </q-card-section>
        </q-card>
      </div>
    </div>

    <q-card class="q-mt-md">
      <q-card-section>
        <div class="text-subtitle1 q-mb-sm">Ventas por día</div>
        <q-table
          :rows="salesByDay"
          :columns="dayColumns"
          row-key="fecha"
          :loading="loading"
          :pagination="pagination"
          flat
          bordered
          hide-pagination
        />
      </q-card-section>
    </q-card>

    <q-card class="q-mt-md">
      <q-card-section>
        <div class="text-subtitle1 q-mb-sm">Productos más vendidos</div>
        <q-table
          :rows="topProducts"
          :columns="productColumns"
          row-key="descripcion"
          :loading="loading"
          :pagination="pagination"
          flat
          bordered
          hide-pagination
        />
      </q-card-section>
    </q-card>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { type QTableColumn } from 'quasar'
import { useCompanyStore } from '@/stores/company'
import { notify } from '@/lib/toast'
import {
  getSalesByDay,
  getSummary,
  getTopProducts,
  type SalesByDay,
  type TopProduct,
} from '@/modules/reports/reports.api'

const company = useCompanyStore()
const loading = ref(false)

const totalFacturado = ref(0)
const numComprobantes = ref(0)
const ticketPromedio = ref(0)
const salesByDay = ref<SalesByDay[]>([])
const topProducts = ref<TopProduct[]>([])

// Mostrar todas las filas (sin paginar): pocas por reporte.
const pagination = { rowsPerPage: 0 }

function soles(v: number): string {
  return `S/ ${v.toFixed(2)}`
}

const kpis = computed(() => [
  { label: 'Total facturado', value: soles(totalFacturado.value) },
  { label: 'N° comprobantes', value: String(numComprobantes.value) },
  { label: 'Ticket promedio', value: soles(ticketPromedio.value) },
])

const dayColumns: QTableColumn<SalesByDay>[] = [
  { name: 'fecha', label: 'Fecha', field: 'fecha', align: 'left' },
  { name: 'cantidad', label: 'Cantidad', field: 'cantidad', align: 'right' },
  {
    name: 'total',
    label: 'Total',
    field: 'total',
    align: 'right',
    format: (v) => soles(Number(v)),
  },
]

const productColumns: QTableColumn<TopProduct>[] = [
  { name: 'descripcion', label: 'Descripción', field: 'descripcion', align: 'left' },
  { name: 'cantidad', label: 'Cantidad', field: 'cantidad', align: 'right' },
  {
    name: 'total',
    label: 'Total',
    field: 'total',
    align: 'right',
    format: (v) => soles(Number(v)),
  },
]

onMounted(async () => {
  if (!company.current) return
  loading.value = true
  try {
    const id = company.current.id
    const [summary, days, products] = await Promise.all([
      getSummary(id),
      getSalesByDay(id),
      getTopProducts(id),
    ])
    totalFacturado.value = summary.totalFacturado
    numComprobantes.value = summary.numComprobantes
    ticketPromedio.value = summary.ticketPromedio
    salesByDay.value = days
    topProducts.value = products
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
})
</script>
