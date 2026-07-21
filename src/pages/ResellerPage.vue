<template>
  <q-page class="q-pa-md">
    <div class="row items-center q-mb-md">
      <div class="text-h5">Panel del revendedor</div>
      <q-space />
      <q-chip v-if="reseller" color="primary" text-color="white" icon="storefront" :label="reseller.nombre" />
    </div>

    <!-- Sin revendedor: crear -->
    <q-card v-if="!reseller" class="q-pa-md">
      <div class="text-h6 q-mb-sm">Activa tu marca blanca</div>
      <div class="text-body2 text-grey-7 q-mb-md">
        Crea tu revendedor para gestionar varias empresas emisoras bajo tu marca,
        con tus planes y tu branding.
      </div>
      <div class="row q-col-gutter-sm">
        <q-input v-model="newReseller.nombre" outlined dense label="Nombre comercial" class="col-12 col-sm-5" />
        <q-input v-model="newReseller.dominio" outlined dense label="Dominio (opcional)" class="col-12 col-sm-5" />
        <div class="col-12 col-sm-2">
          <q-btn color="primary" label="Crear" class="full-width" :loading="creating" @click="doCreateReseller" />
        </div>
      </div>
    </q-card>

    <template v-else>
      <q-tabs v-model="tab" align="left" class="text-primary q-mb-md" dense>
        <q-tab name="empresas" label="Empresas" icon="business" />
        <q-tab name="planes" label="Planes" icon="workspace_premium" />
        <q-tab name="suscripciones" label="Suscripciones" icon="event_repeat" />
        <q-tab name="marca" label="Marca" icon="palette" />
      </q-tabs>

      <q-tab-panels v-model="tab" animated>
        <!-- ===== Empresas ===== -->
        <q-tab-panel name="empresas">
          <q-table :rows="companies" :columns="companyCols" row-key="id" :loading="loading" flat bordered>
            <template #top>
              <div class="text-subtitle1">Empresas de tu marca ({{ companies.length }})</div>
              <q-space />
              <q-select
                v-if="unassigned.length"
                v-model="companyToAdd"
                outlined
                dense
                :options="unassignedOptions"
                emit-value
                map-options
                label="Agregar empresa existente"
                style="min-width: 240px"
                @update:model-value="doAssign"
              />
            </template>
          </q-table>
        </q-tab-panel>

        <!-- ===== Planes ===== -->
        <q-tab-panel name="planes">
          <div class="row items-center q-mb-sm">
            <div class="text-subtitle1">Planes</div>
            <q-space />
            <q-btn color="primary" icon="add" label="Nuevo plan" @click="showPlan = true" />
          </div>
          <q-table :rows="plans" :columns="planCols" row-key="id" :loading="loading" flat bordered>
            <template #body-cell-acciones="props">
              <q-td :props="props" class="text-right">
                <q-btn flat round dense icon="delete" color="negative" @click="doDeletePlan(props.row.id)" />
              </q-td>
            </template>
          </q-table>
        </q-tab-panel>

        <!-- ===== Suscripciones ===== -->
        <q-tab-panel name="suscripciones">
          <div class="row items-center q-mb-sm">
            <div class="text-subtitle1">Suscripciones</div>
            <q-space />
            <q-btn color="primary" icon="add" label="Nueva suscripción" :disable="!plans.length || !companies.length" @click="showSub = true" />
          </div>
          <q-table :rows="subsView" :columns="subCols" row-key="id" :loading="loading" flat bordered>
            <template #body-cell-acciones="props">
              <q-td :props="props" class="text-right">
                <q-btn-dropdown flat dense label="Estado" size="sm">
                  <q-list>
                    <q-item v-for="e in ['activa', 'suspendida', 'vencida', 'cancelada']" :key="e" v-close-popup clickable @click="doSetEstado(props.row.id, e)">
                      <q-item-section>{{ e }}</q-item-section>
                    </q-item>
                  </q-list>
                </q-btn-dropdown>
              </q-td>
            </template>
          </q-table>
        </q-tab-panel>

        <!-- ===== Marca ===== -->
        <q-tab-panel name="marca">
          <div class="text-subtitle1 q-mb-sm">Branding de tu marca</div>
          <div class="row q-col-gutter-md" style="max-width: 640px">
            <q-input v-model="branding.nombre_comercial" outlined dense label="Nombre comercial" class="col-12 col-sm-6" />
            <q-input v-model="branding.logo_url" outlined dense label="URL del logo" class="col-12 col-sm-6" />
            <q-input v-model="branding.color_primario" outlined dense label="Color primario" class="col-12 col-sm-6">
              <template #append><input v-model="branding.color_primario" type="color" /></template>
            </q-input>
            <q-input v-model="branding.color_secundario" outlined dense label="Color secundario" class="col-12 col-sm-6">
              <template #append><input v-model="branding.color_secundario" type="color" /></template>
            </q-input>
            <div class="col-12 text-right">
              <q-btn color="primary" label="Guardar marca" :loading="savingBrand" @click="doSaveBranding" />
            </div>
          </div>
        </q-tab-panel>
      </q-tab-panels>
    </template>

    <!-- Diálogo: nuevo plan -->
    <q-dialog v-model="showPlan">
      <q-card style="min-width: 360px">
        <q-card-section class="text-h6">Nuevo plan</q-card-section>
        <q-card-section class="q-gutter-sm">
          <q-input v-model="planForm.nombre" outlined dense label="Nombre" autofocus />
          <div class="row q-col-gutter-sm">
            <q-input v-model.number="planForm.precio" outlined dense type="number" label="Precio" class="col-6" />
            <q-select v-model="planForm.periodicidad" outlined dense :options="['mensual', 'anual']" label="Periodicidad" class="col-6" />
          </div>
          <div class="text-caption text-grey-7">Límites (0 = ilimitado)</div>
          <div class="row q-col-gutter-sm">
            <q-input v-model.number="planForm.max_comprobantes" outlined dense type="number" label="Comprobantes/mes" class="col-4" />
            <q-input v-model.number="planForm.max_empresas" outlined dense type="number" label="Empresas" class="col-4" />
            <q-input v-model.number="planForm.max_usuarios" outlined dense type="number" label="Usuarios" class="col-4" />
          </div>
        </q-card-section>
        <q-card-actions align="right">
          <q-btn v-close-popup flat label="Cancelar" />
          <q-btn color="primary" label="Guardar" :loading="savingPlan" @click="doCreatePlan" />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <!-- Diálogo: nueva suscripción -->
    <q-dialog v-model="showSub">
      <q-card style="min-width: 360px">
        <q-card-section class="text-h6">Nueva suscripción</q-card-section>
        <q-card-section class="q-gutter-sm">
          <q-select v-model="subForm.companyId" outlined dense :options="companyOptions" emit-value map-options label="Empresa" />
          <q-select v-model="subForm.planId" outlined dense :options="planOptions" emit-value map-options label="Plan" />
          <q-input v-model="subForm.periodoFin" outlined dense type="date" label="Vence (opcional)" />
        </q-card-section>
        <q-card-actions align="right">
          <q-btn v-close-popup flat label="Cancelar" />
          <q-btn color="primary" label="Crear" :loading="savingSub" @click="doCreateSub" />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import type { QTableColumn } from 'quasar'
import { notify } from '@/lib/toast'
import {
  getMyReseller,
  createReseller,
  updateBranding,
  listPlans,
  createPlan,
  deletePlan,
  listResellerCompanies,
  listUnassignedCompanies,
  assignCompany,
  listSubscriptions,
  createSubscription,
  setSubscriptionEstado,
  type Reseller,
  type Plan,
  type ResellerCompany,
  type Subscription,
} from '@/modules/reseller/reseller.api'

const tab = ref('empresas')
const loading = ref(false)
const reseller = ref<Reseller | null>(null)
const plans = ref<Plan[]>([])
const companies = ref<ResellerCompany[]>([])
const unassigned = ref<ResellerCompany[]>([])
const subs = ref<Subscription[]>([])

const newReseller = ref({ nombre: '', dominio: '' })
const creating = ref(false)

const branding = ref<NonNullable<Reseller['branding']>>({
  nombre_comercial: '',
  logo_url: '',
  color_primario: '#6366f1',
  color_secundario: '#22c55e',
})
const savingBrand = ref(false)

const showPlan = ref(false)
const savingPlan = ref(false)
const planForm = ref({ nombre: '', precio: 0, periodicidad: 'mensual', max_comprobantes: 0, max_empresas: 0, max_usuarios: 0 })

const showSub = ref(false)
const savingSub = ref(false)
const subForm = ref<{ companyId: string | null; planId: string | null; periodoFin: string }>({ companyId: null, planId: null, periodoFin: '' })

const companyToAdd = ref<string | null>(null)

const companyCols: QTableColumn<ResellerCompany>[] = [
  { name: 'razon_social', label: 'Empresa', field: 'razon_social', align: 'left', sortable: true },
  { name: 'ruc', label: 'RUC', field: 'ruc', align: 'left' },
  { name: 'estado', label: 'Estado', field: 'estado', align: 'left' },
]
const planCols: QTableColumn<Plan>[] = [
  { name: 'nombre', label: 'Plan', field: 'nombre', align: 'left' },
  { name: 'precio', label: 'Precio', field: (r) => `${r.moneda} ${r.precio}`, align: 'right' },
  { name: 'periodicidad', label: 'Periodo', field: 'periodicidad', align: 'left' },
  { name: 'limites', label: 'Límites', field: (r) => `${r.limites?.max_comprobantes || '∞'} cbte · ${r.limites?.max_usuarios || '∞'} usr`, align: 'left' },
  { name: 'acciones', label: '', field: 'id', align: 'right' },
]
const subCols: QTableColumn<Subscription & { empresa?: string; plan?: string }>[] = [
  { name: 'empresa', label: 'Empresa', field: 'empresa', align: 'left' },
  { name: 'plan', label: 'Plan', field: 'plan', align: 'left' },
  { name: 'estado', label: 'Estado', field: 'estado', align: 'left' },
  { name: 'periodo_fin', label: 'Vence', field: (r) => r.periodo_fin ?? '—', align: 'left' },
  { name: 'acciones', label: '', field: 'id', align: 'right' },
]

const unassignedOptions = computed(() => unassigned.value.map((c) => ({ label: `${c.razon_social} (${c.ruc})`, value: c.id })))
const companyOptions = computed(() => companies.value.map((c) => ({ label: c.razon_social, value: c.id })))
const planOptions = computed(() => plans.value.map((p) => ({ label: `${p.nombre} — ${p.moneda} ${p.precio}`, value: p.id })))
const subsView = computed(() =>
  subs.value.map((s) => ({
    ...s,
    empresa: companies.value.find((c) => c.id === s.company_id)?.razon_social ?? '—',
    plan: plans.value.find((p) => p.id === s.plan_id)?.nombre ?? '—',
  })),
)

async function loadAll() {
  loading.value = true
  try {
    reseller.value = await getMyReseller()
    if (!reseller.value) return
    if (reseller.value.branding) branding.value = { ...branding.value, ...reseller.value.branding }
    const [pl, co, un] = await Promise.all([
      listPlans(reseller.value.id),
      listResellerCompanies(reseller.value.id),
      listUnassignedCompanies(),
    ])
    plans.value = pl
    companies.value = co
    unassigned.value = un
    subs.value = await listSubscriptions(co.map((c) => c.id))
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
}

async function doCreateReseller() {
  if (!newReseller.value.nombre) {
    notify({ type: 'warning', message: 'Ingresa el nombre' })
    return
  }
  creating.value = true
  try {
    reseller.value = await createReseller({ nombre: newReseller.value.nombre, dominio: newReseller.value.dominio || undefined })
    await loadAll()
    notify({ type: 'positive', message: 'Revendedor creado' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    creating.value = false
  }
}

async function doAssign(companyId: string) {
  if (!reseller.value || !companyId) return
  try {
    await assignCompany(companyId, reseller.value.id)
    companyToAdd.value = null
    await loadAll()
    notify({ type: 'positive', message: 'Empresa agregada a tu marca' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  }
}

async function doCreatePlan() {
  if (!reseller.value || !planForm.value.nombre) {
    notify({ type: 'warning', message: 'Ingresa el nombre del plan' })
    return
  }
  savingPlan.value = true
  try {
    await createPlan(reseller.value.id, {
      nombre: planForm.value.nombre,
      precio: planForm.value.precio,
      periodicidad: planForm.value.periodicidad,
      limites: {
        max_comprobantes: planForm.value.max_comprobantes,
        max_empresas: planForm.value.max_empresas,
        max_usuarios: planForm.value.max_usuarios,
      },
    })
    showPlan.value = false
    planForm.value = { nombre: '', precio: 0, periodicidad: 'mensual', max_comprobantes: 0, max_empresas: 0, max_usuarios: 0 }
    await loadAll()
    notify({ type: 'positive', message: 'Plan creado' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    savingPlan.value = false
  }
}

async function doDeletePlan(id: string) {
  try {
    await deletePlan(id)
    await loadAll()
    notify({ type: 'positive', message: 'Plan eliminado' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  }
}

async function doCreateSub() {
  if (!subForm.value.companyId || !subForm.value.planId) {
    notify({ type: 'warning', message: 'Elige empresa y plan' })
    return
  }
  savingSub.value = true
  try {
    await createSubscription({ companyId: subForm.value.companyId, planId: subForm.value.planId, periodoFin: subForm.value.periodoFin || null })
    showSub.value = false
    subForm.value = { companyId: null, planId: null, periodoFin: '' }
    await loadAll()
    notify({ type: 'positive', message: 'Suscripción creada' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    savingSub.value = false
  }
}

async function doSetEstado(id: string, estado: string) {
  try {
    await setSubscriptionEstado(id, estado)
    await loadAll()
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  }
}

async function doSaveBranding() {
  if (!reseller.value) return
  savingBrand.value = true
  try {
    await updateBranding(reseller.value.id, branding.value)
    notify({ type: 'positive', message: 'Marca guardada' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    savingBrand.value = false
  }
}

onMounted(loadAll)
</script>
