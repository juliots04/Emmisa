<template>
  <q-page class="q-pa-md">
    <KModuleHeader
      title="Cuentas por cobrar"
      subtitle="Comprobantes emitidos a crédito con saldo pendiente de cobro"
      :refresh-fn="load"
      show-export
      @export="onExport"
    >
      <template #actions>
        <q-chip
          color="orange-8"
          text-color="white"
          icon="payments"
          :label="`Saldo total: S/ ${totalSaldo.toFixed(2)}`"
        />
      </template>
    </KModuleHeader>

    <q-table
      :rows="rows"
      :columns="cols"
      row-key="id"
      :loading="loading"
      flat
      bordered
    >
      <template #body-cell-estado_pago="props">
        <q-td :props="props">
          <q-chip
            :color="props.row.estado_pago === 'parcial' ? 'amber-7' : 'red-6'"
            text-color="white"
            dense
            :label="props.row.estado_pago"
          />
        </q-td>
      </template>
      <template #body-cell-acciones="props">
        <q-td
          :props="props"
          class="text-right"
        >
          <q-btn
            color="primary"
            dense
            size="sm"
            label="Registrar abono"
            @click="openAbono(props.row)"
          />
        </q-td>
      </template>
      <template #no-data>
        <div class="full-width text-center q-pa-lg text-grey-6">
          Sin cuentas por cobrar pendientes 🎉
        </div>
      </template>
      <template #loading>
        <KTableSkeleton />
      </template>
    </q-table>

    <q-dialog v-model="showAbono">
      <q-card class="k-dialog-sm">
        <q-card-section class="k-modal-head">
          <div class="text-h6">
            Abono a {{ current?.numero }}
          </div>
          <q-space />
          <q-btn
            v-close-popup
            flat
            dense
            round
            icon="close"
            aria-label="Cerrar"
          />
        </q-card-section>
        <q-card-section class="q-gutter-sm">
          <div class="text-body2 text-grey-7">
            Saldo actual: <b>S/ {{ Number(current?.saldo ?? 0).toFixed(2) }}</b>
          </div>
          <q-input
            v-model.number="abonoForm.monto"
            outlined
            dense
            type="number"
            label="Monto"
            autofocus
          />
          <q-select
            v-model="abonoForm.medio"
            outlined
            dense
            :options="['efectivo', 'yape', 'plin', 'tarjeta', 'transferencia']"
            label="Medio"
          />
          <q-input
            v-model="abonoForm.referencia"
            outlined
            dense
            label="Referencia (opcional)"
          />
        </q-card-section>
        <q-card-actions align="right">
          <q-btn
            v-close-popup
            flat
            label="Cancelar"
          />
          <q-btn
            color="primary"
            label="Registrar"
            :loading="saving"
            @click="doAbono"
          />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import type { QTableColumn } from 'quasar'
import KTableSkeleton from '@/components/KTableSkeleton.vue'
import KModuleHeader from '@/components/KModuleHeader.vue'
import { exportTableXls } from '@/lib/exportTable'
import { useCompanyStore } from '@/stores/company'
import { useRealtime } from '@/lib/realtime'
import { notify } from '@/lib/toast'
import { listReceivables, registrarAbono, type Receivable } from '@/modules/receivables/receivables.api'
import { getOpenSession } from '@/modules/cash/cash.api'

const company = useCompanyStore()
// Realtime: al emitir a crédito o registrar un abono, refresca las cuentas por cobrar.
useRealtime('documents', () => company.current?.id, () => { void load() })
const rows = ref<Receivable[]>([])
const loading = ref(false)
const showAbono = ref(false)
const saving = ref(false)
const current = ref<Receivable | null>(null)
const abonoForm = ref<{ monto: number; medio: string; referencia: string }>({ monto: 0, medio: 'efectivo', referencia: '' })

const totalSaldo = computed(() => rows.value.reduce((a, r) => a + Number(r.saldo), 0))

const cols: QTableColumn<Receivable>[] = [
  { name: 'numero', label: 'Comprobante', field: 'numero', align: 'left', sortable: true },
  { name: 'cliente', label: 'Cliente', field: (r) => r.cliente ?? '—', align: 'left' },
  { name: 'total', label: 'Total', field: (r) => `S/ ${Number(r.total).toFixed(2)}`, align: 'right' },
  { name: 'saldo', label: 'Saldo', field: (r) => `S/ ${Number(r.saldo).toFixed(2)}`, align: 'right' },
  { name: 'vencimiento', label: 'Vence', field: (r) => r.vencimiento ?? '—', align: 'left' },
  { name: 'estado_pago', label: 'Estado', field: 'estado_pago', align: 'center' },
  { name: 'acciones', label: '', field: 'id', align: 'right' },
]

function onExport() {
  exportTableXls('cuentas-por-cobrar', cols, rows.value)
}

async function load() {
  if (!company.current) return
  loading.value = !rows.value.length
  try {
    rows.value = await listReceivables(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
}

function openAbono(r: Receivable) {
  current.value = r
  abonoForm.value = { monto: Number(r.saldo), medio: 'efectivo', referencia: '' }
  showAbono.value = true
}

async function doAbono() {
  if (!company.current || !current.value) return
  if (!abonoForm.value.monto || abonoForm.value.monto <= 0) {
    notify({ type: 'warning', message: 'Ingresa un monto válido' })
    return
  }
  // No permitir sobrepago: el abono no puede exceder el saldo pendiente.
  const saldo = Number(current.value.saldo)
  if (Math.round(abonoForm.value.monto * 100) > Math.round(saldo * 100)) {
    notify({ type: 'warning', message: `El abono no puede exceder el saldo (S/ ${saldo.toFixed(2)}).` })
    return
  }
  saving.value = true
  try {
    // Cobro en efectivo → debe entrar a la sesión de caja abierta (si hay), para que el arqueo cuadre.
    let cashSessionId: string | null = null
    if (abonoForm.value.medio === 'efectivo') {
      const sess = await getOpenSession(company.current.id)
      cashSessionId = sess?.id ?? null
    }
    await registrarAbono({
      companyId: company.current.id,
      documentId: current.value.id,
      monto: abonoForm.value.monto,
      medio: abonoForm.value.medio,
      referencia: abonoForm.value.referencia || undefined,
      cashSessionId,
    })
    showAbono.value = false
    await load()
    notify({ type: 'positive', message: 'Abono registrado' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    saving.value = false
  }
}

onMounted(load)
</script>
