<template>
  <q-page class="q-pa-md">
    <div class="text-h5 q-mb-md">Notas de crédito</div>

    <!-- Emisión -->
    <q-card class="q-mb-lg">
      <q-card-section class="q-gutter-md">
        <div class="text-subtitle2">Emitir nota de crédito</div>

        <div class="row q-col-gutter-md">
          <q-select
            v-model="selectedDoc"
            class="col-12 col-md-6"
            outlined
            :options="docOptions"
            emit-value
            map-options
            :loading="loading"
            label="Comprobante a rectificar"
            hint="Solo facturas y boletas aceptadas"
            :rules="[required('Selecciona el comprobante a rectificar')]"
          />
          <q-select
            v-model="selectedMotivo"
            class="col-12 col-md-6"
            outlined
            :options="motivoOptions"
            emit-value
            map-options
            label="Motivo (catálogo SUNAT 09)"
            :rules="[required('Selecciona el motivo')]"
          />
        </div>

        <q-btn
          color="primary"
          icon="assignment_return"
          label="Emitir nota de crédito"
          :loading="emitting"
          :disable="!selectedDoc || !selectedMotivo"
          @click="emitir"
        />
      </q-card-section>
    </q-card>

    <!-- Emitidas -->
    <div class="text-subtitle1 q-mb-sm">Notas de crédito emitidas</div>
    <q-table :rows="creditNotes" :columns="columns" row-key="id" :loading="loading" flat bordered>
      <template #body-cell-estado="props">
        <q-td :props="props">
          <q-badge :color="estadoColor(props.value)" :label="props.value" />
        </q-td>
      </template>
    </q-table>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { type QTableColumn } from 'quasar'
import { useCompanyStore } from '@/stores/company'
import {
  listAcceptedDocuments,
  listCreditNotes,
  issueCreditNote,
  MOTIVOS_NC,
  type CreditNoteRow,
} from '@/modules/creditnotes/creditnotes.api'
import { validate, required } from '@/lib/validation'
import { notify } from '@/lib/toast'

const company = useCompanyStore()

const accepted = ref<CreditNoteRow[]>([])
const creditNotes = ref<CreditNoteRow[]>([])
const loading = ref(false)
const emitting = ref(false)
const selectedDoc = ref<string | null>(null)
const selectedMotivo = ref<string | null>(null)

function numero(serie: string, correlativo: number) {
  return `${serie}-${String(correlativo).padStart(8, '0')}`
}

function tipoLabel(tipoDoc: string) {
  if (tipoDoc === '01') return 'Factura'
  if (tipoDoc === '03') return 'Boleta'
  return 'Comprobante'
}

const docOptions = computed(() =>
  accepted.value.map((d) => ({
    label: `${numero(d.serie, d.correlativo)} · ${tipoLabel(d.tipo_doc)} · S/ ${Number(d.total).toFixed(2)}`,
    value: d.id,
  })),
)

const motivoOptions = MOTIVOS_NC.map((m) => ({
  label: `${m.codigo} · ${m.descripcion}`,
  value: m.codigo,
}))

function refNumero(id: string | null) {
  if (!id) return '—'
  const d = accepted.value.find((x) => x.id === id)
  return d ? numero(d.serie, d.correlativo) : '—'
}

const columns: QTableColumn<CreditNoteRow>[] = [
  {
    name: 'numero',
    label: 'Número',
    field: (r) => numero(r.serie, r.correlativo),
    align: 'left',
  },
  {
    name: 'afecta',
    label: 'Afecta a',
    field: (r) => refNumero(r.ref_document_id),
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

async function reload() {
  if (!company.current) return
  loading.value = true
  try {
    const [acc, ncs] = await Promise.all([
      listAcceptedDocuments(company.current.id),
      listCreditNotes(company.current.id),
    ])
    accepted.value = acc
    creditNotes.value = ncs
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
}

async function emitir() {
  if (!company.current) return
  const err = validate([
    [selectedDoc.value, [required('Selecciona el comprobante a rectificar')]],
    [selectedMotivo.value, [required('Selecciona el motivo')]],
  ])
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  if (!selectedDoc.value || !selectedMotivo.value) return
  const motivo = MOTIVOS_NC.find((m) => m.codigo === selectedMotivo.value)
  emitting.value = true
  try {
    const nc = await issueCreditNote(
      company.current.id,
      selectedDoc.value,
      selectedMotivo.value,
      motivo?.descripcion ?? '',
    )
    notify({
      type: 'positive',
      message: `Nota de crédito ${numero(nc.serie, nc.correlativo)} emitida`,
    })
    selectedDoc.value = null
    selectedMotivo.value = null
    await reload()
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    emitting.value = false
  }
}

onMounted(reload)
</script>
