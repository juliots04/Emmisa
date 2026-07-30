<template>
  <q-page class="q-pa-md">
    <div class="row items-center q-mb-md q-gutter-x-sm">
      <div class="text-h5">
        SIRE
      </div>
      <q-badge
        color="primary"
        outline
        label="Registros electrónicos SUNAT"
      />
    </div>

    <!-- Aviso: cada empresa usa SUS credenciales -->
    <q-banner
      class="k-banner--info q-mb-md"
      rounded
    >
      <template #avatar>
        <q-icon name="info" />
      </template>
      SIRE es el registro mensual de <b>ventas (RVIE)</b> y <b>compras (RCE)</b> ante SUNAT.
      Cada empresa conecta con <b>sus propias credenciales de API SUNAT</b> (gratis, se generan en SUNAT →
      Empresas → Credenciales de API SUNAT).
    </q-banner>

    <!-- ============ Configuración de credenciales ============ -->
    <q-card class="q-mb-md">
      <q-card-section>
        <div class="row items-center q-mb-sm">
          <div class="text-subtitle1">
            Credenciales de API SUNAT
          </div>
          <q-space />
          <q-chip
            v-if="estado.configurado"
            color="positive"
            text-color="white"
            icon="check_circle"
            :label="`Configurado (${estado.usuario ?? 'usuario SOL'})`"
          />
          <q-chip
            v-else
            color="grey-6"
            text-color="white"
            icon="warning"
            label="Sin configurar"
          />
        </div>

        <div class="row q-col-gutter-md">
          <q-input
            v-model="cred.clientId"
            class="col-12 col-md-6"
            outlined
            dense
            label="client_id"
            placeholder="9cae24a9-10d7-48b0-..."
          />
          <q-input
            v-model="cred.clientSecret"
            class="col-12 col-md-6"
            outlined
            dense
            type="password"
            label="client_secret"
          />
          <q-input
            v-model="cred.solUsuario"
            class="col-12 col-md-6"
            outlined
            dense
            label="Usuario SOL (secundario)"
          />
          <q-input
            v-model="cred.solClave"
            class="col-12 col-md-6"
            outlined
            dense
            type="password"
            label="Clave SOL"
          />
        </div>

        <div class="row q-gutter-sm q-mt-md">
          <q-btn
            color="primary"
            unelevated
            no-caps
            icon="save"
            label="Guardar credenciales"
            :loading="saving"
            @click="guardar"
          />
          <q-btn
            outline
            no-caps
            icon="wifi_tethering"
            label="Probar conexión"
            :loading="testing"
            :disable="!estado.configurado"
            @click="probar"
          />
        </div>
      </q-card-section>
    </q-card>

    <!-- ============ Descargar propuesta ============ -->
    <q-card class="q-mb-md">
      <q-card-section>
        <div class="text-subtitle1 q-mb-sm">
          Propuesta de SUNAT
        </div>
        <div class="text-caption text-muted q-mb-md">
          SUNAT arma un borrador de tu registro. Descárgalo, revísalo y luego acéptalo.
          (Por ahora: solo lectura del borrador — la aceptación se habilita tras validar.)
        </div>
        <div class="row q-col-gutter-md items-end">
          <div class="col-12 col-sm-4">
            <q-select
              v-model="tipo"
              outlined
              dense
              emit-value
              map-options
              :options="tipoOptions"
              label="Registro"
            />
          </div>
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
              unelevated
              no-caps
              icon="cloud_download"
              label="Descargar propuesta"
              :loading="descargando"
              :disable="!estado.configurado"
              @click="descargar"
            />
          </div>
          <div class="col-auto">
            <q-btn
              color="positive"
              outline
              no-caps
              icon="task_alt"
              label="Aceptar propuesta"
              :loading="aceptando"
              :disable="!estado.configurado"
              @click="aceptar"
            >
              <q-tooltip>Registra la propuesta como tu registro definitivo del periodo</q-tooltip>
            </q-btn>
          </div>
        </div>
      </q-card-section>
    </q-card>

    <!-- ============ Historial ============ -->
    <div class="text-subtitle1 q-mb-sm">
      Historial
    </div>
    <q-table
      :rows="procesos"
      :columns="columns"
      row-key="id"
      :loading="loading"
      flat
      bordered
    >
      <template #body-cell-tipo="props">
        <q-td :props="props">
          <q-badge
            :color="props.value === 'RCE' ? 'deep-orange' : 'primary'"
            :label="props.value === 'RCE' ? 'Compras' : 'Ventas'"
          />
        </q-td>
      </template>
      <template #body-cell-estado="props">
        <q-td :props="props">
          <q-badge
            :color="props.value === 'terminado' ? 'positive' : props.value === 'error' ? 'negative' : 'orange'"
            :label="props.value"
          />
          <q-btn
            v-if="props.row.num_ticket && props.value !== 'terminado'"
            flat
            dense
            round
            size="sm"
            icon="refresh"
            @click="consultar(props.row)"
          >
            <q-tooltip>Consultar estado</q-tooltip>
          </q-btn>
        </q-td>
      </template>
    </q-table>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { type QTableColumn } from 'quasar'
import { useCompanyStore } from '@/stores/company'
import { notify } from '@/lib/toast'
import {
  tieneSire,
  guardarCredencialesSire,
  sireTest,
  sireDescargarPropuesta,
  sireAceptarPropuesta,
  sireConsultarTicket,
  listSireProcesos,
  type SireEstado,
  type SireProceso,
} from '@/modules/sire/sire.api'

const company = useCompanyStore()

const estado = ref<SireEstado>({ configurado: false, usuario: null })
const cred = reactive({ clientId: '', clientSecret: '', solUsuario: '', solClave: '' })
const saving = ref(false)
const testing = ref(false)
const descargando = ref(false)
const aceptando = ref(false)
const loading = ref(false)
const procesos = ref<SireProceso[]>([])

const tipo = ref<'RVIE' | 'RCE'>('RVIE')
const tipoOptions = [
  { label: 'Ventas (RVIE)', value: 'RVIE' },
  { label: 'Compras (RCE)', value: 'RCE' },
]

const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']
const periodOptions = computed(() => {
  const opts: { label: string; value: string }[] = []
  const d = new Date()
  let y = d.getFullYear()
  let m = d.getMonth()
  for (let i = 0; i < 12; i++) {
    opts.push({ label: `${MESES[m]} ${y}`, value: `${y}${String(m + 1).padStart(2, '0')}` })
    m--
    if (m < 0) {
      m = 11
      y--
    }
  }
  return opts
})
const periodo = ref(periodOptions.value[0].value)

const columns: QTableColumn<SireProceso>[] = [
  { name: 'tipo', label: 'Registro', field: 'tipo', align: 'left' },
  { name: 'periodo', label: 'Periodo', field: 'periodo', align: 'left' },
  { name: 'ticket', label: 'Ticket', field: 'num_ticket', align: 'left' },
  { name: 'estado', label: 'Estado', field: 'estado', align: 'left' },
  {
    name: 'fecha',
    label: 'Fecha',
    field: 'created_at',
    align: 'left',
    format: (v) => new Date(v as string).toLocaleString('es-PE'),
  },
]

async function cargar() {
  if (!company.current) return
  loading.value = true
  try {
    const [e, p] = await Promise.all([tieneSire(company.current.id), listSireProcesos(company.current.id)])
    estado.value = e
    procesos.value = p
    if (e.usuario) cred.solUsuario = e.usuario
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
}

async function guardar() {
  if (!company.current) return
  if (!cred.clientId || !cred.clientSecret || !cred.solUsuario || !cred.solClave) {
    notify({ type: 'warning', message: 'Completa las 4 credenciales' })
    return
  }
  saving.value = true
  try {
    await guardarCredencialesSire(company.current.id, cred)
    notify({ type: 'positive', message: 'Credenciales SIRE guardadas' })
    cred.clientSecret = ''
    cred.solClave = ''
    await cargar()
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    saving.value = false
  }
}

async function probar() {
  if (!company.current) return
  testing.value = true
  try {
    const r = await sireTest(company.current.id)
    notify({ type: 'positive', message: r.mensaje })
  } catch (e) {
    notify({ type: 'negative', message: `Conexión falló: ${(e as Error).message}` })
  } finally {
    testing.value = false
  }
}

async function descargar() {
  if (!company.current) return
  descargando.value = true
  try {
    const r = await sireDescargarPropuesta(company.current.id, tipo.value, periodo.value)
    notify({ type: 'positive', message: `Propuesta solicitada. Ticket: ${r.numTicket}` })
    await cargar()
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    descargando.value = false
  }
}

async function aceptar() {
  if (!company.current) return
  aceptando.value = true
  try {
    const r = await sireAceptarPropuesta(company.current.id, tipo.value, periodo.value)
    notify({ type: 'positive', message: `Propuesta aceptada. Ticket: ${r.numTicket}` })
    await cargar()
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    aceptando.value = false
  }
}

async function consultar(p: SireProceso) {
  if (!company.current || !p.num_ticket) return
  try {
    const r = await sireConsultarTicket(company.current.id, p.tipo, p.num_ticket, p.id)
    notify({ type: 'info', message: `Estado: ${r.estado}` })
    await cargar()
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  }
}

onMounted(cargar)
</script>
