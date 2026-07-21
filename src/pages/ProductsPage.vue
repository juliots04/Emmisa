<template>
  <q-page class="q-pa-md">
    <div class="row items-center q-mb-md">
      <div class="text-h5">Productos</div>
      <q-space />
      <q-btn color="primary" unelevated icon="add" label="Nuevo producto" @click="openNew" />
    </div>

    <q-table :rows="rows" :columns="columns" row-key="id" :loading="loading" flat bordered>
      <template #body-cell-acciones="props">
        <q-td :props="props" class="text-right">
          <q-btn flat dense round size="sm" icon="edit" @click="openEdit(props.row)" />
          <q-btn flat dense round size="sm" icon="delete" color="negative" @click="confirmDelete(props.row)" />
        </q-td>
      </template>
    </q-table>

    <!-- Crear / Editar -->
    <q-dialog v-model="show">
      <q-card style="width: 720px; max-width: 95vw">
        <q-card-section class="row items-center q-pb-none">
          <div class="text-h6">{{ editingId ? 'Editar producto' : 'Nuevo producto' }}</div>
          <q-space />
          <q-btn v-close-popup flat dense round icon="close" />
        </q-card-section>

        <q-tabs
          v-model="tab"
          align="left"
          no-caps
          active-color="primary"
          indicator-color="primary"
          class="text-grey"
        >
          <q-tab name="general" label="General" />
          <q-tab name="almacen" label="Almacén" />
          <q-tab name="compra" label="Compra" />
          <q-tab name="adicional" label="Adicional" />
        </q-tabs>
        <q-separator />

        <q-tab-panels v-model="tab" animated>
          <!-- GENERAL -->
          <q-tab-panel name="general" class="q-gutter-md">
            <div class="row q-col-gutter-md">
              <q-input
                v-model="form.nombre"
                class="col-12 col-sm-8"
                outlined
                label="Nombre *"
                autofocus
                :rules="nameRules"
                lazy-rules
              />
              <q-select
                v-model="form.tipo"
                class="col-12 col-sm-4"
                outlined
                :options="tipoOptions"
                emit-value
                map-options
                label="Tipo"
              />
            </div>
            <q-input v-model="form.nombre_secundario" outlined label="Nombre secundario" />
            <q-input v-model="form.descripcion" outlined type="textarea" autogrow label="Descripción" />

            <div class="row q-col-gutter-md">
              <q-input v-model="form.sku" class="col-6 col-sm-4" outlined label="Código interno" />
              <q-input
                v-model="form.barcode"
                class="col-6 col-sm-4"
                outlined
                label="Código de barra"
                :rules="codeRules"
                lazy-rules              />
              <q-select
                v-model="form.unidad_medida"
                class="col-12 col-sm-4"
                outlined
                :options="unidadOptions"
                emit-value
                map-options
                label="Unidad"
              />
            </div>

            <div class="row q-col-gutter-md">
              <q-select
                v-model="form.tipo_afectacion"
                class="col-12 col-sm-6"
                outlined
                :options="afectacionOptions"
                emit-value
                map-options
                label="Tipo de afectación (IGV)"
              />
              <q-select
                v-model="form.moneda"
                class="col-6 col-sm-3"
                outlined
                :options="['PEN', 'USD']"
                label="Moneda"
              />
              <q-input
                v-model.number="form.precio"
                class="col-6 col-sm-3"
                outlined
                type="number"
                label="Precio unitario"
                :rules="priceRules"
                lazy-rules              />
            </div>

            <div class="row items-center justify-between">
              <q-toggle
                v-model="form.incluye_igv"
                label="Precio incluye IGV"
                :disable="form.tipo_afectacion !== '10'"
              />
              <div class="k-igv">
                <span><span class="k-igv-lbl">Valor</span> S/ {{ igv.valor.toFixed(2) }}</span>
                <span><span class="k-igv-lbl">IGV</span> S/ {{ igv.igv.toFixed(2) }}</span>
                <span class="k-igv-total"><span class="k-igv-lbl">Total</span> S/ {{ igv.total.toFixed(2) }}</span>
              </div>
            </div>
          </q-tab-panel>

          <!-- ALMACEN -->
          <q-tab-panel name="almacen" class="q-gutter-md">
            <div v-if="editingId" class="text-caption text-grey">
              El stock se ajusta desde el módulo <b>Inventario</b>.
            </div>
            <template v-else>
              <div v-if="warehouses.length === 0" class="text-caption text-grey">
                Aún no hay almacenes (créalos en Inventario). El stock inicial es opcional.
              </div>
              <q-select
                v-else
                v-model="form.warehouse_id"
                outlined
                clearable
                :options="warehouseOptions"
                emit-value
                map-options
                label="Almacén"
              />
              <div class="row q-col-gutter-md">
                <q-input
                  v-model.number="form.stock_inicial"
                  class="col-6"
                  outlined
                  type="number"
                  label="Stock inicial"
                  :rules="stockInicialRules"
                  lazy-rules                />
                <q-input
                  v-model.number="form.stock_minimo"
                  class="col-6"
                  outlined
                  type="number"
                  label="Stock mínimo"
                  :rules="stockMinRules"
                  lazy-rules                />
              </div>
            </template>
          </q-tab-panel>

          <!-- COMPRA -->
          <q-tab-panel name="compra" class="q-gutter-md">
            <q-input
              v-model.number="form.costo"
              outlined
              type="number"
              label="Costo de compra (unitario)"
              hint="Para calcular tu margen/utilidad"
              :rules="costRules"
              lazy-rules
            />
          </q-tab-panel>

          <!-- ADICIONAL -->
          <q-tab-panel name="adicional">
            <div class="row q-col-gutter-md">
              <q-input
                v-model="form.codigo_sunat"
                class="col-12 col-sm-6"
                outlined
                label="Código SUNAT"
                :rules="codeRules"
                lazy-rules              />
              <q-input v-model="form.linea_producto" class="col-12 col-sm-6" outlined label="Línea de producto" />
              <q-input v-model="form.modelo" class="col-12 col-sm-6" outlined label="Modelo" />
              <q-input v-model="form.registro_sanitario" class="col-12 col-sm-6" outlined label="Registro sanitario" />
              <q-input v-model="form.codigo_digemid" class="col-12 col-sm-6" outlined label="Código DIGEMID" />
              <q-input v-model="form.codigo_fabrica" class="col-12 col-sm-6" outlined label="Código de fábrica" />
            </div>
          </q-tab-panel>
        </q-tab-panels>

        <q-separator />
        <q-card-actions align="right">
          <q-btn v-close-popup flat label="Cancelar" />
          <q-btn
            color="primary"
            unelevated
            :label="editingId ? 'Guardar cambios' : 'Crear producto'"
            :loading="saving"
            @click="save"
          />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useQuasar, type QTableColumn } from 'quasar'
import { useCompanyStore } from '@/stores/company'
import {
  listProducts,
  createProduct,
  updateProduct,
  deleteProduct,
} from '@/modules/products/products.api'
import { listWarehouses, registerMovement } from '@/modules/inventory/inventory.api'
import { round2 } from '@/modules/sunat'
import {
  validate,
  nameRules,
  priceRules,
  costRules,
  stockMinRules,
  onlyDigits,
  nonNegative,
  type Rule,
} from '@/lib/validation'
import type { Product } from '@/types'
import { notify } from '@/lib/toast'

const company = useCompanyStore()
const $q = useQuasar()

const rows = ref<Product[]>([])
const loading = ref(false)
const show = ref(false)
const saving = ref(false)
const tab = ref('general')
const editingId = ref<string | null>(null)
const warehouses = ref<{ id: string; nombre: string }[]>([])

const tipoOptions = [
  { label: 'Bien', value: 'bien' },
  { label: 'Servicio', value: 'servicio' },
]
const unidadOptions = [
  { label: 'Unidades (NIU)', value: 'NIU' },
  { label: 'Servicio (ZZ)', value: 'ZZ' },
  { label: 'Kilogramos (KGM)', value: 'KGM' },
  { label: 'Litros (LTR)', value: 'LTR' },
  { label: 'Metros (MTR)', value: 'MTR' },
  { label: 'Cajas (BX)', value: 'BX' },
]
const afectacionOptions = [
  { label: 'Gravado - Operación Onerosa', value: '10' },
  { label: 'Exonerado', value: '20' },
  { label: 'Inafecto', value: '30' },
]

// Reglas coherentes con validation.ts (reutilizadas en template y en la guarda de save()).
const codeRules: Rule[] = [onlyDigits()] // códigos numéricos opcionales (barra, SUNAT)
const stockInicialRules: Rule[] = [nonNegative('El stock inicial no puede ser negativo')]

function blankForm() {
  return {
    nombre: '',
    nombre_secundario: '',
    descripcion: '',
    modelo: '',
    sku: '',
    barcode: '',
    tipo: 'bien' as 'bien' | 'servicio',
    unidad_medida: 'NIU',
    tipo_afectacion: '10',
    moneda: 'PEN',
    precio: 0,
    costo: 0,
    incluye_igv: true,
    stock_minimo: 0,
    codigo_sunat: '',
    linea_producto: '',
    registro_sanitario: '',
    codigo_digemid: '',
    codigo_fabrica: '',
    warehouse_id: null as string | null,
    stock_inicial: 0,
  }
}
const form = ref(blankForm())

const warehouseOptions = computed(() => warehouses.value.map((w) => ({ label: w.nombre, value: w.id })))

// IGV calculado automáticamente (no es un campo, es un desglose en vivo)
const igv = computed(() => {
  const precio = Number(form.value.precio) || 0
  if (form.value.tipo_afectacion !== '10') return { valor: round2(precio), igv: 0, total: round2(precio) }
  if (form.value.incluye_igv) {
    const valor = round2(precio / 1.18)
    return { valor, igv: round2(precio - valor), total: round2(precio) }
  }
  const impuesto = round2(precio * 0.18)
  return { valor: round2(precio), igv: impuesto, total: round2(precio + impuesto) }
})

const columns: QTableColumn<Product>[] = [
  { name: 'nombre', label: 'Nombre', field: 'nombre', align: 'left', sortable: true },
  { name: 'sku', label: 'Código', field: (r) => r.sku ?? '—', align: 'left' },
  { name: 'unidad', label: 'Unidad', field: 'unidad_medida', align: 'left' },
  {
    name: 'precio',
    label: 'Precio',
    field: 'precio',
    align: 'right',
    format: (v) => `S/ ${Number(v).toFixed(2)}`,
  },
  { name: 'acciones', label: '', field: 'id', align: 'right' },
]

function openNew() {
  editingId.value = null
  form.value = blankForm()
  tab.value = 'general'
  show.value = true
}

function openEdit(p: Product) {
  editingId.value = p.id
  form.value = {
    ...blankForm(),
    nombre: p.nombre,
    nombre_secundario: p.nombre_secundario ?? '',
    descripcion: p.descripcion ?? '',
    modelo: p.modelo ?? '',
    sku: p.sku ?? '',
    barcode: p.barcode ?? '',
    tipo: p.tipo,
    unidad_medida: p.unidad_medida,
    tipo_afectacion: p.tipo_afectacion,
    moneda: p.moneda ?? 'PEN',
    precio: p.precio,
    costo: p.costo,
    incluye_igv: p.incluye_igv ?? true,
    stock_minimo: p.stock_minimo ?? 0,
    codigo_sunat: p.codigo_sunat ?? '',
    linea_producto: p.linea_producto ?? '',
    registro_sanitario: p.registro_sanitario ?? '',
    codigo_digemid: p.codigo_digemid ?? '',
    codigo_fabrica: p.codigo_fabrica ?? '',
  }
  tab.value = 'general'
  show.value = true
}

function confirmDelete(p: Product) {
  $q.dialog({
    title: 'Eliminar producto',
    message: `¿Eliminar "${p.nombre}"?`,
    cancel: true,
    persistent: true,
  }).onOk(async () => {
    try {
      await deleteProduct(p.id)
      await load()
      notify({ type: 'positive', message: 'Producto eliminado' })
    } catch (e) {
      notify({ type: 'negative', message: (e as Error).message })
    }
  })
}

async function load() {
  if (!company.current) return
  loading.value = true
  try {
    rows.value = await listProducts(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
}

async function save() {
  if (!company.current) return
  const err = validate([
    [form.value.nombre, nameRules],
    [form.value.precio, priceRules],
    [form.value.costo, costRules],
    [form.value.stock_minimo, stockMinRules],
    [form.value.stock_inicial, stockInicialRules],
    [form.value.barcode, codeRules],
    [form.value.codigo_sunat, codeRules],
  ])
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  saving.value = true
  try {
    const payload = {
      nombre: form.value.nombre,
      precio: form.value.precio,
      tipo: form.value.tipo,
      unidad_medida: form.value.unidad_medida,
      sku: form.value.sku || null,
      nombre_secundario: form.value.nombre_secundario || null,
      descripcion: form.value.descripcion || null,
      modelo: form.value.modelo || null,
      barcode: form.value.barcode || null,
      tipo_afectacion: form.value.tipo_afectacion,
      moneda: form.value.moneda,
      costo: form.value.costo,
      incluye_igv: form.value.incluye_igv,
      stock_minimo: form.value.stock_minimo,
      codigo_sunat: form.value.codigo_sunat || null,
      linea_producto: form.value.linea_producto || null,
      registro_sanitario: form.value.registro_sanitario || null,
      codigo_digemid: form.value.codigo_digemid || null,
      codigo_fabrica: form.value.codigo_fabrica || null,
    }
    if (editingId.value) {
      await updateProduct(editingId.value, payload)
    } else {
      const product = await createProduct(company.current.id, payload)
      if (form.value.warehouse_id && form.value.stock_inicial > 0) {
        try {
          await registerMovement(company.current.id, {
            productId: product.id,
            warehouseId: form.value.warehouse_id,
            tipo: 'ingreso',
            cantidad: form.value.stock_inicial,
            motivo: 'Stock inicial',
          })
        } catch {
          /* el módulo de inventario es opcional */
        }
      }
    }
    show.value = false
    await load()
    notify({
      type: 'positive',
      message: editingId.value ? 'Producto actualizado' : 'Producto creado',
    })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    saving.value = false
  }
}

onMounted(async () => {
  await load()
  try {
    if (company.current) warehouses.value = await listWarehouses(company.current.id)
  } catch {
    /* inventario opcional */
  }
})
</script>

<style scoped>
/* Resumen de IGV: fuente normal (no monoespaciada), etiquetas sutiles. */
.k-igv {
  display: flex;
  gap: 18px;
  align-items: baseline;
  font-size: 13.5px;
  font-family: 'Hanken Grotesk', system-ui, sans-serif;
}
.k-igv-lbl {
  margin-right: 5px;
  font-size: 11px;
  color: var(--k-muted);
  text-transform: uppercase;
  letter-spacing: 0.3px;
}
.k-igv-total {
  font-weight: 700;
}
</style>
