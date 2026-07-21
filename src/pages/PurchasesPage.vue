<template>
  <q-page class="q-pa-md">
    <!-- ==================== COMPRAS ==================== -->
    <div class="row items-center q-mb-md">
      <div class="text-h5">Compras</div>
      <q-space />
      <q-btn color="primary" icon="add" label="Nueva compra" @click="openNewPurchase" />
    </div>

    <q-table
      :rows="purchaseRows"
      :columns="purchaseColumns"
      row-key="id"
      :loading="loadingPurchases"
      flat
      bordered
    />

    <!-- ==================== GASTOS ==================== -->
    <div class="row items-center q-mb-md q-mt-xl">
      <div class="text-h5">Gastos</div>
      <q-space />
      <q-btn color="primary" icon="add" label="Nuevo gasto" @click="openNewExpense" />
    </div>

    <q-table
      :rows="expenseRows"
      :columns="expenseColumns"
      row-key="id"
      :loading="loadingExpenses"
      flat
      bordered
    />

    <!-- ==================== DIÁLOGO COMPRA ==================== -->
    <q-dialog v-model="showPurchase">
      <q-card style="min-width: 480px">
        <q-card-section class="text-h6">Nueva compra</q-card-section>
        <q-card-section class="q-gutter-sm">
          <q-select
            v-model="purchaseForm.supplier_id"
            outlined
            :options="supplierOptions"
            emit-value
            map-options
            label="Proveedor"
            :rules="supplierRules"
          />
          <q-select
            v-model="purchaseForm.tipo_doc"
            outlined
            :options="docOptions"
            emit-value
            map-options
            label="Tipo de documento"
            :rules="tipoDocRules"
          />
          <q-input
            v-model="purchaseForm.serie_numero"
            outlined
            label="Serie - Número"
            :rules="serieRules"
          />
          <q-input
            v-model="purchaseForm.fecha"
            outlined
            type="date"
            label="Fecha"
            stack-label
            :rules="fechaRules"
          />

          <div class="text-subtitle2 q-mt-md">Ítems</div>
          <div
            v-for="(item, i) in purchaseForm.items"
            :key="i"
            class="row q-col-gutter-sm items-center"
          >
            <div class="col">
              <q-input
                v-model="item.descripcion"
                outlined
                dense
                label="Descripción"
                :rules="nameRules"
                lazy-rules
                hide-bottom-space
              />
            </div>
            <div class="col-3">
              <q-input
                v-model.number="item.cantidad"
                outlined
                dense
                type="number"
                label="Cant."
                :rules="qtyRules"
                lazy-rules
                hide-bottom-space
              />
            </div>
            <div class="col-3">
              <q-input
                v-model.number="item.costo"
                outlined
                dense
                type="number"
                label="Costo"
                :rules="costoRules"
                lazy-rules
                hide-bottom-space
              />
            </div>
            <div class="col-auto">
              <q-btn
                flat
                round
                dense
                icon="delete"
                :disable="purchaseForm.items.length === 1"
                @click="removeItem(i)"
              />
            </div>
          </div>
          <q-btn flat dense icon="add" label="Agregar ítem" @click="addItem" />

          <div class="row justify-end q-mt-md text-subtitle1">
            Total: S/ {{ purchaseTotal.toFixed(2) }}
          </div>
        </q-card-section>
        <q-card-actions align="right">
          <q-btn v-close-popup flat label="Cancelar" />
          <q-btn color="primary" label="Guardar" :loading="savingPurchase" @click="savePurchase" />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <!-- ==================== DIÁLOGO GASTO ==================== -->
    <q-dialog v-model="showExpense">
      <q-card style="min-width: 340px">
        <q-card-section class="text-h6">Nuevo gasto</q-card-section>
        <q-card-section class="q-gutter-sm">
          <q-input
            v-model="expenseForm.concepto"
            outlined
            label="Concepto"
            autofocus
            :rules="nameRules"
          />
          <q-input
            v-model.number="expenseForm.monto"
            outlined
            type="number"
            label="Monto"
            :rules="montoRules"
          />
          <q-input
            v-model="expenseForm.fecha"
            outlined
            type="date"
            label="Fecha"
            stack-label
            :rules="fechaRules"
          />
        </q-card-section>
        <q-card-actions align="right">
          <q-btn v-close-popup flat label="Cancelar" />
          <q-btn color="primary" label="Guardar" :loading="savingExpense" @click="saveExpense" />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { type QTableColumn } from 'quasar'
import { notify } from '@/lib/toast'
import { useCompanyStore } from '@/stores/company'
import {
  listSuppliers,
  listPurchases,
  createPurchase,
  listExpenses,
  createExpense,
  type Supplier,
  type Purchase,
  type Expense,
} from '@/modules/purchases/purchases.api'
import {
  validate,
  required,
  requiredNum,
  positive,
  maxLen,
  nameRules,
  qtyRules,
  montoRules,
  type Rule,
} from '@/lib/validation'

const company = useCompanyStore()

// ---------- Reglas de validación ----------
const supplierRules: Rule[] = [required('Selecciona un proveedor')]
const tipoDocRules: Rule[] = [required('Selecciona el tipo de documento')]
const serieRules: Rule[] = [required('Ingresa serie y número'), maxLen(30)]
const fechaRules: Rule[] = [required('Selecciona la fecha')]
const costoRules: Rule[] = [requiredNum(), positive('El costo debe ser mayor que 0')]

function today(): string {
  return new Date().toISOString().slice(0, 10)
}

// ---------- Estado compartido ----------
const suppliers = ref<Supplier[]>([])
const supplierOptions = computed(() =>
  suppliers.value.map((s) => ({ label: s.razon_social, value: s.id })),
)
const supplierName = (id: string | null) =>
  suppliers.value.find((s) => s.id === id)?.razon_social ?? '—'

const docOptions = [
  { label: 'Factura', value: '01' },
  { label: 'Boleta', value: '03' },
  { label: 'Recibo por honorarios', value: '02' },
  { label: 'Otro', value: '00' },
]

// ---------- Compras ----------
const purchaseRows = ref<Purchase[]>([])
const loadingPurchases = ref(false)
const showPurchase = ref(false)
const savingPurchase = ref(false)

interface PurchaseItemForm {
  descripcion: string
  cantidad: number
  costo: number
}

const purchaseForm = ref<{
  supplier_id: string | null
  tipo_doc: string
  serie_numero: string
  fecha: string
  items: PurchaseItemForm[]
}>({
  supplier_id: null,
  tipo_doc: '01',
  serie_numero: '',
  fecha: today(),
  items: [{ descripcion: '', cantidad: 1, costo: 0 }],
})

const purchaseTotal = computed(() =>
  purchaseForm.value.items.reduce(
    (acc, it) => acc + (Number(it.cantidad) || 0) * (Number(it.costo) || 0),
    0,
  ),
)

const purchaseColumns: QTableColumn<Purchase>[] = [
  { name: 'fecha', label: 'Fecha', field: 'fecha', align: 'left', sortable: true },
  {
    name: 'supplier',
    label: 'Proveedor',
    field: (r) => supplierName(r.supplier_id),
    align: 'left',
  },
  { name: 'serie_numero', label: 'Documento', field: 'serie_numero', align: 'left' },
  {
    name: 'total',
    label: 'Total',
    field: 'total',
    align: 'right',
    format: (v) => `S/ ${Number(v).toFixed(2)}`,
  },
]

function addItem() {
  purchaseForm.value.items.push({ descripcion: '', cantidad: 1, costo: 0 })
}

function removeItem(i: number) {
  purchaseForm.value.items.splice(i, 1)
}

function openNewPurchase() {
  purchaseForm.value = {
    supplier_id: null,
    tipo_doc: '01',
    serie_numero: '',
    fecha: today(),
    items: [{ descripcion: '', cantidad: 1, costo: 0 }],
  }
  showPurchase.value = true
}

async function loadPurchases() {
  if (!company.current) return
  loadingPurchases.value = true
  try {
    purchaseRows.value = await listPurchases(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loadingPurchases.value = false
  }
}

async function savePurchase() {
  if (!company.current) return
  const fields: Array<[unknown, Rule[]]> = [
    [purchaseForm.value.supplier_id, supplierRules],
    [purchaseForm.value.tipo_doc, tipoDocRules],
    [purchaseForm.value.serie_numero, serieRules],
    [purchaseForm.value.fecha, fechaRules],
  ]
  for (const it of purchaseForm.value.items) {
    fields.push([it.descripcion, nameRules], [it.cantidad, qtyRules], [it.costo, costoRules])
  }
  const err = validate(fields)
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  savingPurchase.value = true
  try {
    await createPurchase(company.current.id, {
      supplier_id: purchaseForm.value.supplier_id,
      tipo_doc: purchaseForm.value.tipo_doc,
      serie_numero: purchaseForm.value.serie_numero,
      fecha: purchaseForm.value.fecha,
      items: purchaseForm.value.items,
    })
    showPurchase.value = false
    await loadPurchases()
    notify({ type: 'positive', message: 'Compra registrada' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    savingPurchase.value = false
  }
}

// ---------- Gastos ----------
const expenseRows = ref<Expense[]>([])
const loadingExpenses = ref(false)
const showExpense = ref(false)
const savingExpense = ref(false)
const expenseForm = ref({ concepto: '', monto: 0, fecha: today() })

const expenseColumns: QTableColumn<Expense>[] = [
  { name: 'fecha', label: 'Fecha', field: 'fecha', align: 'left', sortable: true },
  { name: 'concepto', label: 'Concepto', field: 'concepto', align: 'left' },
  {
    name: 'monto',
    label: 'Monto',
    field: 'monto',
    align: 'right',
    format: (v) => `S/ ${Number(v).toFixed(2)}`,
  },
]

function openNewExpense() {
  expenseForm.value = { concepto: '', monto: 0, fecha: today() }
  showExpense.value = true
}

async function loadExpenses() {
  if (!company.current) return
  loadingExpenses.value = true
  try {
    expenseRows.value = await listExpenses(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loadingExpenses.value = false
  }
}

async function saveExpense() {
  if (!company.current) return
  const err = validate([
    [expenseForm.value.concepto, nameRules],
    [expenseForm.value.monto, montoRules],
    [expenseForm.value.fecha, fechaRules],
  ])
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  savingExpense.value = true
  try {
    await createExpense(company.current.id, expenseForm.value)
    showExpense.value = false
    await loadExpenses()
    notify({ type: 'positive', message: 'Gasto registrado' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    savingExpense.value = false
  }
}

// ---------- Init ----------
async function loadSuppliers() {
  if (!company.current) return
  try {
    suppliers.value = await listSuppliers(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  }
}

onMounted(async () => {
  await Promise.all([loadSuppliers(), loadPurchases(), loadExpenses()])
})
</script>
