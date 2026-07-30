<template>
  <q-page class="q-pa-md">
    <div class="text-h5 q-mb-md">Configuración</div>

    <q-card class="q-mb-md">
      <q-card-section class="text-h6"> Datos de la empresa </q-card-section>

      <q-card-section class="row items-center q-gutter-md">
        <div class="k-logo-box">
          <img
            v-if="company.current?.logo_url"
            :src="company.current.logo_url"
            alt="Logo"
            class="k-logo-img"
          />
          <q-icon v-else name="storefront" size="30px" class="text-grey-6" />
        </div>
        <div class="column q-gutter-xs">
          <div class="text-caption text-grey-7">Logo de la empresa · se muestra en el sistema</div>
          <div class="row q-gutter-sm">
            <q-btn
              outline
              dense
              no-caps
              icon="upload"
              :label="company.current?.logo_url ? 'Cambiar' : 'Subir logo'"
              :loading="uploadingLogo"
              @click="pickLogo"
            />
            <q-btn
              v-if="company.current?.logo_url"
              flat
              dense
              no-caps
              color="negative"
              icon="delete"
              label="Quitar"
              :disable="uploadingLogo"
              @click="removeLogo"
            />
          </div>
        </div>
        <input ref="logoInput" type="file" accept="image/*" hidden @change="onLogoFile" />
      </q-card-section>

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
        <div class="text-h6">Emmisa Fiscal API</div>
        <q-space />
        <q-chip
          :color="fiscalStatus.configured ? 'positive' : 'grey-5'"
          text-color="white"
          :icon="fiscalStatus.configured ? 'check_circle' : 'info'"
          :label="fiscalStatus.configured ? 'Conectado' : 'Pendiente de conexión'"
        />
      </q-card-section>
      <q-card-section class="q-gutter-sm">
        <div>
          Emisión directa mediante nuestra API independiente, sin PSE de terceros.
        </div>
        <div class="text-caption text-grey-7">
          La API key está protegida como secreto del backend y nunca se envía a este
          navegador. El emisor se valida contra el RUC de esta empresa antes de emitir.
        </div>
        <q-badge
          v-if="fiscalStatus.configured"
          outline
          color="primary"
          :label="fiscalStatus.environment === 'production' ? 'Producción' : 'Beta SUNAT'"
        />
      </q-card-section>
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
              <q-btn
                flat
                round
                dense
                icon="delete"
                size="sm"
                color="negative"
                @click="removeSerie(props.row)"
              />
            </q-td>
          </template>
          <template #loading>
            <KTableSkeleton />
          </template>
        </q-table>
      </q-card-section>
    </q-card>

    <q-dialog v-model="showSerie">
      <q-card class="k-dialog-sm">
        <q-card-section class="k-modal-head">
          <div class="text-h6">Nueva serie</div>
          <q-space />
          <q-btn v-close-popup flat dense round icon="close" aria-label="Cerrar" />
        </q-card-section>
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
import KTableSkeleton from '@/components/KTableSkeleton.vue'
import {
  updateCompany,
  uploadCompanyLogo,
  listSeries,
  createSerie,
  deleteSerie,
  estadoIntegracionFiscal,
  type FiscalIntegrationStatus,
  type Serie,
  type SerieTipoDoc,
} from '@/modules/settings/settings.api'
import type { Regimen } from '@/types'
import { validate, required, nameRules, maxLen, type Rule } from '@/lib/validation'
import { notify } from '@/lib/toast'

const $q = useQuasar()
const company = useCompanyStore()

const companyForm = ref<{ ruc: string; razon_social: string; direccion: string; regimen: Regimen }>(
  {
    ruc: '',
    razon_social: '',
    direccion: '',
    regimen: 'RER',
  },
)
const savingCompany = ref(false)
const uploadingLogo = ref(false)
const logoInput = ref<HTMLInputElement | null>(null)

const regimenOptions: { label: string; value: Regimen }[] = [
  { label: 'RER', value: 'RER' },
  { label: 'RMT', value: 'RMT' },
  { label: 'GENERAL', value: 'GENERAL' },
  { label: 'NRUS', value: 'NRUS' },
]

const fiscalStatus = ref<FiscalIntegrationStatus>({
  configured: false,
  environment: null,
})

async function loadCreds() {
  if (!company.current) return
  try {
    fiscalStatus.value = await estadoIntegracionFiscal(company.current.id)
  } catch {
    fiscalStatus.value = { configured: false, environment: null }
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
    if (!company.current) return
    try {
      await deleteSerie(company.current.id, row.id)
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
  loadingSeries.value = !seriesRows.value.length
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
    await company.load(true)
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

function pickLogo() {
  logoInput.value?.click()
}
async function onLogoFile(e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (!file || !company.current) return
  uploadingLogo.value = true
  try {
    const url = await uploadCompanyLogo(company.current.id, file)
    await updateCompany(company.current.id, {
      razon_social: company.current.razon_social,
      direccion: company.current.direccion,
      regimen: company.current.regimen,
      logo_url: url,
    })
    await company.load(true)
    notify({ type: 'positive', message: 'Logo actualizado' })
  } catch (err) {
    notify({ type: 'negative', message: (err as Error).message })
  } finally {
    uploadingLogo.value = false
    if (logoInput.value) logoInput.value.value = ''
  }
}
async function removeLogo() {
  if (!company.current) return
  uploadingLogo.value = true
  try {
    await updateCompany(company.current.id, {
      razon_social: company.current.razon_social,
      direccion: company.current.direccion,
      regimen: company.current.regimen,
      logo_url: null,
    })
    await company.load(true)
    notify({ type: 'positive', message: 'Logo quitado' })
  } catch (err) {
    notify({ type: 'negative', message: (err as Error).message })
  } finally {
    uploadingLogo.value = false
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

<style scoped>
.k-logo-box {
  width: 64px;
  height: 64px;
  border-radius: 14px;
  background: var(--k-surface-2);
  border: 1px solid var(--k-border);
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  flex-shrink: 0;
}
.k-logo-img {
  width: 100%;
  height: 100%;
  object-fit: contain;
}
</style>
