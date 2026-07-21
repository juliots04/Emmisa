<template>
  <q-page class="q-pa-md">
    <div class="text-h5 q-mb-md">Comprobantes</div>
    <q-table
      :rows="rows"
      :columns="columns"
      row-key="id"
      :loading="loading"
      flat
      bordered
      class="cursor-pointer"
      @row-click="openDetail"
    >
      <template #body-cell-estado="props">
        <q-td :props="props">
          <q-badge :color="estadoColor(props.value)" :label="props.value" />
        </q-td>
      </template>
    </q-table>
  </q-page>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { type QTableColumn } from 'quasar'
import { useCompanyStore } from '@/stores/company'
import { listDocuments } from '@/modules/documents/documents.api'
import { notify } from '@/lib/toast'
import type { DocumentRow } from '@/types'

const company = useCompanyStore()
const router = useRouter()

function openDetail(_evt: Event, row: DocumentRow) {
  router.push({ name: 'document-detail', params: { id: row.id } })
}
const rows = ref<DocumentRow[]>([])
const loading = ref(false)

const columns: QTableColumn<DocumentRow>[] = [
  {
    name: 'numero',
    label: 'Número',
    field: (r) => `${r.serie}-${String(r.correlativo).padStart(8, '0')}`,
    align: 'left',
  },
  {
    name: 'tipo',
    label: 'Tipo',
    field: (r) => (r.tipo_doc === '01' ? 'Factura' : 'Boleta'),
    align: 'left',
  },
  {
    name: 'total',
    label: 'Total',
    field: 'total',
    align: 'right',
    format: (v) => `S/ ${Number(v).toFixed(2)}`,
  },
  { name: 'estado', label: 'Estado', field: 'estado_sunat', align: 'left' },
  {
    name: 'fecha',
    label: 'Fecha',
    field: 'created_at',
    align: 'left',
    format: (v) => new Date(v as string).toLocaleString('es-PE'),
  },
]

function estadoColor(estado: string) {
  if (estado === 'aceptado') return 'positive'
  if (estado === 'rechazado') return 'negative'
  if (estado === 'anulado') return 'grey'
  return 'orange'
}

onMounted(async () => {
  if (!company.current) return
  loading.value = true
  try {
    rows.value = await listDocuments(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
})
</script>
