<template>
  <q-page class="q-pa-md">
    <div class="text-h5 q-mb-md">
      Reportes
    </div>

    <div class="row q-col-gutter-md">
      <div
        v-for="k in kpis"
        :key="k.label"
        class="col-12 col-sm-4"
      >
        <q-card>
          <q-card-section>
            <div class="text-caption text-muted">
              {{ k.label }}
            </div>
            <div class="text-h4">
              {{ k.value }}
            </div>
          </q-card-section>
        </q-card>
      </div>
    </div>

    <q-card class="q-mt-md">
      <q-card-section>
        <div class="text-subtitle1 q-mb-sm">
          Ventas por día
        </div>
        <q-table
          :rows="salesByDay"
          :columns="dayColumns"
          row-key="fecha"
          :loading="loading"
          :pagination="pagination"
          flat
          bordered
          hide-pagination
        >
          <template #loading>
            <KTableSkeleton />
          </template>
        </q-table>
      </q-card-section>
    </q-card>

    <q-card class="q-mt-md">
      <q-card-section>
        <div class="text-subtitle1 q-mb-sm">
          Productos más vendidos
        </div>
        <q-table
          :rows="topProducts"
          :columns="productColumns"
          row-key="descripcion"
          :loading="loading"
          :pagination="pagination"
          flat
          bordered
          hide-pagination
        >
          <template #loading>
            <KTableSkeleton />
          </template>
        </q-table>
      </q-card-section>
    </q-card>

    <!-- ==================== LIBROS ELECTRÓNICOS (PLE) ==================== -->
    <q-card class="q-mt-md">
      <q-card-section>
        <div class="text-subtitle1 q-mb-xs">
          Libros Electrónicos (PLE)
        </div>
        <div class="text-caption text-muted q-mb-md">
          Registro de Ventas (14.1) y de Compras (8.1) en formato SUNAT. Valida el archivo con el
          <b>Validador SUNAT PLE</b> (herramienta offline gratuita) antes de presentarlo.
        </div>
        <div class="row q-col-gutter-md items-end">
          <div class="col-12 col-sm-4">
            <q-select
              v-model="periodo"
              outlined
              dense
              emit-value
              map-options
              :options="periodOptions"
              label="Periodo"
            />
          </div>
          <div class="col-auto">
            <q-btn
              color="primary"
              outline
              no-caps
              icon="download"
              label="Registro de Ventas"
              :loading="pleBusy"
              @click="descargarVentas"
            />
          </div>
          <div class="col-auto">
            <q-btn
              color="primary"
              outline
              no-caps
              icon="download"
              label="Registro de Compras"
              :loading="pleBusy"
              @click="descargarCompras"
            />
          </div>
        </div>
      </q-card-section>
    </q-card>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { type QTableColumn } from 'quasar'
import KTableSkeleton from '@/components/KTableSkeleton.vue'
import { useCompanyStore } from '@/stores/company'
import { notify } from '@/lib/toast'
import {
  getSalesByDay,
  getSummary,
  getTopProducts,
  type SalesByDay,
  type TopProduct,
} from '@/modules/reports/reports.api'
import { listAllDocuments, getDocumentsByIds } from '@/modules/documents/documents.api'
import { listPurchasesForPle } from '@/modules/purchases/purchases.api'
import { pleRegistroVentas, pleRegistroCompras, descargarPle } from '@/lib/ple'

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

// ---------- Libros Electrónicos (PLE) ----------
const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']
function currentMonth(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
}
// Últimos 12 periodos como opciones (p.ej. { label: 'Julio 2026', value: '2026-07' }).
const periodOptions = computed(() => {
  const opts: { label: string; value: string }[] = []
  const d = new Date()
  let y = d.getFullYear()
  let m = d.getMonth()
  for (let i = 0; i < 12; i++) {
    opts.push({ label: `${MESES[m]} ${y}`, value: `${y}-${String(m + 1).padStart(2, '0')}` })
    m--
    if (m < 0) {
      m = 11
      y--
    }
  }
  return opts
})
const periodo = ref(currentMonth())
const pleBusy = ref(false)

function rangoPeriodo(p: string): { desde: string; hasta: string } {
  const [y, m] = p.split('-').map(Number)
  const last = new Date(y, m, 0).getDate()
  return { desde: `${p}-01`, hasta: `${p}-${String(last).padStart(2, '0')}` }
}

async function descargarVentas() {
  if (!company.current) return
  pleBusy.value = true
  try {
    const { desde, hasta } = rangoPeriodo(periodo.value)
    const docs = await listAllDocuments(company.current.id, { desde, hasta })
    // Resuelve los comprobantes que rectifican las NC/ND aunque sean de otro periodo,
    // para no dejar vacíos los campos 28-31 del Registro de Ventas.
    const known = new Set(docs.map((d) => d.id))
    const refIds = [
      ...new Set(
        docs
          .filter((d) => (d.tipo_doc === '07' || d.tipo_doc === '08') && d.ref_document_id && !known.has(d.ref_document_id))
          .map((d) => d.ref_document_id as string),
      ),
    ]
    const referencias = await getDocumentsByIds(company.current.id, refIds)
    const file = pleRegistroVentas(docs, periodo.value, company.current.ruc, referencias)
    descargarPle(file)
    const n = docs.filter((d) => d.estado_sunat === 'aceptado').length
    notify({ type: 'positive', message: `Registro de Ventas generado (${n} comprobante(s))` })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    pleBusy.value = false
  }
}

async function descargarCompras() {
  if (!company.current) return
  pleBusy.value = true
  try {
    const { desde, hasta } = rangoPeriodo(periodo.value)
    const compras = await listPurchasesForPle(company.current.id, desde, hasta)
    const file = pleRegistroCompras(compras, periodo.value, company.current.ruc)
    descargarPle(file)
    notify({ type: 'positive', message: `Registro de Compras generado (${compras.length} registro(s))` })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    pleBusy.value = false
  }
}

onMounted(async () => {
  if (!company.current) return
  loading.value = !salesByDay.value.length && !topProducts.value.length
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
