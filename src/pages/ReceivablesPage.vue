<template>
  <q-page class="q-pa-md">
    <div class="row items-center q-mb-md">
      <div class="text-h5">Cuentas por cobrar</div>
      <q-space />
      <q-chip color="orange-8" text-color="white" icon="payments" :label="`Saldo total: S/ ${totalSaldo.toFixed(2)}`" />
    </div>

    <q-table :rows="rows" :columns="cols" row-key="id" :loading="loading" flat bordered>
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
        <q-td :props="props" class="text-right">
          <q-btn color="primary" dense size="sm" label="Registrar abono" @click="openAbono(props.row)" />
        </q-td>
      </template>
      <template #no-data>
        <div class="full-width text-center q-pa-lg text-grey-6">Sin cuentas por cobrar pendientes 🎉</div>
      </template>
    </q-table>

    <q-dialog v-model="showAbono">
      <q-card style="min-width: 340px">
        <q-card-section class="text-h6">Abono a {{ current?.numero }}</q-card-section>
        <q-card-section class="q-gutter-sm">
          <div class="text-body2 text-grey-7">Saldo actual: <b>S/ {{ current?.saldo.toFixed(2) }}</b></div>
          <q-input v-model.number="abonoForm.monto" outlined dense type="number" label="Monto" autofocus />
          <q-select
            v-model="abonoForm.medio"
            outlined
            dense
            :options="['efectivo', 'yape', 'plin', 'tarjeta', 'transferencia']"
            label="Medio"
          />
          <q-input v-model="abonoForm.referencia" outlined dense label="Referencia (opcional)" />
        </q-card-section>
        <q-card-actions align="right">
          <q-btn v-close-popup flat label="Cancelar" />
          <q-btn color="primary" label="Registrar" :loading="saving" @click="doAbono" />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import type { QTableColumn } from 'quasar'
import { useCompanyStore } from '@/stores/company'
import { notify } from '@/lib/toast'
import { listReceivables, registrarAbono, type Receivable } from '@/modules/receivables/receivables.api'

const company = useCompanyStore()
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

async function load() {
  if (!company.current) return
  loading.value = true
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
  saving.value = true
  try {
    await registrarAbono({
      companyId: company.current.id,
      documentId: current.value.id,
      monto: abonoForm.value.monto,
      medio: abonoForm.value.medio,
      referencia: abonoForm.value.referencia || undefined,
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
