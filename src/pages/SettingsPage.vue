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

    <q-card class="q-mb-md">
      <q-card-section class="row items-center">
        <div class="text-h6">Motor SUNAT (APISUNAT)</div>
        <q-space />
        <q-chip
          :color="hasCreds ? 'positive' : 'grey-5'"
          text-color="white"
          :icon="hasCreds ? 'check_circle' : 'info'"
          :label="hasCreds ? 'Configurado' : 'Sin configurar (modo simulado)'"
        />
      </q-card-section>
      <q-card-section class="q-gutter-sm">
        <div class="text-caption text-grey-7">
          Pega tu Persona ID y Token de APISUNAT. El token se guarda cifrado y
          <b>nunca se lee de vuelta</b> desde la app; solo la Edge Function lo usa para emitir.
        </div>
        <q-select
          v-model="credForm.provider"
          outlined
          dense
          :options="[{ label: 'APISUNAT', value: 'apisunat' }, { label: 'Nubefact', value: 'nubefact' }]"
          emit-value
          map-options
          label="Proveedor"
        />
        <q-input v-model="credForm.personaId" outlined dense label="Persona ID" />
        <q-input
          v-model="credForm.token"
          outlined
          dense
          type="password"
          label="Token"
          hint="Se guarda de forma segura; déjalo vacío para no cambiarlo"
        />
      </q-card-section>
      <q-card-actions align="right">
        <q-btn color="primary" label="Guardar credenciales" :loading="savingCreds" @click="saveCreds" />
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
        >
          <template #body-cell-acciones="props">
            <q-td :props="props" class="text-right">
              <q-btn flat round dense icon="delete" size="sm" color="negative" @click="removeSerie(props.row)" />
            </q-td>
          </template>
        </q-table>
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
import { useQuasar, type QTableColumn } from 'quasar'
import { useCompanyStore } from '@/stores/company'
import {
  updateCompany,
  listSeries,
  createSerie,
  deleteSerie,
  tieneCredenciales,
  guardarCredenciales,
  type Serie,
  type SerieTipoDoc,
} from '@/modules/settings/settings.api'
import type { Regimen } from '@/types'
import { validate, required, nameRules, maxLen, type Rule } from '@/lib/validation'
import { notify } from '@/lib/toast'

const $q = useQuasar()
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

// Credenciales del emisor
const hasCreds = ref(false)
const savingCreds = ref(false)
const credForm = ref<{ provider: string; personaId: string; token: string }>({
  provider: 'apisunat',
  personaId: '',
  token: '',
})

async function loadCreds() {
  if (!company.current) return
  try {
    hasCreds.value = await tieneCredenciales(company.current.id)
  } catch {
    /* la migración de plataforma puede no estar aplicada aún */
  }
}

async function saveCreds() {
  if (!company.current) return
  if (!credForm.value.personaId || !credForm.value.token) {
    notify({ type: 'warning', message: 'Completa Persona ID y Token' })
    return
  }
  savingCreds.value = true
  try {
    await guardarCredenciales(company.current.id, {
      provider: credForm.value.provider,
      personaId: credForm.value.personaId,
      token: credForm.value.token,
    })
    credForm.value.token = ''
    await loadCreds()
    notify({ type: 'positive', message: 'Credenciales guardadas' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    savingCreds.value = false
  }
}

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
  { name: 'acciones', label: '', field: 'id', align: 'right' },
]

function removeSerie(row: Serie) {
  $q.dialog({
    title: 'Eliminar serie',
    message: `¿Eliminar la serie "${row.serie}"? Si ya emitiste con ella, el correlativo se reiniciaría al recrearla.`,
    cancel: true,
    persistent: true,
  }).onOk(async () => {
    try {
      await deleteSerie(row.id)
      await loadSeries()
      notify({ type: 'positive', message: 'Serie eliminada' })
    } catch (e) {
      notify({ type: 'negative', message: (e as Error).message })
    }
  })
}

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
  loadCreds()
})
</script>
