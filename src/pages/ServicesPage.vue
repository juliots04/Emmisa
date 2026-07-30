<template>
  <q-page class="q-pa-md">
    <KModuleHeader
      title="Servicios"
      subtitle="Catálogo de servicios que ofreces, con su precio e IGV"
      :refresh-fn="load"
      new-label="Nuevo"
      show-import
      show-export
      @new="openNew"
      @export="onExport"
    />

    <!-- Filtros ⇄ acciones masivas: mismo lugar, con el giro cubo (global). -->
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
            icon="content_copy"
            label="Duplicar"
            @click="bulkDuplicate"
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
              :placeholder="`Buscar por ${searchFieldLabel.toLowerCase()}…`"
            >
              <template #prepend>
                <q-icon name="search" />
              </template>
            </q-input>
          </div>
          <div class="col-6 col-md k-fcol">
            <q-select
              v-model="searchField"
              outlined
              dense
              emit-value
              map-options
              :options="searchFieldOptions"
              label="Filtrar por"
            />
          </div>
          <div class="col-6 col-md k-fcol">
            <q-select
              v-model="estadoFilter"
              outlined
              dense
              emit-value
              map-options
              :options="estadoFilterOptions"
              label="Estado"
            />
          </div>
          <div class="col-6 col-md k-fcol">
            <q-select
              v-model="afectacionFilter"
              outlined
              dense
              emit-value
              map-options
              :options="afectacionFilterOptions"
              label="Afectación"
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
      class="k-prod-table"
      :rows-per-page-options="[12, 25, 50, 0]"
    >
      <!-- ID: número de fila (uuid en tooltip) -->
      <template #body-cell-id="props">
        <q-td :props="props">
          <span class="k-id">
            {{ props.rowIndex + 1 }}
            <q-tooltip>{{ props.row.id }}</q-tooltip>
          </span>
        </q-td>
      </template>

      <!-- Unidad de medida -->
      <template #body-cell-unidad="props">
        <q-td :props="props">
          <span class="k-chip">
            {{ props.row.unidad_medida || 'ZZ' }}
            <q-tooltip>{{ unidadNombre(props.row.unidad_medida) }}</q-tooltip>
          </span>
        </q-td>
      </template>

      <!-- Imagen -->
      <template #body-cell-imagen="props">
        <q-td
          :props="props"
          class="text-center"
        >
          <img
            :src="props.row.imagen_url || '/product-placeholder.svg'"
            class="k-prod-img"
            alt=""
            loading="lazy"
            @error="onImgError"
          >
        </q-td>
      </template>

      <!-- Nombre (+ SKU) -->
      <template #body-cell-producto="props">
        <q-td :props="props">
          <div class="k-prod-name">
            {{ props.row.nombre }}
          </div>
          <div
            v-if="props.row.sku"
            class="k-prod-sku"
          >
            {{ props.row.sku }}
          </div>
        </q-td>
      </template>

      <!-- Descripción (recortada, completa en tooltip) -->
      <template #body-cell-descripcion="props">
        <q-td :props="props">
          <div
            v-if="props.row.descripcion"
            class="k-desc"
          >
            {{ props.row.descripcion }}
            <q-tooltip max-width="320px">
              {{ props.row.descripcion }}
            </q-tooltip>
          </div>
          <span
            v-else
            class="text-muted"
          >—</span>
        </q-td>
      </template>

      <!-- Detracción -->
      <template #body-cell-detraccion="props">
        <q-td
          :props="props"
          class="text-center"
        >
          {{ props.row.detraccion ? 'Sí' : 'No' }}
        </q-td>
      </template>

      <!-- Historial (ventas/compras del servicio) -->
      <template #body-cell-historial="props">
        <q-td
          :props="props"
          class="text-center"
        >
          <q-btn
            flat
            round
            dense
            icon="history"
            class="k-ico-btn"
            @click="openHistorial(props.row)"
          >
            <q-tooltip>Historial: ventas y compras</q-tooltip>
          </q-btn>
        </q-td>
      </template>

      <!-- Tiene IGV (venta) -->
      <template #body-cell-igv_venta="props">
        <q-td
          :props="props"
          class="text-center"
        >
          {{ props.row.tipo_afectacion === '10' ? 'Sí' : 'No' }}
        </q-td>
      </template>

      <!-- Tiene IGV (compra) -->
      <template #body-cell-igv_compra="props">
        <q-td
          :props="props"
          class="text-center"
        >
          {{ props.row.tipo_afectacion_compra === '10' ? 'Sí' : 'No' }}
        </q-td>
      </template>

      <!-- Estado -->
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

      <!-- Acciones -->
      <template #body-cell-acciones="props">
        <q-td
          :props="props"
          class="text-right k-act-td"
        >
          <q-btn
            flat
            round
            icon="more_vert"
            size="md"
            class="k-act-btn"
          >
            <q-menu
              anchor="bottom right"
              self="top right"
            >
              <q-list
                dense
                style="min-width: 176px"
              >
                <q-item
                  v-close-popup
                  clickable
                  @click="openEdit(props.row)"
                >
                  <q-item-section avatar>
                    <q-icon
                      name="edit"
                      size="18px"
                    />
                  </q-item-section>
                  <q-item-section>Editar</q-item-section>
                </q-item>
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
            name="design_services"
            size="42px"
            class="k-state-icon"
          />
          <div class="text-subtitle1 q-mt-sm">
            {{ rows.length ? 'Sin coincidencias' : 'Aún no tienes servicios' }}
          </div>
          <div class="text-caption text-muted">
            {{ rows.length ? 'Ajusta la búsqueda o los filtros.' : 'Crea tu primer servicio con “Nuevo”.' }}
          </div>
        </div>
      </template>

      <template #loading>
        <KTableSkeleton />
      </template>
    </q-table>

    <!-- Crear / Editar servicio -->
    <q-dialog
      v-model="show"
      :maximized="$q.screen.lt.sm"
      @hide="onDialogHide"
    >
      <q-card class="k-dialog-lg">
        <q-card-section class="k-modal-head">
          <div class="text-h6">
            {{ editingId ? 'Editar servicio' : 'Nuevo servicio' }}
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

        <q-tabs
          v-model="tab"
          align="left"
          no-caps
          active-color="primary"
          indicator-color="primary"
          class="text-muted"
        >
          <q-tab
            name="general"
            label="General"
          />
          <q-tab
            name="adicional"
            label="Atributos"
          />
        </q-tabs>
        <q-separator />

        <q-tab-panels
          v-model="tab"
          animated
        >
          <!-- GENERAL: lo esencial de un servicio -->
          <q-tab-panel name="general">
            <div class="row q-col-gutter-md items-start">
              <q-input
                v-model="form.nombre"
                class="col-12 col-sm-5"
                outlined
                label="Nombre *"
                autofocus
                :rules="nameRules"
                lazy-rules="ondemand"
                hide-bottom-space
              />
              <q-input
                v-model.number="form.precio"
                class="col-6 col-sm-4"
                outlined
                type="number"
                :label="`Precio (${form.incluye_igv ? 'con' : 'sin'} IGV) *`"
                :rules="priceRules"
                lazy-rules="ondemand"
                hide-bottom-space
              />
              <q-input
                v-model.number="form.costo"
                class="col-6 col-sm-3"
                outlined
                type="number"
                label="Costo (Compra)"
              />
              <q-select
                v-model="form.unidad_medida"
                class="col-6 col-sm-6"
                outlined
                :options="unidadOptions"
                emit-value
                map-options
                label="Unidad"
              />
              <q-select
                v-model="form.moneda"
                class="col-6 col-sm-6"
                outlined
                :options="monedaOptions"
                emit-value
                map-options
                label="Moneda"
              />
              <!-- Los 3 de IGV en una fila -->
              <q-select
                v-model="form.tipo_afectacion"
                class="col-12 col-sm-4"
                outlined
                :options="afectacionOptions"
                emit-value
                map-options
                label="Afectación IGV (Venta)"
              />
              <q-select
                v-model="form.tipo_afectacion_compra"
                class="col-12 col-sm-4"
                outlined
                :options="afectacionOptions"
                emit-value
                map-options
                label="Afectación IGV (Compra)"
              />
              <div class="col-12 col-sm-4 self-center k-checks">
                <q-checkbox
                  v-model="form.incluye_igv"
                  :disable="form.tipo_afectacion !== '10'"
                  label="El precio incluye IGV"
                />
              </div>
              <q-input
                v-model="form.descripcion"
                class="col-12"
                outlined
                label="Descripción"
              />
            </div>
          </q-tab-panel>

          <!-- ADICIONAL: códigos, imagen y opciones del comprobante -->
          <q-tab-panel name="adicional">
            <div class="row q-col-gutter-md items-start">
              <!-- Imagen -->
              <div class="col-12 col-sm-4 k-img-col">
                <div class="k-img-preview-wrap">
                  <img
                    v-if="form.imagen_url"
                    :src="form.imagen_url"
                    class="k-img-preview"
                    alt=""
                  >
                  <div
                    v-else
                    class="k-img-empty"
                  >
                    <q-icon
                      name="add_photo_alternate"
                      size="30px"
                    />
                    <span>Sin foto</span>
                  </div>
                </div>
                <div class="k-img-actions">
                  <button
                    type="button"
                    class="k-upload-btn"
                    :disabled="uploadingImg"
                    @click="pickFile"
                  >
                    <q-spinner
                      v-if="uploadingImg"
                      size="16px"
                    />
                    <q-icon
                      v-else
                      :name="form.imagen_url ? 'photo_camera' : 'add_photo_alternate'"
                      size="18px"
                    />
                    {{ form.imagen_url ? 'Cambiar' : 'Subir foto' }}
                  </button>
                  <button
                    v-if="form.imagen_url"
                    type="button"
                    class="k-upload-btn k-upload-btn--danger"
                    :disabled="uploadingImg"
                    @click="clearImage"
                  >
                    <q-icon
                      name="delete"
                      size="16px"
                    />
                    Quitar
                  </button>
                </div>
                <input
                  ref="fileInput"
                  type="file"
                  accept="image/*"
                  style="display: none"
                  @change="onFileChange"
                >
              </div>

              <!-- Códigos + opciones -->
              <div class="col-12 col-sm">
                <div class="row q-col-gutter-md">
                  <q-input
                    v-model="form.sku"
                    class="col-12 col-sm-6"
                    outlined
                    label="Código interno"
                  />
                  <q-input
                    v-model="form.codigo_sunat"
                    class="col-12 col-sm-6"
                    outlined
                    label="Código SUNAT"
                  />
                  <div class="col-12">
                    <div class="row q-col-gutter-sm k-checks">
                      <q-checkbox
                        v-model="form.detraccion"
                        class="col-12 col-sm-6"
                        label="Sujeto a detracción"
                      />
                      <q-checkbox
                        v-model="form.restringir_cpe"
                        class="col-12 col-sm-6"
                        label="Restringir venta en CPE"
                      />
                      <q-checkbox
                        v-model="form.canje_puntos"
                        class="col-12 col-sm-6"
                        label="¿Canjeable por puntos?"
                      />
                    </div>
                  </div>
                  <div class="col-12 k-checks">
                    <q-checkbox
                      v-model="form.activo"
                      label="Activo"
                    />
                  </div>
                </div>
              </div>
            </div>
          </q-tab-panel>
        </q-tab-panels>

        <q-separator />
        <q-card-actions align="right">
          <q-btn
            v-close-popup
            flat
            label="Cancelar"
          />
          <q-btn
            color="primary"
            unelevated
            :label="editingId ? 'Guardar cambios' : 'Crear servicio'"
            :loading="saving"
            @click="save"
          />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <!-- Historial del servicio (ventas · compras) -->
    <q-dialog
      v-model="histShow"
      :maximized="$q.screen.lt.sm"
    >
      <q-card class="k-dialog-lg k-hist-card">
        <q-card-section class="k-modal-head">
          <div>
            <div class="text-h6">
              Historial
            </div>
            <div class="text-caption text-muted">
              {{ histTitle }}
            </div>
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

        <q-tabs
          v-model="histTab"
          align="left"
          no-caps
          active-color="primary"
          indicator-color="primary"
          class="text-muted"
        >
          <q-tab
            name="ventas"
            label="Últimas ventas"
          />
          <q-tab
            name="compras"
            label="Últimas compras"
          />
        </q-tabs>
        <q-separator />

        <q-tab-panels
          v-model="histTab"
          animated
        >
          <q-tab-panel
            name="ventas"
            class="k-hist-panel"
          >
            <q-table
              :rows="histSales"
              :columns="salesCols"
              row-key="id"
              :loading="histLoading"
              flat
              bordered
              dense
              class="k-hist-table"
              :rows-per-page-options="[10, 25, 0]"
            >
              <template #body-cell-tipo="props">
                <q-td :props="props">
                  <span class="k-chip">{{ tipoDocLabel(props.value) }}</span>
                </q-td>
              </template>
              <template #body-cell-estado="props">
                <q-td :props="props">
                  <span
                    class="k-pill"
                    :class="estadoMeta(props.value).cls"
                  >{{ estadoMeta(props.value).label }}</span>
                </q-td>
              </template>
              <template #loading>
                <KTableSkeleton />
              </template>
              <template #no-data>
                <div class="k-hist-empty text-muted">
                  <q-icon
                    name="point_of_sale"
                    size="30px"
                    class="k-state-icon"
                  />
                  <span>Sin ventas de este servicio</span>
                </div>
              </template>
            </q-table>
          </q-tab-panel>

          <q-tab-panel
            name="compras"
            class="k-hist-panel"
          >
            <q-table
              :rows="histPurchases"
              :columns="purchaseCols"
              row-key="id"
              :loading="histLoading"
              flat
              bordered
              dense
              class="k-hist-table"
              :rows-per-page-options="[10, 25, 0]"
            >
              <template #body-cell-tipo="props">
                <q-td :props="props">
                  <span class="k-chip">{{ tipoDocLabel(props.value) }}</span>
                </q-td>
              </template>
              <template #loading>
                <KTableSkeleton />
              </template>
              <template #no-data>
                <div class="k-hist-empty text-muted">
                  <q-icon
                    name="local_shipping"
                    size="30px"
                    class="k-state-icon"
                  />
                  <span>Sin compras de este servicio</span>
                </div>
              </template>
            </q-table>
          </q-tab-panel>
        </q-tab-panels>
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
import {
  listProducts,
  createProduct,
  updateProduct,
  deleteProduct,
  uploadProductImage,
  removeProductImage,
} from '@/modules/products/products.api'
import { listProductSales, type ProductSaleRow } from '@/modules/documents/documents.api'
import { listProductPurchases, type ProductPurchaseRow } from '@/modules/purchases/purchases.api'
import { exportTableXls } from '@/lib/exportTable'
import { round2 } from '@/modules/sunat'
import { fmtFecha } from '@/lib/date'
import type { Product } from '@/types'
import { validate, nameRules, priceRules } from '@/lib/validation'
import { notify } from '@/lib/toast'

const $q = useQuasar()
const company = useCompanyStore()
// Realtime: refresca al crear/editar/eliminar servicios (products).
useRealtime('products', () => company.current?.id, () => { void load() })
const rows = ref<Product[]>([])
const loading = ref(false)
const show = ref(false)
const saving = ref(false)
const editingId = ref<string | null>(null)
const tab = ref<'general' | 'adicional'>('general')
const uploadingImg = ref(false)
const originalImageUrl = ref('')
const selected = ref<Product[]>([])

// Filtros: búsqueda (por nombre/código/descripción) + estado + afectación IGV.
const search = ref('')
const searchField = ref<'nombre' | 'sku' | 'descripcion'>('nombre')
const estadoFilter = ref<'all' | 'activo' | 'inactivo'>('all')
const afectacionFilter = ref<'all' | '10' | '20' | '30' | '40'>('all')

const searchFieldOptions = [
  { label: 'Nombre', value: 'nombre' },
  { label: 'Código interno', value: 'sku' },
  { label: 'Descripción', value: 'descripcion' },
]
const estadoFilterOptions = [
  { label: 'Todos', value: 'all' },
  { label: 'Activo', value: 'activo' },
  { label: 'Inactivo', value: 'inactivo' },
]
const afectacionFilterOptions = [
  { label: 'Todas', value: 'all' },
  { label: 'Gravado', value: '10' },
  { label: 'Exonerado', value: '20' },
  { label: 'Inafecto', value: '30' },
  { label: 'Exportación', value: '40' },
]
const searchFieldLabel = computed(
  () => searchFieldOptions.find((o) => o.value === searchField.value)?.label ?? 'Nombre',
)

const filteredRows = computed(() => {
  const q = search.value.trim().toLowerCase()
  return rows.value.filter((p) => {
    if (estadoFilter.value === 'activo' && p.activo === false) return false
    if (estadoFilter.value === 'inactivo' && p.activo !== false) return false
    if (afectacionFilter.value !== 'all' && p.tipo_afectacion !== afectacionFilter.value) return false
    if (!q) return true
    const hay = searchField.value === 'sku' ? (p.sku ?? '')
      : searchField.value === 'descripcion' ? (p.descripcion ?? '')
      : p.nombre
    return hay.toLowerCase().includes(q)
  })
})

const afectacionOptions = [
  { label: 'Gravado (10)', value: '10' },
  { label: 'Exonerado (20)', value: '20' },
  { label: 'Inafecto (30)', value: '30' },
  { label: 'Exportación (40)', value: '40' },
]
const unidadOptions = [
  { label: 'Servicio (ZZ)', value: 'ZZ' },
  { label: 'Unidades (NIU)', value: 'NIU' },
  { label: 'Horas (HUR)', value: 'HUR' },
  { label: 'Días (DAY)', value: 'DAY' },
]
const monedaOptions = [
  { label: 'Soles (PEN)', value: 'PEN' },
  { label: 'Dólares (USD)', value: 'USD' },
]

function blankForm() {
  return {
    nombre: '',
    precio: 0,
    costo: 0,
    unidad_medida: 'ZZ',
    moneda: 'PEN',
    tipo_afectacion: '10',
    tipo_afectacion_compra: '10',
    incluye_igv: true,
    codigo_sunat: '',
    descripcion: '',
    sku: '',
    imagen_url: '',
    detraccion: false,
    restringir_cpe: false,
    canje_puntos: false,
    activo: true,
  }
}
const form = ref(blankForm())

function unidadNombre(v?: string): string {
  return unidadOptions.find((u) => u.value === (v || 'ZZ'))?.label ?? (v || 'ZZ')
}
function onImgError(e: Event) {
  const img = e.target as HTMLImageElement
  if (!img.src.endsWith('/product-placeholder.svg')) img.src = '/product-placeholder.svg'
}
// Valor de venta unitario SIN IGV: descuenta el IGV si el precio lo incluye.
function valorVentaNeto(p: Product): number {
  const precio = Number(p.precio) || 0
  if (p.tipo_afectacion === '10' && p.incluye_igv) return round2(precio / 1.18)
  return round2(precio)
}
const money = (v: unknown, row: Product) => `${row.moneda === 'USD' ? 'US$' : 'S/'} ${Number(v).toFixed(2)}`

const columns: QTableColumn<Product>[] = [
  { name: 'id', label: 'ID', field: 'id', align: 'left' },
  { name: 'unidad', label: 'Unidad', field: 'unidad_medida', align: 'left', sortable: true },
  { name: 'imagen', label: 'Imagen', field: 'imagen_url', align: 'center' },
  { name: 'producto', label: 'Nombre', field: 'nombre', align: 'left', sortable: true },
  { name: 'descripcion', label: 'Descripción', field: (r) => r.descripcion ?? '', align: 'left' },
  { name: 'codigo_sunat', label: 'Cód. SUNAT', field: (r) => r.codigo_sunat || '—', align: 'left' },
  { name: 'detraccion', label: 'Detracción', field: (r) => (r.detraccion ? 1 : 0), align: 'center', sortable: true },
  { name: 'historial', label: 'Historial', field: 'id', align: 'center' },
  { name: 'precio_venta', label: 'P.Unitario (Venta)', field: 'precio', align: 'right', sortable: true, format: money },
  { name: 'precio_compra', label: 'P.Unitario (Compra)', field: 'costo', align: 'right', sortable: true, format: money },
  { name: 'p_venta', label: 'P. venta', field: (r) => valorVentaNeto(r), align: 'right', sortable: true, format: money },
  { name: 'igv_venta', label: 'Tiene Igv (Venta)', field: (r) => (r.tipo_afectacion === '10' ? 1 : 0), align: 'center', sortable: true },
  { name: 'igv_compra', label: 'Tiene Igv (Compra)', field: (r) => (r.tipo_afectacion_compra === '10' ? 1 : 0), align: 'center', sortable: true },
  { name: 'estado', label: 'Estado', field: (r) => (r.activo === false ? 0 : 1), align: 'left', sortable: true },
  { name: 'acciones', label: '', field: 'id', align: 'right' },
]

/* ---------------- Imagen ---------------- */
const fileInput = ref<HTMLInputElement | null>(null)
function pickFile() {
  fileInput.value?.click()
}
function onFileChange(e: Event) {
  const input = e.target as HTMLInputElement
  void onPickImage(input.files?.[0] ?? null)
  input.value = ''
}
async function onPickImage(file: File | null) {
  if (!file || !company.current) return
  uploadingImg.value = true
  try {
    const prev = form.value.imagen_url
    const url = await uploadProductImage(company.current.id, file)
    form.value.imagen_url = url
    if (prev && prev !== originalImageUrl.value && prev !== url) void removeProductImage(prev)
    notify({ type: 'positive', message: 'Imagen subida' })
  } catch (e) {
    notify({ type: 'negative', message: 'No se pudo subir: ' + (e as Error).message })
  } finally {
    uploadingImg.value = false
  }
}
function clearImage() {
  if (form.value.imagen_url && form.value.imagen_url !== originalImageUrl.value) {
    void removeProductImage(form.value.imagen_url)
  }
  form.value.imagen_url = ''
}
function onDialogHide() {
  if (form.value.imagen_url && form.value.imagen_url !== originalImageUrl.value) {
    void removeProductImage(form.value.imagen_url)
  }
}

/* ---------------- CRUD ---------------- */
function openNew() {
  editingId.value = null
  form.value = blankForm()
  originalImageUrl.value = ''
  tab.value = 'general'
  show.value = true
}

function openEdit(row: Product) {
  editingId.value = row.id
  form.value = {
    ...blankForm(),
    nombre: row.nombre,
    precio: row.precio,
    costo: row.costo,
    unidad_medida: row.unidad_medida,
    moneda: row.moneda ?? 'PEN',
    tipo_afectacion: row.tipo_afectacion,
    tipo_afectacion_compra: row.tipo_afectacion_compra ?? '10',
    incluye_igv: row.incluye_igv ?? true,
    codigo_sunat: row.codigo_sunat ?? '',
    descripcion: row.descripcion ?? '',
    sku: row.sku ?? '',
    imagen_url: row.imagen_url ?? '',
    detraccion: row.detraccion ?? false,
    restringir_cpe: row.restringir_cpe ?? false,
    canje_puntos: row.canje_puntos ?? false,
    activo: row.activo ?? true,
  }
  originalImageUrl.value = row.imagen_url ?? ''
  tab.value = 'general'
  show.value = true
}

async function toggleActivo(row: Product) {
  try {
    await updateProduct(row.id, { activo: row.activo === false })
    await load()
    notify({ type: 'positive', message: row.activo === false ? 'Servicio activado' : 'Servicio desactivado' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  }
}

function remove(row: Product) {
  $q.dialog({
    title: 'Eliminar servicio',
    message: `¿Eliminar "${row.nombre}"?`,
    cancel: true,
    persistent: true,
  }).onOk(async () => {
    try {
      const { softDeleted } = await deleteProduct(row.id, row.imagen_url)
      await load()
      notify({ type: 'positive', message: softDeleted ? 'Servicio desactivado (tenía historial)' : 'Servicio eliminado' })
    } catch (e) {
      notify({ type: 'negative', message: (e as Error).message })
    }
  })
}

/* ---------------- Acciones masivas ---------------- */
async function bulkSetActivo(activo: boolean) {
  const items = selected.value.filter((p) => (p.activo !== false) !== activo)
  if (!items.length) {
    notify({ type: 'info', message: activo ? 'Ya estaban activos' : 'Ya estaban inactivos' })
    return
  }
  try {
    const res = await Promise.allSettled(items.map((p) => updateProduct(p.id, { activo })))
    const fail = res.filter((r) => r.status === 'rejected').length
    notify(fail
      ? { type: 'warning', message: `${items.length - fail} aplicados · ${fail} fallaron` }
      : { type: 'positive', message: `${items.length} servicio(s) ${activo ? 'activados' : 'desactivados'}` })
  } finally {
    selected.value = []
    await load()
  }
}

// Copia de un servicio: sin sku ni foto (evita colisiones de código / imagen compartida).
function serviceCopyPayload(p: Product) {
  return {
    nombre: `${p.nombre} (copia)`,
    precio: p.precio,
    costo: p.costo,
    tipo: 'servicio' as const,
    controla_stock: false,
    unidad_medida: p.unidad_medida,
    moneda: p.moneda ?? 'PEN',
    tipo_afectacion: p.tipo_afectacion,
    tipo_afectacion_compra: p.tipo_afectacion_compra ?? null,
    incluye_igv: p.incluye_igv ?? true,
    codigo_sunat: p.codigo_sunat ?? null,
    descripcion: p.descripcion ?? null,
    sku: null,
    imagen_url: null,
    detraccion: p.detraccion ?? false,
    restringir_cpe: p.restringir_cpe ?? false,
    canje_puntos: p.canje_puntos ?? false,
    activo: p.activo ?? true,
  }
}

async function bulkDuplicate() {
  const items = [...selected.value]
  if (!items.length || !company.current) return
  const companyId = company.current.id
  try {
    const res = await Promise.allSettled(items.map((p) => createProduct(companyId, serviceCopyPayload(p))))
    const fail = res.filter((r) => r.status === 'rejected').length
    notify(fail
      ? { type: 'warning', message: `${items.length - fail} duplicado(s) · ${fail} fallaron` }
      : { type: 'positive', message: `${items.length} servicio(s) duplicado(s)` })
  } finally {
    selected.value = []
    await load()
  }
}

function bulkDelete() {
  const items = [...selected.value]
  if (!items.length) return
  $q.dialog({
    title: 'Eliminar servicios',
    message: `¿Eliminar ${items.length} servicio(s)? Los que tengan historial se desactivarán (baja lógica) para conservar la trazabilidad fiscal.`,
    cancel: true,
    persistent: true,
  }).onOk(async () => {
    try {
      const res = await Promise.allSettled(items.map((p) => deleteProduct(p.id, p.imagen_url)))
      const soft = res.filter((r) => r.status === 'fulfilled' && r.value.softDeleted).length
      const fail = res.filter((r) => r.status === 'rejected').length
      const del = items.length - soft - fail
      const parts: string[] = []
      if (del) parts.push(`${del} eliminado(s)`)
      if (soft) parts.push(`${soft} desactivado(s) (con historial)`)
      if (fail) parts.push(`${fail} fallaron`)
      notify({ type: fail ? 'warning' : 'positive', message: parts.join(' · ') || 'Sin cambios' })
    } finally {
      selected.value = []
      await load()
    }
  })
}

function onExport() {
  exportTableXls('servicios', columns, filteredRows.value)
}

async function load() {
  if (!company.current) return
  loading.value = !rows.value.length
  try {
    rows.value = (await listProducts(company.current.id)).filter((p) => p.tipo === 'servicio')
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
      costo: form.value.costo,
      tipo: 'servicio' as const,
      controla_stock: false,
      unidad_medida: form.value.unidad_medida,
      moneda: form.value.moneda,
      tipo_afectacion: form.value.tipo_afectacion,
      tipo_afectacion_compra: form.value.tipo_afectacion_compra || null,
      incluye_igv: form.value.incluye_igv,
      codigo_sunat: form.value.codigo_sunat || null,
      descripcion: form.value.descripcion || null,
      sku: form.value.sku || null,
      imagen_url: form.value.imagen_url || null,
      detraccion: form.value.detraccion,
      restringir_cpe: form.value.restringir_cpe,
      canje_puntos: form.value.canje_puntos,
      activo: form.value.activo,
    }
    if (editingId.value) await updateProduct(editingId.value, payload)
    else await createProduct(company.current.id, payload)
    if (originalImageUrl.value && originalImageUrl.value !== (form.value.imagen_url || null)) {
      await removeProductImage(originalImageUrl.value)
    }
    originalImageUrl.value = form.value.imagen_url || ''
    show.value = false
    await load()
    notify({ type: 'positive', message: editingId.value ? 'Servicio actualizado' : 'Servicio creado' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    saving.value = false
  }
}

/* ---------------- Historial (ventas · compras) ---------------- */
const histShow = ref(false)
const histLoading = ref(false)
const histTitle = ref('')
const histTab = ref<'ventas' | 'compras'>('ventas')
const histSales = ref<ProductSaleRow[]>([])
const histPurchases = ref<ProductPurchaseRow[]>([])

const histMoney = (v: unknown, row: { moneda?: string }) =>
  `${row.moneda === 'USD' ? 'US$' : 'S/'} ${Number(v).toFixed(2)}`

const salesCols: QTableColumn<ProductSaleRow>[] = [
  { name: 'fecha', label: 'Fecha', field: 'fecha', align: 'left', sortable: true, format: (v) => fmtFecha(v as string) },
  { name: 'comprobante', label: 'Comprobante', field: 'comprobante', align: 'left', sortable: true },
  { name: 'tipo', label: 'Tipo', field: 'tipoDoc', align: 'left' },
  { name: 'cantidad', label: 'Cant.', field: 'cantidad', align: 'right', sortable: true },
  { name: 'precio', label: 'P. unit.', field: 'precioUnitario', align: 'right', format: histMoney },
  { name: 'total', label: 'Total', field: 'total', align: 'right', sortable: true, format: histMoney },
  { name: 'estado', label: 'Estado', field: 'estado', align: 'left' },
]
const purchaseCols: QTableColumn<ProductPurchaseRow>[] = [
  { name: 'fecha', label: 'Fecha', field: 'fecha', align: 'left', sortable: true, format: (v) => fmtFecha(v as string) },
  { name: 'comprobante', label: 'Comprobante', field: 'comprobante', align: 'left' },
  { name: 'tipo', label: 'Tipo', field: 'tipoDoc', align: 'left' },
  { name: 'cantidad', label: 'Cant.', field: 'cantidad', align: 'right', sortable: true },
  { name: 'costo', label: 'Costo', field: 'costo', align: 'right', format: histMoney },
  { name: 'total', label: 'Total', field: 'total', align: 'right', sortable: true, format: histMoney },
]

const tipoDocLabels: Record<string, string> = {
  '01': 'Factura',
  '03': 'Boleta',
  '07': 'N. crédito',
  '08': 'N. débito',
}
function tipoDocLabel(t: string): string {
  return tipoDocLabels[t] ?? t
}
function estadoMeta(e: string): { label: string; cls: string } {
  switch (e) {
    case 'aceptado':
      return { label: 'Aceptado', cls: 'k-pill--ok' }
    case 'rechazado':
      return { label: 'Rechazado', cls: 'k-pill--err' }
    case 'anulado':
      return { label: 'Anulado', cls: 'k-pill--err' }
    default:
      return { label: 'Pendiente', cls: 'k-pill--muted' }
  }
}

async function openHistorial(p: Product) {
  histTitle.value = p.nombre
  histTab.value = 'ventas'
  histSales.value = []
  histPurchases.value = []
  histShow.value = true
  if (!company.current) return
  histLoading.value = true
  try {
    const [sales, purchases] = await Promise.allSettled([
      listProductSales(company.current.id, p.id),
      listProductPurchases(company.current.id, p.id),
    ])
    if (sales.status === 'fulfilled') histSales.value = sales.value
    if (purchases.status === 'fulfilled') histPurchases.value = purchases.value
    const errRes = sales.status === 'rejected' ? sales.reason
      : purchases.status === 'rejected' ? purchases.reason : null
    if (errRes) notify({ type: 'negative', message: (errRes as Error).message })
  } finally {
    histLoading.value = false
  }
}

onMounted(load)
</script>

<style scoped>
/* La tabla es ancha: no partir celdas → scroll horizontal. */
.k-prod-table :deep(th),
.k-prod-table :deep(td) {
  white-space: nowrap;
}

.k-id {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  color: var(--k-muted);
}
.k-chip {
  display: inline-block;
  padding: 2px 10px;
  border-radius: 999px;
  background: var(--k-surface-2);
  color: var(--k-muted);
  font-size: 11.5px;
  font-weight: 600;
}
.k-prod-img {
  width: 38px;
  height: 38px;
  border-radius: 9px;
  object-fit: cover;
  background: var(--k-surface-2);
}
.k-prod-name {
  font-weight: 600;
  font-size: 13.5px;
}
.k-prod-sku {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 10.5px;
  color: var(--k-muted);
}
.k-desc {
  max-width: 260px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12.5px;
  color: var(--k-muted);
}
.k-ico-btn {
  color: var(--q-primary);
  background: color-mix(in srgb, var(--q-primary) 12%, transparent);
  transition: background 0.15s ease;
}
.k-ico-btn:hover {
  background: color-mix(in srgb, var(--q-primary) 22%, transparent);
}
.k-ico-btn :deep(.q-icon) {
  font-size: 19px;
}
.k-act-td {
  white-space: nowrap;
}
.k-act-btn {
  color: var(--k-muted);
}
.k-act-btn:hover {
  color: var(--k-text);
}
.k-checks :deep(.q-checkbox__label) {
  font-size: 13px;
}

/* Píldoras */
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
.k-pill--muted {
  color: var(--k-muted);
  background: color-mix(in srgb, var(--k-muted) 18%, transparent);
}
.k-pill--err {
  color: var(--q-negative);
  background: color-mix(in srgb, var(--q-negative) 15%, transparent);
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

/* Imagen del formulario */
.k-img-col {
  display: flex;
  flex-direction: column;
  gap: 10px;
  max-width: 170px;
}
.k-img-preview-wrap {
  width: 100%;
  aspect-ratio: 1;
  border-radius: var(--k-radius-sm);
  background: var(--k-surface-2);
  overflow: hidden;
  display: flex;
  align-items: center;
  justify-content: center;
}
.k-img-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  color: var(--k-muted);
  font-size: 12px;
}
.k-img-preview {
  width: 100%;
  height: 100%;
  object-fit: contain;
}
.k-img-actions {
  display: flex;
  gap: 8px;
}
.k-upload-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  flex: 1;
  border: none;
  background: var(--k-surface-2);
  color: var(--k-text);
  font-family: inherit;
  font-size: 13.5px;
  font-weight: 600;
  padding: 12px;
  border-radius: var(--k-radius-sm);
  cursor: pointer;
  transition: box-shadow 0.15s ease, background 0.15s ease, color 0.15s ease;
}
.k-upload-btn:hover {
  box-shadow: 0 0 0 1px var(--k-border-hover);
}
.k-upload-btn:disabled {
  opacity: 0.6;
  cursor: default;
}
.k-upload-btn--danger {
  color: var(--k-muted);
}
.k-upload-btn--danger:hover {
  background: color-mix(in srgb, var(--q-negative) 15%, transparent);
  color: var(--q-negative);
  box-shadow: none;
}

/* Historial */
.k-hist-panel {
  padding: 12px;
}
.k-hist-table {
  max-height: 56vh;
}
.k-hist-table :deep(thead th) {
  padding-top: 10px;
  padding-bottom: 10px;
}
.k-hist-table :deep(tbody td) {
  height: 44px;
  padding-top: 10px;
  padding-bottom: 10px;
  border-bottom: 1px solid var(--k-border);
}
.k-hist-table :deep(tbody tr:nth-child(even) td) {
  background: color-mix(in srgb, var(--k-text) 4%, transparent);
}
.k-hist-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  padding: 28px 16px;
  width: 100%;
}
</style>
