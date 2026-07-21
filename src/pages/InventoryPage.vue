<template>
  <q-page class="q-pa-md">
    <div class="row items-center q-mb-md">
      <div class="text-h5">Inventario</div>
    </div>

    <q-card flat bordered>
      <q-tabs
        v-model="tab"
        align="left"
        active-color="primary"
        indicator-color="primary"
        class="text-grey"
      >
        <q-tab name="stock" label="Stock" />
        <q-tab name="movimientos" label="Movimientos" />
        <q-tab name="categorias" label="Categorías" />
        <q-tab name="almacenes" label="Almacenes" />
      </q-tabs>

      <q-separator />

      <q-tab-panels v-model="tab" animated class="bg-transparent">
        <!-- ==================== STOCK ==================== -->
        <q-tab-panel name="stock">
          <q-table
            :rows="stockRows"
            :columns="stockColumns"
            row-key="id"
            :loading="loadingStock"
            flat
            bordered
          />
        </q-tab-panel>

        <!-- ==================== MOVIMIENTOS ==================== -->
        <q-tab-panel name="movimientos">
          <div class="row items-center q-mb-md">
            <q-space />
            <q-btn color="primary" icon="add" label="Registrar movimiento" @click="openMovement" />
          </div>
          <q-table
            :rows="movements"
            :columns="movementColumns"
            row-key="id"
            :loading="loadingMovements"
            flat
            bordered
          />
        </q-tab-panel>

        <!-- ==================== CATEGORÍAS ==================== -->
        <q-tab-panel name="categorias">
          <div class="row items-center q-mb-md">
            <q-space />
            <q-btn color="primary" icon="add" label="Nueva categoría" @click="openCategory" />
          </div>
          <q-table
            :rows="categories"
            :columns="nameColumns"
            row-key="id"
            :loading="loadingCategories"
            flat
            bordered
          />
        </q-tab-panel>

        <!-- ==================== ALMACENES ==================== -->
        <q-tab-panel name="almacenes">
          <div class="row items-center q-mb-md">
            <q-space />
            <q-btn color="primary" icon="add" label="Nuevo almacén" @click="openWarehouse" />
          </div>
          <q-table
            :rows="warehouses"
            :columns="nameColumns"
            row-key="id"
            :loading="loadingWarehouses"
            flat
            bordered
          />
        </q-tab-panel>
      </q-tab-panels>
    </q-card>

    <!-- ==================== Diálogo: registrar movimiento ==================== -->
    <q-dialog v-model="showMovement">
      <q-card style="min-width: 360px">
        <q-card-section class="text-h6">Registrar movimiento</q-card-section>
        <q-card-section class="q-gutter-sm">
          <q-select
            v-model="movForm.productId"
            outlined
            :options="productOptions"
            emit-value
            map-options
            label="Producto"
            :rules="[required('Selecciona un producto')]"
            lazy-rules
          />
          <q-select
            v-model="movForm.warehouseId"
            outlined
            :options="warehouseOptions"
            emit-value
            map-options
            label="Almacén"
            :rules="[required('Selecciona un almacén')]"
            lazy-rules
          />
          <q-select
            v-model="movForm.tipo"
            outlined
            :options="tipoOptions"
            emit-value
            map-options
            label="Tipo"
          />
          <q-input
            v-model.number="movForm.cantidad"
            outlined
            type="number"
            label="Cantidad"
            :rules="qtyRules"
            lazy-rules
          />
          <q-input v-model="movForm.motivo" outlined label="Motivo" />
        </q-card-section>
        <q-card-actions align="right">
          <q-btn v-close-popup flat label="Cancelar" />
          <q-btn color="primary" label="Guardar" :loading="savingMovement" @click="saveMovement" />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <!-- ==================== Diálogo: nueva categoría ==================== -->
    <q-dialog v-model="showCategory">
      <q-card style="min-width: 340px">
        <q-card-section class="text-h6">Nueva categoría</q-card-section>
        <q-card-section class="q-gutter-sm">
          <q-input v-model="categoryName" outlined label="Nombre" autofocus :rules="nameRules" lazy-rules />
        </q-card-section>
        <q-card-actions align="right">
          <q-btn v-close-popup flat label="Cancelar" />
          <q-btn color="primary" label="Guardar" :loading="savingCategory" @click="saveCategory" />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <!-- ==================== Diálogo: nuevo almacén ==================== -->
    <q-dialog v-model="showWarehouse">
      <q-card style="min-width: 340px">
        <q-card-section class="text-h6">Nuevo almacén</q-card-section>
        <q-card-section class="q-gutter-sm">
          <q-input v-model="warehouseName" outlined label="Nombre" autofocus :rules="nameRules" lazy-rules />
        </q-card-section>
        <q-card-actions align="right">
          <q-btn v-close-popup flat label="Cancelar" />
          <q-btn color="primary" label="Guardar" :loading="savingWarehouse" @click="saveWarehouse" />
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
import { required, qtyRules, nameRules, validate } from '@/lib/validation'
import {
  listCategories,
  createCategory,
  listWarehouses,
  createWarehouse,
  listProductOptions,
  listStock,
  listMovements,
  registerMovement,
  type Category,
  type Warehouse,
  type StockRow,
  type InventoryMovement,
  type ProductOption,
  type MovementType,
} from '@/modules/inventory/inventory.api'

const company = useCompanyStore()

const tab = ref<'stock' | 'movimientos' | 'categorias' | 'almacenes'>('stock')

// ---- Datos ----
const products = ref<ProductOption[]>([])
const warehouses = ref<Warehouse[]>([])
const categories = ref<Category[]>([])
const stockRows = ref<StockRow[]>([])
const movements = ref<InventoryMovement[]>([])

// ---- Loading ----
const loadingStock = ref(false)
const loadingMovements = ref(false)
const loadingCategories = ref(false)
const loadingWarehouses = ref(false)

// ---- Mapas nombre por id (para tablas de movimientos) ----
const productMap = computed<Record<string, string>>(() => {
  const m: Record<string, string> = {}
  for (const p of products.value) m[p.id] = p.nombre
  return m
})
const warehouseMap = computed<Record<string, string>>(() => {
  const m: Record<string, string> = {}
  for (const w of warehouses.value) m[w.id] = w.nombre
  return m
})

// ---- Opciones de selects ----
const productOptions = computed(() => products.value.map((p) => ({ label: p.nombre, value: p.id })))
const warehouseOptions = computed(() =>
  warehouses.value.map((w) => ({ label: w.nombre, value: w.id })),
)
const tipoOptions: { label: string; value: MovementType }[] = [
  { label: 'Ingreso', value: 'ingreso' },
  { label: 'Salida', value: 'salida' },
  { label: 'Ajuste', value: 'ajuste' },
]

// ---- Columnas ----
const stockColumns: QTableColumn<StockRow>[] = [
  { name: 'producto', label: 'Producto', field: 'producto', align: 'left', sortable: true },
  { name: 'almacen', label: 'Almacén', field: 'almacen', align: 'left', sortable: true },
  {
    name: 'cantidad',
    label: 'Cantidad',
    field: 'cantidad',
    align: 'right',
    sortable: true,
    format: (v) => Number(v).toFixed(2),
  },
]

const movementColumns: QTableColumn<InventoryMovement>[] = [
  {
    name: 'created_at',
    label: 'Fecha',
    field: 'created_at',
    align: 'left',
    sortable: true,
    format: (v) => new Date(v as string).toLocaleString(),
  },
  {
    name: 'producto',
    label: 'Producto',
    field: (r) => productMap.value[r.product_id] ?? '—',
    align: 'left',
  },
  {
    name: 'almacen',
    label: 'Almacén',
    field: (r) => warehouseMap.value[r.warehouse_id] ?? '—',
    align: 'left',
  },
  { name: 'tipo', label: 'Tipo', field: 'tipo', align: 'left' },
  {
    name: 'cantidad',
    label: 'Cantidad',
    field: 'cantidad',
    align: 'right',
    format: (v) => Number(v).toFixed(2),
  },
  { name: 'motivo', label: 'Motivo', field: 'motivo', align: 'left' },
]

const nameColumns: QTableColumn<Category | Warehouse>[] = [
  { name: 'nombre', label: 'Nombre', field: 'nombre', align: 'left', sortable: true },
  {
    name: 'created_at',
    label: 'Creado',
    field: 'created_at',
    align: 'left',
    format: (v) => new Date(v as string).toLocaleDateString(),
  },
]

// ---- Diálogos ----
const showMovement = ref(false)
const savingMovement = ref(false)
const movForm = ref<{
  productId: string
  warehouseId: string
  tipo: MovementType
  cantidad: number
  motivo: string
}>({ productId: '', warehouseId: '', tipo: 'ingreso', cantidad: 0, motivo: '' })

const showCategory = ref(false)
const savingCategory = ref(false)
const categoryName = ref('')

const showWarehouse = ref(false)
const savingWarehouse = ref(false)
const warehouseName = ref('')

function openMovement() {
  movForm.value = { productId: '', warehouseId: '', tipo: 'ingreso', cantidad: 0, motivo: '' }
  showMovement.value = true
}
function openCategory() {
  categoryName.value = ''
  showCategory.value = true
}
function openWarehouse() {
  warehouseName.value = ''
  showWarehouse.value = true
}

// ---- Cargas ----
async function loadStock() {
  if (!company.current) return
  loadingStock.value = true
  try {
    stockRows.value = await listStock(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loadingStock.value = false
  }
}

async function loadMovements() {
  if (!company.current) return
  loadingMovements.value = true
  try {
    movements.value = await listMovements(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loadingMovements.value = false
  }
}

async function loadCategories() {
  if (!company.current) return
  loadingCategories.value = true
  try {
    categories.value = await listCategories(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loadingCategories.value = false
  }
}

async function loadWarehouses() {
  if (!company.current) return
  loadingWarehouses.value = true
  try {
    warehouses.value = await listWarehouses(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loadingWarehouses.value = false
  }
}

async function loadProducts() {
  if (!company.current) return
  try {
    products.value = await listProductOptions(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  }
}

// ---- Guardados ----
async function saveMovement() {
  if (!company.current) return
  const err = validate([
    [movForm.value.productId, [required('Selecciona un producto')]],
    [movForm.value.warehouseId, [required('Selecciona un almacén')]],
    [movForm.value.cantidad, qtyRules],
  ])
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  savingMovement.value = true
  try {
    await registerMovement(company.current.id, {
      productId: movForm.value.productId,
      warehouseId: movForm.value.warehouseId,
      tipo: movForm.value.tipo,
      cantidad: movForm.value.cantidad,
      motivo: movForm.value.motivo || null,
    })
    showMovement.value = false
    await Promise.all([loadMovements(), loadStock()])
    notify({ type: 'positive', message: 'Movimiento registrado' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    savingMovement.value = false
  }
}

async function saveCategory() {
  if (!company.current) return
  const err = validate([[categoryName.value, nameRules]])
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  savingCategory.value = true
  try {
    await createCategory(company.current.id, categoryName.value.trim())
    showCategory.value = false
    await loadCategories()
    notify({ type: 'positive', message: 'Categoría creada' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    savingCategory.value = false
  }
}

async function saveWarehouse() {
  if (!company.current) return
  const err = validate([[warehouseName.value, nameRules]])
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  savingWarehouse.value = true
  try {
    await createWarehouse(company.current.id, warehouseName.value.trim())
    showWarehouse.value = false
    await loadWarehouses()
    notify({ type: 'positive', message: 'Almacén creado' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    savingWarehouse.value = false
  }
}

onMounted(async () => {
  await Promise.all([
    loadProducts(),
    loadWarehouses(),
    loadCategories(),
    loadStock(),
    loadMovements(),
  ])
})
</script>
