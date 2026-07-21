<template>
  <q-page class="q-pa-md">
    <div class="row items-center q-mb-md">
      <div class="text-h5">Caja</div>
      <q-space />
      <q-btn
        v-if="active"
        color="negative"
        icon="lock"
        label="Cerrar caja"
        @click="openClose"
      />
    </div>

    <!-- Sin caja abierta -->
    <q-card v-if="!active && !loading" style="max-width: 420px">
      <q-card-section class="text-h6">Abrir caja</q-card-section>
      <q-card-section>
        <q-input
          v-model.number="montoInicial"
          type="number"
          outlined
          label="Monto inicial (S/)"
          :rules="montoRules"
          autofocus
        />
      </q-card-section>
      <q-card-actions align="right">
        <q-btn
          color="primary"
          icon="point_of_sale"
          label="Abrir caja"
          :loading="opening"
          @click="abrir"
        />
      </q-card-actions>
    </q-card>

    <!-- Caja abierta -->
    <template v-if="active">
      <div class="row q-col-gutter-md q-mb-md">
        <div class="col-12 col-sm-3">
          <q-card>
            <q-card-section>
              <div class="text-caption">Monto inicial</div>
              <div class="text-h6">S/ {{ toMoney(active.monto_inicial) }}</div>
            </q-card-section>
          </q-card>
        </div>
        <div class="col-12 col-sm-3">
          <q-card>
            <q-card-section>
              <div class="text-caption">Ingresos</div>
              <div class="text-h6 text-positive">S/ {{ toMoney(ingresos) }}</div>
            </q-card-section>
          </q-card>
        </div>
        <div class="col-12 col-sm-3">
          <q-card>
            <q-card-section>
              <div class="text-caption">Retiros</div>
              <div class="text-h6 text-negative">S/ {{ toMoney(retiros) }}</div>
            </q-card-section>
          </q-card>
        </div>
        <div class="col-12 col-sm-3">
          <q-card>
            <q-card-section>
              <div class="text-caption">Saldo esperado</div>
              <div class="text-h6">S/ {{ toMoney(esperado) }}</div>
            </q-card-section>
          </q-card>
        </div>
      </div>

      <div class="row items-center q-mb-sm">
        <div class="text-subtitle1">Movimientos</div>
        <q-space />
        <q-btn color="positive" icon="add" label="Ingreso" @click="openMovement('ingreso')" />
        <q-btn
          color="warning"
          icon="remove"
          label="Retiro"
          class="q-ml-sm"
          @click="openMovement('retiro')"
        />
      </div>

      <q-table
        :rows="movements"
        :columns="movColumns"
        row-key="id"
        :loading="loading"
        flat
        bordered
      >
        <template #body-cell-tipo="props">
          <q-td :props="props">
            <q-badge :color="props.value === 'ingreso' ? 'positive' : 'warning'" :label="props.value" />
          </q-td>
        </template>
      </q-table>
    </template>

    <!-- Historial de sesiones -->
    <div class="text-subtitle1 q-mt-lg q-mb-sm">Historial de sesiones</div>
    <q-table
      :rows="sessions"
      :columns="sessionColumns"
      row-key="id"
      :loading="loading"
      flat
      bordered
    >
      <template #body-cell-estado="props">
        <q-td :props="props">
          <q-badge :color="props.value === 'abierta' ? 'positive' : 'grey'" :label="props.value" />
        </q-td>
      </template>
    </q-table>

    <!-- Diálogo movimiento -->
    <q-dialog v-model="showMovement">
      <q-card style="min-width: 340px">
        <q-card-section class="text-h6">
          {{ movForm.tipo === 'ingreso' ? 'Registrar ingreso' : 'Registrar retiro' }}
        </q-card-section>
        <q-card-section class="q-gutter-sm">
          <q-input
            v-model.number="movForm.monto"
            type="number"
            outlined
            label="Monto (S/)"
            :rules="montoRules"
            autofocus
          />
          <q-input v-model="movForm.motivo" outlined label="Motivo" :rules="[required('Indica el motivo')]" />
        </q-card-section>
        <q-card-actions align="right">
          <q-btn v-close-popup flat label="Cancelar" />
          <q-btn color="primary" label="Guardar" :loading="savingMov" @click="saveMovement" />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <!-- Diálogo cierre -->
    <q-dialog v-model="showClose">
      <q-card style="min-width: 360px">
        <q-card-section class="text-h6">Cerrar caja</q-card-section>
        <q-card-section class="q-gutter-sm">
          <div class="text-caption">Saldo esperado: S/ {{ toMoney(esperado) }}</div>
          <q-input
            v-model.number="montoFinal"
            type="number"
            outlined
            label="Monto final real (S/)"
            :rules="montoCeroRules"
            autofocus
          />
          <q-banner class="q-mt-sm text-white" :class="diffClass">
            Diferencia: S/ {{ toMoney(diferenciaPreview) }}
          </q-banner>
        </q-card-section>
        <q-card-actions align="right">
          <q-btn v-close-popup flat label="Cancelar" />
          <q-btn color="negative" label="Cerrar caja" :loading="closing" @click="cerrar" />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { type QTableColumn } from 'quasar'
import { useCompanyStore } from '@/stores/company'
import {
  openSession,
  getOpenSession,
  closeSession,
  listMovements,
  addMovement,
  listSessions,
  type CashMovement,
  type CashSession,
  type MovementTipo,
} from '@/modules/cash/cash.api'
import { validate, required, montoRules, montoCeroRules } from '@/lib/validation'
import { notify } from '@/lib/toast'

const company = useCompanyStore()

const loading = ref(false)
const opening = ref(false)
const closing = ref(false)
const savingMov = ref(false)

const active = ref<CashSession | null>(null)
const movements = ref<CashMovement[]>([])
const sessions = ref<CashSession[]>([])

const montoInicial = ref(0)
const montoFinal = ref(0)

const showMovement = ref(false)
const showClose = ref(false)
const movForm = ref<{ tipo: MovementTipo; monto: number; motivo: string }>({
  tipo: 'ingreso',
  monto: 0,
  motivo: '',
})

const ingresos = computed(() =>
  movements.value.filter((m) => m.tipo === 'ingreso').reduce((acc, m) => acc + Number(m.monto), 0),
)
const retiros = computed(() =>
  movements.value.filter((m) => m.tipo === 'retiro').reduce((acc, m) => acc + Number(m.monto), 0),
)
const esperado = computed(() =>
  active.value ? Number(active.value.monto_inicial) + ingresos.value - retiros.value : 0,
)
const diferenciaPreview = computed(() => montoFinal.value - esperado.value)
const diffClass = computed(() => {
  if (diferenciaPreview.value < 0) return 'bg-negative'
  if (diferenciaPreview.value > 0) return 'bg-warning'
  return 'bg-positive'
})

function toMoney(v: number | string | null): string {
  return Number(v ?? 0).toFixed(2)
}

const movColumns: QTableColumn<CashMovement>[] = [
  { name: 'tipo', label: 'Tipo', field: 'tipo', align: 'left' },
  {
    name: 'monto',
    label: 'Monto',
    field: 'monto',
    align: 'right',
    format: (v) => `S/ ${toMoney(v as number)}`,
  },
  { name: 'motivo', label: 'Motivo', field: 'motivo', align: 'left', format: (v) => (v as string | null) ?? '—' },
  {
    name: 'fecha',
    label: 'Fecha',
    field: 'created_at',
    align: 'left',
    format: (v) => new Date(v as string).toLocaleString('es-PE'),
  },
]

const sessionColumns: QTableColumn<CashSession>[] = [
  {
    name: 'apertura',
    label: 'Apertura',
    field: 'abierto_en',
    align: 'left',
    format: (v) => new Date(v as string).toLocaleString('es-PE'),
  },
  {
    name: 'inicial',
    label: 'Inicial',
    field: 'monto_inicial',
    align: 'right',
    format: (v) => `S/ ${toMoney(v as number)}`,
  },
  {
    name: 'final',
    label: 'Final',
    field: 'monto_final',
    align: 'right',
    format: (v) => (v === null ? '—' : `S/ ${toMoney(v as number)}`),
  },
  {
    name: 'diferencia',
    label: 'Diferencia',
    field: 'diferencia',
    align: 'right',
    format: (v) => (v === null ? '—' : `S/ ${toMoney(v as number)}`),
  },
  { name: 'estado', label: 'Estado', field: 'estado', align: 'left' },
  {
    name: 'cierre',
    label: 'Cierre',
    field: 'cerrado_en',
    align: 'left',
    format: (v) => (v ? new Date(v as string).toLocaleString('es-PE') : '—'),
  },
]

async function load() {
  if (!company.current) return
  loading.value = true
  try {
    const companyId = company.current.id
    active.value = await getOpenSession(companyId)
    sessions.value = await listSessions(companyId)
    movements.value = active.value ? await listMovements(active.value.id) : []
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
}

async function abrir() {
  if (!company.current) return
  const err = validate([[montoInicial.value, montoRules]])
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  opening.value = true
  try {
    await openSession(company.current.id, montoInicial.value)
    montoInicial.value = 0
    await load()
    notify({ type: 'positive', message: 'Caja abierta' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    opening.value = false
  }
}

function openMovement(tipo: MovementTipo) {
  movForm.value = { tipo, monto: 0, motivo: '' }
  showMovement.value = true
}

async function saveMovement() {
  if (!active.value) return
  const err = validate([
    [movForm.value.monto, montoRules],
    [movForm.value.motivo, [required('Indica el motivo')]],
  ])
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  savingMov.value = true
  try {
    await addMovement(active.value.id, {
      tipo: movForm.value.tipo,
      monto: movForm.value.monto,
      motivo: movForm.value.motivo,
    })
    showMovement.value = false
    await load()
    notify({ type: 'positive', message: 'Movimiento registrado' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    savingMov.value = false
  }
}

function openClose() {
  montoFinal.value = esperado.value
  showClose.value = true
}

async function cerrar() {
  if (!active.value) return
  const err = validate([[montoFinal.value, montoCeroRules]])
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  closing.value = true
  try {
    const closed = await closeSession(active.value.id, montoFinal.value)
    showClose.value = false
    await load()
    notify({
      type: closed.diferencia === 0 ? 'positive' : 'warning',
      message: `Caja cerrada · Diferencia S/ ${toMoney(closed.diferencia)}`,
    })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    closing.value = false
  }
}

onMounted(load)
</script>
