<template>
  <q-page class="q-pa-md">
    <div class="text-h5 q-mb-md">
      Notas de crédito y débito
    </div>

    <!-- Emisión -->
    <q-card class="q-mb-lg">
      <q-card-section class="q-gutter-md">
        <div class="text-subtitle2">
          Emitir nota
        </div>

        <div class="row q-col-gutter-md">
          <q-select
            v-model="tipoNota"
            class="col-12 col-md-4"
            outlined
            emit-value
            map-options
            :options="tipoOptions"
            label="Tipo de nota"
          />
          <q-select
            v-model="selectedDoc"
            class="col-12 col-md-8"
            outlined
            :options="docOptions"
            emit-value
            map-options
            :loading="loading"
            label="Comprobante a rectificar"
            hint="Solo facturas y boletas aceptadas"
            :rules="[required('Selecciona el comprobante a rectificar')]"
          />
        </div>

        <q-select
          v-model="selectedMotivo"
          outlined
          :options="motivoOptions"
          emit-value
          map-options
          :label="motivoLabel"
          :rules="[required('Selecciona el motivo')]"
        />

        <q-btn
          color="primary"
          icon="assignment_return"
          :label="btnLabel"
          :loading="emitting"
          :disable="!selectedDoc || !selectedMotivo"
          @click="emitir"
        />
      </q-card-section>
    </q-card>

    <!-- Emitidas -->
    <div class="text-subtitle1 q-mb-sm">
      Notas emitidas
    </div>
    <q-table
      :rows="notes"
      :columns="columns"
      row-key="id"
      :loading="loading"
      flat
      bordered
    >
      <template #body-cell-tipo="props">
        <q-td :props="props">
          <q-badge
            :color="props.value === '08' ? 'deep-orange' : 'primary'"
            :label="props.value === '08' ? 'Débito' : 'Crédito'"
          />
        </q-td>
      </template>
      <template #body-cell-estado="props">
        <q-td :props="props">
          <q-badge
            :color="estadoColor(props.value)"
            :label="props.value"
          />
        </q-td>
      </template>
      <template #loading>
        <KTableSkeleton />
      </template>
    </q-table>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { type QTableColumn } from 'quasar'
import { useCompanyStore } from '@/stores/company'
import {
  listAcceptedDocuments,
  listNotes,
  issueNote,
  motivosPorTipo,
  type CreditNoteRow,
} from '@/modules/creditnotes/creditnotes.api'
import { validate, required } from '@/lib/validation'
import { uid } from '@/lib/uid'
import { notify } from '@/lib/toast'
import KTableSkeleton from '@/components/KTableSkeleton.vue'

const company = useCompanyStore()

const accepted = ref<CreditNoteRow[]>([])
const notes = ref<CreditNoteRow[]>([])
const loading = ref(false)
const emitting = ref(false)
const tipoNota = ref<'07' | '08'>('07')
const selectedDoc = ref<string | null>(null)
const selectedMotivo = ref<string | null>(null)

const tipoOptions = [
  { label: 'Nota de crédito (07)', value: '07' },
  { label: 'Nota de débito (08)', value: '08' },
]

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

const motivoOptions = computed(() =>
  motivosPorTipo(tipoNota.value).map((m) => ({
    label: `${m.codigo} · ${m.descripcion}`,
    value: m.codigo,
  })),
)

const motivoLabel = computed(() =>
  tipoNota.value === '08' ? 'Motivo (catálogo SUNAT 10)' : 'Motivo (catálogo SUNAT 09)',
)
const btnLabel = computed(() =>
  tipoNota.value === '08' ? 'Emitir nota de débito' : 'Emitir nota de crédito',
)

// Al cambiar el tipo, el motivo anterior ya no aplica (catálogo distinto).
watch(tipoNota, () => {
  selectedMotivo.value = null
})

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
  { name: 'tipo', label: 'Tipo', field: 'tipo_doc', align: 'left' },
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
  loading.value = !notes.value.length
  try {
    const [acc, ns] = await Promise.all([
      listAcceptedDocuments(company.current.id),
      listNotes(company.current.id),
    ])
    accepted.value = acc
    notes.value = ns
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
}

// Llave de idempotencia estable por intento: si el emit falla y se reintenta, se
// reusa la misma llave para que el RPC NO emita una segunda nota (evita duplicados).
const notaKey = ref<string | null>(null)
// Al cambiar el comprobante a rectificar o el tipo de nota, invalida la llave de
// idempotencia: si no, un reintento tras un fallo emitiría contra el documento anterior
// (el RPC deduplica por la llave ANTES de mirar el comprobante de referencia).
// Incluye selectedMotivo: cambiar el motivo (cat.09/10) altera el contenido fiscal de la nota,
// así que debe invalidar la llave de idempotencia (si no, un reintento reusaría el motivo viejo).
watch([selectedDoc, tipoNota, selectedMotivo], () => {
  notaKey.value = null
})
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
  const motivo = motivosPorTipo(tipoNota.value).find((m) => m.codigo === selectedMotivo.value)
  const tipoTxt = tipoNota.value === '08' ? 'débito' : 'crédito'
  if (!notaKey.value) notaKey.value = uid()
  emitting.value = true
  try {
    const nota = await issueNote(
      company.current.id,
      selectedDoc.value,
      tipoNota.value,
      selectedMotivo.value,
      motivo?.descripcion ?? '',
      undefined,
      notaKey.value,
    )
    notify({
      type: 'positive',
      message: `Nota de ${tipoTxt} ${numero(nota.serie, nota.correlativo)} emitida`,
    })
    selectedDoc.value = null
    selectedMotivo.value = null
    notaKey.value = null // intento cerrado con éxito → próxima nota, nueva llave
    await reload()
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    emitting.value = false
  }
}

onMounted(reload)
</script>
