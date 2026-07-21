<template>
  <q-page class="q-pa-md">
    <div class="text-h5 q-mb-md">Configuración</div>

    <q-card class="q-mb-md">
      <q-card-section class="text-h6">Datos de la empresa</q-card-section>
      <q-card-section class="q-gutter-sm">
        <q-input v-model="companyForm.ruc" outlined readonly label="RUC" />
        <q-input
          v-model="companyForm.razon_social"
          outlined
          label="Razón social"
          :rules="nameRules"
        />
        <q-input
          v-model="companyForm.direccion"
          outlined
          label="Dirección"
          :rules="[maxLen(200)]"
        />
        <q-select
          v-model="companyForm.regimen"
          outlined
          :options="regimenOptions"
          emit-value
          map-options
          label="Régimen"
          :rules="[required('Selecciona un régimen')]"
        />
      </q-card-section>
      <q-card-actions align="right">
        <q-btn color="primary" label="Guardar" :loading="savingCompany" @click="saveCompany" />
      </q-card-actions>
    </q-card>

    <q-card>
      <q-card-section class="row items-center">
        <div class="text-h6">Series</div>
        <q-space />
        <q-btn color="primary" icon="add" label="Nueva serie" @click="openNewSerie" />
      </q-card-section>
      <q-card-section>
        <q-table
          :rows="seriesRows"
          :columns="seriesColumns"
          row-key="id"
          :loading="loadingSeries"
          flat
          bordered
        />
      </q-card-section>
    </q-card>

    <q-dialog v-model="showSerie">
      <q-card style="min-width: 340px">
        <q-card-section class="text-h6">Nueva serie</q-card-section>
        <q-card-section class="q-gutter-sm">
          <q-select
            v-model="serieForm.tipo_doc"
            outlined
            :options="tipoDocOptions"
            emit-value
            map-options
            label="Tipo de documento"
            :rules="[required('Selecciona el tipo de documento')]"
          />
          <q-input
            v-model="serieForm.serie"
            outlined
            label="Serie"
            hint="Ej. F001"
            autofocus
            :rules="serieRules"
          />
        </q-card-section>
        <q-card-actions align="right">
          <q-btn v-close-popup flat label="Cancelar" />
          <q-btn color="primary" label="Guardar" :loading="savingSerie" @click="saveSerie" />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { type QTableColumn } from 'quasar'
import { useCompanyStore } from '@/stores/company'
import {
  updateCompany,
  listSeries,
  createSerie,
  type Serie,
  type SerieTipoDoc,
} from '@/modules/settings/settings.api'
import type { Regimen } from '@/types'
import { validate, required, nameRules, maxLen, type Rule } from '@/lib/validation'
import { notify } from '@/lib/toast'

const company = useCompanyStore()

const companyForm = ref<{ ruc: string; razon_social: string; direccion: string; regimen: Regimen }>({
  ruc: '',
  razon_social: '',
  direccion: '',
  regimen: 'RER',
})
const savingCompany = ref(false)

const regimenOptions: { label: string; value: Regimen }[] = [
  { label: 'RER', value: 'RER' },
  { label: 'RMT', value: 'RMT' },
  { label: 'GENERAL', value: 'GENERAL' },
  { label: 'NRUS', value: 'NRUS' },
]

const seriesRows = ref<Serie[]>([])
const loadingSeries = ref(false)
const showSerie = ref(false)
const savingSerie = ref(false)
const serieForm = ref<{ tipo_doc: SerieTipoDoc; serie: string }>({ tipo_doc: '01', serie: '' })

const serieRules: Rule[] = [
  required('Serie obligatoria'),
  (v) => /^[A-Za-z][A-Za-z0-9]{3}$/.test(String(v ?? '').trim()) || 'Serie inválida (ej. F001)',
]

const tipoDocOptions: { label: string; value: SerieTipoDoc }[] = [
  { label: 'Factura', value: '01' },
  { label: 'Boleta', value: '03' },
  { label: 'Nota crédito', value: '07' },
  { label: 'Nota débito', value: '08' },
]

const tipoDocLabels: Record<SerieTipoDoc, string> = {
  '01': 'Factura',
  '03': 'Boleta',
  '07': 'Nota crédito',
  '08': 'Nota débito',
}

const seriesColumns: QTableColumn<Serie>[] = [
  { name: 'serie', label: 'Serie', field: 'serie', align: 'left', sortable: true },
  {
    name: 'tipo_doc',
    label: 'Tipo',
    field: (r) => tipoDocLabels[r.tipo_doc] ?? r.tipo_doc,
    align: 'left',
  },
  { name: 'correlativo', label: 'Correlativo', field: 'correlativo', align: 'right' },
]

function fillCompanyForm() {
  if (!company.current) return
  companyForm.value = {
    ruc: company.current.ruc,
    razon_social: company.current.razon_social,
    direccion: company.current.direccion ?? '',
    regimen: company.current.regimen,
  }
}

async function loadSeries() {
  if (!company.current) return
  loadingSeries.value = true
  try {
    seriesRows.value = await listSeries(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loadingSeries.value = false
  }
}

async function saveCompany() {
  if (!company.current) return
  const err = validate([
    [companyForm.value.razon_social, nameRules],
    [companyForm.value.direccion, [maxLen(200)]],
    [companyForm.value.regimen, [required('Selecciona un régimen')]],
  ])
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  savingCompany.value = true
  try {
    const updated = await updateCompany(company.current.id, {
      razon_social: companyForm.value.razon_social,
      direccion: companyForm.value.direccion,
      regimen: companyForm.value.regimen,
    })
    await company.load()
    companyForm.value = {
      ruc: updated.ruc,
      razon_social: updated.razon_social,
      direccion: updated.direccion ?? '',
      regimen: updated.regimen,
    }
    notify({ type: 'positive', message: 'Datos actualizados' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    savingCompany.value = false
  }
}

function openNewSerie() {
  serieForm.value = { tipo_doc: '01', serie: '' }
  showSerie.value = true
}

async function saveSerie() {
  if (!company.current) return
  const err = validate([
    [serieForm.value.tipo_doc, [required('Selecciona el tipo de documento')]],
    [serieForm.value.serie, serieRules],
  ])
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  savingSerie.value = true
  try {
    await createSerie(company.current.id, serieForm.value)
    showSerie.value = false
    await loadSeries()
    notify({ type: 'positive', message: 'Serie creada' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    savingSerie.value = false
  }
}

onMounted(() => {
  fillCompanyForm()
  loadSeries()
})
</script>
