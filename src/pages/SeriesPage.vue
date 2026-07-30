<template>
  <q-page class="q-pa-md">
    <KModuleHeader
      title="Series"
      subtitle="Registro de números de serie · se llena solo con tus compras y ventas"
      :refresh-fn="load"
      new-label="Carga manual"
      show-import
      show-export
      @new="openNew"
      @export="onExport"
    />

    <!-- Filtros ⇄ acciones masivas: se reemplazan en el mismo lugar con la animación. -->
    <div class="k-toolbar-swap q-mb-md">
      <Transition name="k-swap">
        <div
          v-if="selected.length"
          key="bulk"
          class="k-bulk"
        >
          <q-icon
            name="check_circle"
            size="18px"
          />
          <span class="k-bulk-count">{{ selected.length }} seleccionado(s)</span>
          <q-space />
          <q-btn
            flat
            dense
            no-caps
            icon="check_circle"
            label="Activar"
            @click="bulkSetActivo(true)"
          />
          <q-btn
            flat
            dense
            no-caps
            icon="block"
            label="Desactivar"
            @click="bulkSetActivo(false)"
          />
          <q-btn
            flat
            dense
            no-caps
            color="negative"
            icon="delete"
            label="Eliminar"
            @click="bulkDelete"
          />
        </div>
        <div
          v-else
          key="filters"
          class="row items-center q-col-gutter-sm k-filters"
        >
          <div class="col-12 col-md k-search-col">
            <q-input
              v-model="search"
              outlined
              dense
              clearable
              placeholder="Buscar por número de serie…"
            >
              <template #prepend>
                <q-icon name="search" />
              </template>
            </q-input>
          </div>
          <div class="col-6 col-md k-fcol">
            <q-select
              v-model="productFilter"
              outlined
              dense
              emit-value
              map-options
              :options="productFilterOptions"
              label="Producto"
            />
          </div>
          <div class="col-6 col-md k-fcol">
            <q-select
              v-model="situacionFilter"
              outlined
              dense
              emit-value
              map-options
              :options="situacionFilterOptions"
              label="Situación"
            />
          </div>
          <div class="col-6 col-md k-fcol">
            <q-select
              v-model="activoFilter"
              outlined
              dense
              emit-value
              map-options
              :options="activoFilterOptions"
              label="Estado"
            />
          </div>
          <div class="col-6 col-md-auto k-fcol">
            <KDate
              v-model="fechaDesde"
              placeholder="Desde"
            />
          </div>
          <div class="col-6 col-md-auto k-fcol">
            <KDate
              v-model="fechaHasta"
              placeholder="Hasta"
            />
          </div>
        </div>
      </Transition>
    </div>

    <q-table
      v-model:selected="selected"
      selection="multiple"
      :rows="filteredRows"
      :columns="columns"
      row-key="id"
      :loading="loading"
      flat
      bordered
    >
      <!-- Situación (ciclo: Disponible / Vendido / Baja) -->
      <template #body-cell-situacion="props">
        <q-td :props="props">
          <span
            class="k-pill"
            :class="situacionMeta(props.row.estado).cls"
          >
            <i class="k-dot" />{{ situacionMeta(props.row.estado).label }}
          </span>
        </q-td>
      </template>

      <!-- Estado (activo / inactivo, manual) -->
      <template #body-cell-estado="props">
        <q-td :props="props">
          <span
            class="k-pill"
            :class="props.row.activo !== false ? 'k-pill--ok' : 'k-pill--muted'"
          >
            <i class="k-dot" />{{ props.row.activo !== false ? 'Activo' : 'Inactivo' }}
          </span>
        </q-td>
      </template>

      <!-- Origen (compra o carga manual) -->
      <template #body-cell-origen="props">
        <q-td :props="props">
          <span :class="props.row.origen === 'Carga manual' ? 'text-muted' : ''">{{ props.row.origen }}</span>
        </q-td>
      </template>

      <!-- Comprobante de venta -->
      <template #body-cell-comprobante="props">
        <q-td :props="props">
          <span :class="props.row.comprobante === '—' ? 'text-muted' : ''">{{ props.row.comprobante }}</span>
        </q-td>
      </template>

      <!-- Acciones (3 puntitos) -->
      <template #body-cell-acciones="props">
        <q-td
          :props="props"
          class="text-right"
        >
          <q-btn
            flat
            round
            dense
            icon="more_vert"
            size="sm"
            class="k-act-btn"
            aria-label="Acciones"
          >
            <q-tooltip>Acciones</q-tooltip>
            <q-menu
              anchor="bottom right"
              self="top right"
            >
              <q-list
                dense
                style="min-width: 172px"
              >
                <q-item
                  v-close-popup
                  clickable
                  @click="toggleActivo(props.row)"
                >
                  <q-item-section avatar>
                    <q-icon
                      :name="props.row.activo === false ? 'check_circle' : 'block'"
                      size="18px"
                    />
                  </q-item-section>
                  <q-item-section>
                    {{ props.row.activo === false ? 'Activar' : 'Desactivar' }}
                  </q-item-section>
                </q-item>
                <q-item
                  v-close-popup
                  clickable
                  @click="editNota(props.row)"
                >
                  <q-item-section avatar>
                    <q-icon
                      name="edit_note"
                      size="18px"
                    />
                  </q-item-section>
                  <q-item-section>Editar nota</q-item-section>
                </q-item>
                <q-separator />
                <q-item
                  v-close-popup
                  clickable
                  class="text-negative"
                  @click="remove(props.row)"
                >
                  <q-item-section avatar>
                    <q-icon
                      name="delete"
                      size="18px"
                      color="negative"
                    />
                  </q-item-section>
                  <q-item-section>Eliminar</q-item-section>
                </q-item>
              </q-list>
            </q-menu>
          </q-btn>
        </q-td>
      </template>

      <template #no-data>
        <div class="k-empty">
          <q-icon
            name="confirmation_number"
            size="42px"
            class="k-state-icon"
          />
          <div class="text-subtitle1 q-mt-sm">
            {{ serials.length ? 'Sin coincidencias' : 'Aún no hay números de serie' }}
          </div>
          <div class="text-caption text-muted">
            {{ serials.length ? 'Ajusta la búsqueda o los filtros.' : 'Entran solos al comprar, o cárgalos con “Carga manual”.' }}
          </div>
        </div>
      </template>

      <template #loading>
        <KTableSkeleton />
      </template>
    </q-table>

    <!-- Carga manual de series -->
    <q-dialog v-model="show">
      <q-card class="k-dialog-md">
        <q-card-section class="k-modal-head">
          <div class="text-h6">
            Carga manual de series
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
          <div class="text-caption text-muted">
            Para stock inicial o correcciones. Lo normal es que entren solas al registrar la compra.
          </div>
          <q-select
            v-model="form.productId"
            outlined
            :options="productOptions"
            emit-value
            map-options
            label="Producto"
          />
          <div
            v-if="!seriesProducts.length"
            class="text-caption text-warning"
          >
            No hay productos con «¿Maneja series?» activado. Actívalo en el producto.
          </div>
          <q-input
            v-model="form.texto"
            outlined
            type="textarea"
            autogrow
            label="Números de serie (uno por línea)"
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
            :loading="saving"
            :disable="!seriesProducts.length"
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
import { useRealtime } from '@/lib/realtime'
import KTableSkeleton from '@/components/KTableSkeleton.vue'
import KModuleHeader from '@/components/KModuleHeader.vue'
import KDate from '@/components/KDate.vue'
import { exportTableXls } from '@/lib/exportTable'
import {
  listSerials,
  createSerials,
  updateSerialNota,
  setSerialActivo,
  deleteSerial,
  listProducts,
  type ProductSerialRow,
} from '@/modules/products/products.api'
import type { Product } from '@/types'
import { fmtFecha } from '@/lib/date'
import { notify } from '@/lib/toast'

type Estado = ProductSerialRow['estado']

const $q = useQuasar()
const company = useCompanyStore()
// Realtime: refresca al comprar/vender/cambiar/eliminar seriales.
useRealtime('product_serials', () => company.current?.id, () => { void load() })
const serials = ref<ProductSerialRow[]>([])
const seriesProducts = ref<Product[]>([])
const loading = ref(false)
const show = ref(false)
const saving = ref(false)
const form = ref({ productId: '', texto: '' })
const selected = ref<ProductSerialRow[]>([])

/* ---------------- Filtros ---------------- */
const search = ref('')
const productFilter = ref<string>('all')
const situacionFilter = ref<'all' | Estado>('all') // ciclo: disponible/vendido/baja
const activoFilter = ref<'all' | 'activo' | 'inactivo'>('all') // flag manual
const fechaDesde = ref('')
const fechaHasta = ref('')

// Fecha local (YYYY-MM-DD) de un timestamptz, para comparar con el calendario sin desfase UTC.
function localYMD(iso: string): string {
  const d = new Date(iso)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

const productOptions = computed(() =>
  seriesProducts.value.map((p) => ({ label: p.nombre, value: p.id })),
)
// Productos con seriales cargados (para el filtro), derivados de las filas.
const productFilterOptions = computed(() => {
  const seen = new Map<string, string>()
  for (const s of serials.value) if (!seen.has(s.product_id)) seen.set(s.product_id, s.producto)
  return [{ label: 'Todos', value: 'all' }, ...Array.from(seen, ([value, label]) => ({ label, value }))]
})
const situacionFilterOptions = [
  { label: 'Todas', value: 'all' },
  { label: 'Disponible', value: 'disponible' },
  { label: 'Vendido', value: 'vendido' },
  { label: 'Baja', value: 'baja' },
]
const activoFilterOptions = [
  { label: 'Todos', value: 'all' },
  { label: 'Activo', value: 'activo' },
  { label: 'Inactivo', value: 'inactivo' },
]

const filteredRows = computed(() => {
  const q = (search.value ?? '').trim().toLowerCase()
  const desde = fechaDesde.value
  const hasta = fechaHasta.value
  return serials.value.filter((s) => {
    if (productFilter.value !== 'all' && s.product_id !== productFilter.value) return false
    if (situacionFilter.value !== 'all' && s.estado !== situacionFilter.value) return false
    if (activoFilter.value === 'activo' && s.activo === false) return false
    if (activoFilter.value === 'inactivo' && s.activo !== false) return false
    if (desde || hasta) {
      const dia = localYMD(s.created_at)
      if (desde && dia < desde) return false
      if (hasta && dia > hasta) return false
    }
    if (!q) return true
    return s.serie.toLowerCase().includes(q)
  })
})

// Situación (ciclo) → etiqueta + estilo. 'Vendido' lo pone el sistema al facturar.
function situacionMeta(estado: Estado): { label: string; cls: string } {
  switch (estado) {
    case 'disponible':
      return { label: 'Disponible', cls: 'k-pill--ok' }
    case 'vendido':
      return { label: 'Vendido', cls: 'k-pill--info' }
    case 'baja':
      return { label: 'Baja', cls: 'k-pill--muted' }
    default:
      return { label: estado, cls: 'k-pill--muted' }
  }
}

const columns: QTableColumn<ProductSerialRow>[] = [
  { name: 'producto', label: 'Producto', field: 'producto', align: 'left', sortable: true },
  { name: 'serie', label: 'Serie', field: 'serie', align: 'left', sortable: true },
  { name: 'situacion', label: 'Situación', field: 'estado', align: 'left', sortable: true, format: (v) => situacionMeta(v as Estado).label },
  { name: 'estado', label: 'Estado', field: (r) => (r.activo === false ? 0 : 1), align: 'left', sortable: true, format: (v) => (v ? 'Activo' : 'Inactivo') },
  { name: 'origen', label: 'Origen', field: 'origen', align: 'left' },
  { name: 'comprobante', label: 'Comprobante', field: 'comprobante', align: 'left' },
  { name: 'created_at', label: 'Fecha', field: 'created_at', align: 'left', sortable: true, format: (v) => fmtFecha(v as string) },
  { name: 'acciones', label: '', field: 'id', align: 'right' },
]

function openNew() {
  form.value = { productId: '', texto: '' }
  show.value = true
}

// Activar / Desactivar = flag manual (no toca el ciclo disponible/vendido/baja).
async function toggleActivo(row: ProductSerialRow) {
  const nuevo = row.activo === false
  try {
    await setSerialActivo(row.id, nuevo)
    await load()
    notify({ type: 'positive', message: nuevo ? 'Serial activado' : 'Serial desactivado' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  }
}

function editNota(row: ProductSerialRow) {
  $q.dialog({
    title: 'Nota del serial',
    message: `Serie ${row.serie}`,
    prompt: { model: row.nota ?? '', type: 'textarea', label: 'Nota (garantía, IMEI, cliente…)' },
    cancel: true,
  }).onOk(async (val: string) => {
    try {
      await updateSerialNota(row.id, val)
      await load()
      notify({ type: 'positive', message: 'Nota actualizada' })
    } catch (e) {
      notify({ type: 'negative', message: (e as Error).message })
    }
  })
}

function remove(row: ProductSerialRow) {
  $q.dialog({
    title: 'Eliminar serial',
    message: `¿Eliminar la serie "${row.serie}"?`,
    cancel: true,
    persistent: true,
  }).onOk(async () => {
    try {
      await deleteSerial(row.id)
      await load()
      notify({ type: 'positive', message: 'Serial eliminado' })
    } catch (e) {
      notify({ type: 'negative', message: (e as Error).message })
    }
  })
}

async function bulkSetActivo(activo: boolean) {
  const items = [...selected.value]
  if (!items.length) return
  try {
    const res = await Promise.allSettled(items.map((s) => setSerialActivo(s.id, activo)))
    const fail = res.filter((r) => r.status === 'rejected').length
    notify(fail
      ? { type: 'warning', message: `${items.length - fail} actualizado(s) · ${fail} fallaron` }
      : { type: 'positive', message: `${items.length} serial(es) ${activo ? 'activados' : 'desactivados'}` })
  } finally {
    selected.value = []
    await load()
  }
}

function bulkDelete() {
  const items = [...selected.value]
  if (!items.length) return
  $q.dialog({
    title: 'Eliminar seriales',
    message: `¿Eliminar ${items.length} serial(es)? No se puede deshacer.`,
    cancel: true,
    persistent: true,
  }).onOk(async () => {
    try {
      const res = await Promise.allSettled(items.map((s) => deleteSerial(s.id)))
      const fail = res.filter((r) => r.status === 'rejected').length
      notify(fail
        ? { type: 'warning', message: `${items.length - fail} eliminado(s) · ${fail} fallaron` }
        : { type: 'positive', message: `${items.length} serial(es) eliminado(s)` })
    } finally {
      selected.value = []
      await load()
    }
  })
}

function onExport() {
  exportTableXls('series', columns, filteredRows.value)
}

async function load() {
  if (!company.current) return
  loading.value = !serials.value.length
  try {
    serials.value = await listSerials(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
}

async function save() {
  if (!company.current) return
  if (!form.value.productId) {
    notify({ type: 'warning', message: 'Elige un producto' })
    return
  }
  saving.value = true
  try {
    const lista = form.value.texto.split(/\r?\n/)
    const insertadas = await createSerials(company.current.id, form.value.productId, lista)
    show.value = false
    await load()
    if (insertadas.length === 0) {
      notify({ type: 'info', message: 'No se agregó ningún serial (¿vacíos o duplicados?)' })
    } else {
      notify({ type: 'positive', message: `${insertadas.length} serial(es) agregado(s)` })
    }
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    saving.value = false
  }
}

onMounted(async () => {
  if (!company.current) return
  await load()
  try {
    seriesProducts.value = (await listProducts(company.current.id)).filter((p) => p.maneja_series)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  }
})
</script>

<style scoped>
/* Barra de acciones masivas (selección múltiple) */
.k-bulk {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 14px;
  border-radius: var(--k-radius-sm);
  background: var(--k-active-bg);
  color: var(--k-text);
}
.k-bulk-count {
  font-weight: 700;
  font-size: 13px;
}

/* Filtros ⇄ acciones masivas comparten el mismo lugar (giro de cubo vertical). */
/* Animación filtros ⇄ acciones masivas: definida GLOBAL en theme.css (.k-toolbar-swap / .k-swap-*). */

/* Botón de acciones (3 puntitos) */
.k-act-btn {
  color: var(--k-muted);
}
.k-act-btn:hover {
  color: var(--k-text);
}

/* Píldora de estado */
.k-pill {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 3px 10px 3px 8px;
  border-radius: 999px;
  font-size: 11.5px;
  font-weight: 600;
}
.k-pill .k-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: currentColor;
}
.k-pill--ok {
  color: var(--q-positive);
  background: color-mix(in srgb, var(--q-positive) 15%, transparent);
}
.k-pill--info {
  color: #0ea5e9;
  background: color-mix(in srgb, #0ea5e9 15%, transparent);
}
.k-pill--muted {
  color: var(--k-muted);
  background: color-mix(in srgb, var(--k-muted) 18%, transparent);
}

/* Estado vacío */
.k-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  padding: 48px 16px;
  width: 100%;
}
.k-state-icon {
  color: var(--k-muted);
  opacity: 0.6;
}
</style>
