<template>
  <q-page class="q-pa-md">
    <!-- ==================== COMPRAS ==================== -->
    <div class="row items-center q-mb-md">
      <div class="text-h5">
        Compras
      </div>
      <q-space />
      <q-btn
        color="primary"
        icon="add"
        label="Nueva compra"
        @click="openNewPurchase"
      />
    </div>

    <q-table
      :rows="purchaseRows"
      :columns="purchaseColumns"
      row-key="id"
      :loading="loadingPurchases"
      flat
      bordered
    >
      <template #loading>
        <KTableSkeleton />
      </template>
    </q-table>

    <!-- ==================== GASTOS ==================== -->
    <div class="row items-center q-mb-md q-mt-xl">
      <div class="text-h5">
        Gastos
      </div>
      <q-space />
      <q-btn
        color="primary"
        icon="add"
        label="Nuevo gasto"
        @click="openNewExpense"
      />
    </div>

    <q-table
      :rows="expenseRows"
      :columns="expenseColumns"
      row-key="id"
      :loading="loadingExpenses"
      flat
      bordered
    >
      <template #loading>
        <KTableSkeleton />
      </template>
    </q-table>

    <!-- ==================== DIÁLOGO COMPRA ==================== -->
    <q-dialog v-model="showPurchase">
      <q-card class="k-dialog-lg">
        <q-card-section class="k-modal-head">
          <div class="text-h6">
            Nueva compra
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

          <div class="row q-col-gutter-sm">
            <q-select
              v-model="purchaseForm.moneda"
              class="col"
              outlined
              dense
              emit-value
              map-options
              :options="monedaOptions"
              label="Moneda"
            />
            <q-input
              v-if="purchaseForm.moneda === 'USD'"
              v-model.number="purchaseForm.tipo_cambio"
              class="col"
              outlined
              dense
              type="number"
              step="0.001"
              label="Tipo de cambio"
            />
          </div>

          <div class="row q-col-gutter-sm">
            <q-select
              v-model="purchaseForm.condicion_pago"
              class="col"
              outlined
              dense
              emit-value
              map-options
              :options="condicionOptions"
              label="Condición de pago"
            />
            <q-input
              v-if="purchaseForm.condicion_pago === 'credito'"
              v-model="purchaseForm.fecha_vencimiento"
              class="col"
              outlined
              dense
              type="date"
              stack-label
              label="Vence"
            />
          </div>

          <q-toggle
            v-model="purchaseForm.afecta_inventario"
            label="Ingresar mercadería a inventario (actualiza stock y costo)"
          />
          <q-select
            v-if="purchaseForm.afecta_inventario"
            v-model="purchaseForm.warehouse_id"
            outlined
            dense
            clearable
            emit-value
            map-options
            :options="warehouseOptions"
            label="Almacén de destino (por defecto: principal)"
          />

          <div class="text-subtitle2 q-mt-md">
            Ítems
          </div>
          <div
            v-for="(item, i) in purchaseForm.items"
            :key="i"
            class="row q-col-gutter-sm items-center"
          >
            <div
              v-if="purchaseForm.afecta_inventario"
              class="col-12"
            >
              <q-select
                v-model="item.productId"
                outlined
                dense
                clearable
                emit-value
                map-options
                :options="productOptions"
                label="Producto (vincula al stock)"
                @update:model-value="(v: string | null) => onPickProduct(item, v)"
              />
            </div>
            <div class="col">
              <q-input
                v-model="item.descripcion"
                outlined
                dense
                label="Descripción"
                :rules="nameRules"
                lazy-rules="ondemand"
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
                lazy-rules="ondemand"
                hide-bottom-space
              />
            </div>
            <div class="col-3">
              <q-input
                v-model.number="item.costo"
                outlined
                dense
                type="number"
                label="Costo (incl. IGV)"
                :rules="costoRules"
                lazy-rules="ondemand"
                hide-bottom-space
              />
            </div>
            <div
              v-if="purchaseForm.tipo_doc === '01'"
              class="col-auto"
            >
              <q-toggle
                v-model="item.afecto"
                dense
                size="sm"
                label="IGV"
              >
                <q-tooltip>Desmarca si la línea es exonerada/inafecta (sin crédito fiscal)</q-tooltip>
              </q-toggle>
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

            <!-- Números de serie (solo productos serializados que ingresan a inventario) -->
            <div
              v-if="purchaseForm.afecta_inventario && itemManejaSeries(item)"
              class="col-12"
            >
              <q-input
                v-model="item.series"
                outlined
                dense
                type="textarea"
                autogrow
                label="Números de serie (uno por línea)"
                :hint="`${parseSeries(item.series).length} de ${Number(item.cantidad) || 0} · deben coincidir con la cantidad`"
              />
            </div>
          </div>
          <q-btn
            flat
            dense
            icon="add"
            label="Agregar ítem"
            @click="addItem"
          />

          <div class="row justify-end q-mt-md text-subtitle1">
            Total: S/ {{ purchaseTotal.toFixed(2) }}
          </div>
        </q-card-section>
        <q-card-actions align="right">
          <q-btn
            v-close-popup
            flat
            label="Cancelar"
          />
          <q-btn
            color="primary"
            label="Guardar"
            :loading="savingPurchase"
            @click="savePurchase"
          />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <!-- ==================== DIÁLOGO GASTO ==================== -->
    <q-dialog v-model="showExpense">
      <q-card class="k-dialog-sm">
        <q-card-section class="k-modal-head">
          <div class="text-h6">
            Nuevo gasto
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
          <q-btn
            v-close-popup
            flat
            label="Cancelar"
          />
          <q-btn
            color="primary"
            label="Guardar"
            :loading="savingExpense"
            @click="saveExpense"
          />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { type QTableColumn } from 'quasar'
import KTableSkeleton from '@/components/KTableSkeleton.vue'
import { notify } from '@/lib/toast'
import { useCompanyStore } from '@/stores/company'
import { useRealtime } from '@/lib/realtime'
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
import { listProducts } from '@/modules/products/products.api'
import { listWarehouses, type Warehouse } from '@/modules/inventory/inventory.api'
import type { Product } from '@/types'
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
// Realtime: refresca compras y gastos al registrarlos (incl. otras pestañas/usuarios).
useRealtime('purchases', () => company.current?.id, () => { void loadPurchases() })
useRealtime('expenses', () => company.current?.id, () => { void loadExpenses() })

// ---------- Reglas de validación ----------
const supplierRules: Rule[] = [required('Selecciona un proveedor')]
const tipoDocRules: Rule[] = [required('Selecciona el tipo de documento')]
const serieRules: Rule[] = [required('Ingresa serie y número'), maxLen(30)]
const fechaRules: Rule[] = [required('Selecciona la fecha')]
const costoRules: Rule[] = [requiredNum(), positive('El costo debe ser mayor que 0')]

function today(): string {
  // Fecha local (no UTC): de noche en Perú, toISOString ya está en el día siguiente.
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
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

const condicionOptions = [
  { label: 'Contado', value: 'contado' },
  { label: 'Crédito', value: 'credito' },
]

// Productos para vincular ítems de compra al stock (recepción de mercadería).
const products = ref<Product[]>([])
const warehouses = ref<Warehouse[]>([])
const warehouseOptions = computed(() => warehouses.value.map((w) => ({ label: w.nombre, value: w.id })))
const monedaOptions = [
  { label: 'Soles (PEN)', value: 'PEN' },
  { label: 'Dólares (USD)', value: 'USD' },
]
const productOptions = computed(() =>
  products.value.map((p) => ({ label: p.nombre, value: p.id })),
)

// ---------- Compras ----------
const purchaseRows = ref<Purchase[]>([])
const loadingPurchases = ref(false)
const showPurchase = ref(false)
const savingPurchase = ref(false)

interface PurchaseItemForm {
  descripcion: string
  cantidad: number
  costo: number
  productId: string | null
  /** Da crédito fiscal (gravado). Desmarca para líneas exoneradas/inafectas. */
  afecto: boolean
  /** Números de serie que ingresan (uno por línea), solo si el producto maneja series. */
  series: string
}

function emptyItem(): PurchaseItemForm {
  return { descripcion: '', cantidad: 1, costo: 0, productId: null, afecto: true, series: '' }
}

interface PurchaseForm {
  supplier_id: string | null
  tipo_doc: string
  serie_numero: string
  fecha: string
  moneda: string
  tipo_cambio: number | null
  condicion_pago: string
  fecha_vencimiento: string | null
  afecta_inventario: boolean
  warehouse_id: string | null
  items: PurchaseItemForm[]
}

function emptyPurchase(): PurchaseForm {
  return {
    supplier_id: null,
    tipo_doc: '01',
    serie_numero: '',
    fecha: today(),
    moneda: 'PEN',
    tipo_cambio: null,
    condicion_pago: 'contado',
    fecha_vencimiento: null,
    afecta_inventario: false,
    warehouse_id: null,
    items: [emptyItem()],
  }
}

const purchaseForm = ref<PurchaseForm>(emptyPurchase())

// Al vincular un producto, autocompleta la descripción del ítem.
function onPickProduct(item: PurchaseItemForm, productId: string | null) {
  item.productId = productId
  const p = products.value.find((x) => x.id === productId)
  if (p) item.descripcion = p.nombre
  if (!p?.maneja_series) item.series = '' // limpia series si el nuevo producto no las maneja
}

// ¿La línea es de un producto que maneja números de serie?
function itemManejaSeries(item: PurchaseItemForm): boolean {
  return !!products.value.find((p) => p.id === item.productId)?.maneja_series
}
// Parsea el textarea de series a una lista limpia (sin vacíos ni duplicados).
function parseSeries(text: string): string[] {
  return Array.from(new Set(text.split(/\r?\n/).map((s) => s.trim()).filter(Boolean)))
}

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
  purchaseForm.value.items.push(emptyItem())
}

function removeItem(i: number) {
  purchaseForm.value.items.splice(i, 1)
}

function openNewPurchase() {
  purchaseForm.value = emptyPurchase()
  showPurchase.value = true
}

async function loadPurchases() {
  if (!company.current) return
  loadingPurchases.value = !purchaseRows.value.length
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
  if (purchaseForm.value.condicion_pago === 'credito' && !purchaseForm.value.fecha_vencimiento) {
    notify({ type: 'warning', message: 'Indica la fecha de vencimiento para una compra a crédito' })
    return
  }
  if (purchaseForm.value.moneda === 'USD' && !(Number(purchaseForm.value.tipo_cambio) > 0)) {
    notify({ type: 'warning', message: 'Ingresa un tipo de cambio válido (> 0) para una compra en dólares' })
    return
  }
  // Series: cada línea serializada que ingresa a inventario debe traer exactamente
  // `cantidad` números de serie únicos (una serie = una unidad física).
  if (purchaseForm.value.afecta_inventario) {
    for (const it of purchaseForm.value.items) {
      if (!itemManejaSeries(it)) continue
      const series = parseSeries(it.series)
      const cant = Number(it.cantidad) || 0
      if (series.length !== cant) {
        notify({ type: 'warning', message: `“${it.descripcion || 'Producto'}” maneja series: ingresa exactamente ${cant} número(s) de serie (tienes ${series.length}).` })
        return
      }
    }
  }
  savingPurchase.value = true
  try {
    await createPurchase(company.current.id, {
      supplier_id: purchaseForm.value.supplier_id,
      tipo_doc: purchaseForm.value.tipo_doc,
      serie_numero: purchaseForm.value.serie_numero,
      fecha: purchaseForm.value.fecha,
      moneda: purchaseForm.value.moneda,
      tipo_cambio: purchaseForm.value.tipo_cambio ?? undefined,
      condicion_pago: purchaseForm.value.condicion_pago,
      fecha_vencimiento: purchaseForm.value.fecha_vencimiento,
      afecta_inventario: purchaseForm.value.afecta_inventario,
      warehouse_id: purchaseForm.value.afecta_inventario ? purchaseForm.value.warehouse_id : null,
      items: purchaseForm.value.items.map((it) => ({
        descripcion: it.descripcion,
        cantidad: it.cantidad,
        costo: it.costo,
        productId: it.productId,
        afecto: it.afecto,
        series: purchaseForm.value.afecta_inventario && itemManejaSeries(it)
          ? parseSeries(it.series)
          : undefined,
      })),
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
  loadingExpenses.value = !expenseRows.value.length
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

async function loadProducts() {
  if (!company.current) return
  try {
    products.value = await listProducts(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  }
}
async function loadWarehouses() {
  if (!company.current) return
  try {
    warehouses.value = await listWarehouses(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  }
}

onMounted(async () => {
  await Promise.all([loadSuppliers(), loadPurchases(), loadExpenses(), loadProducts(), loadWarehouses()])
})
</script>
