<template>
  <q-page class="q-pa-md">
    <KModuleHeader
      title="Marcas"
      subtitle="Gestiona las marcas de tus productos"
      :refresh-fn="load"
      new-label="Nueva"
      show-import
      show-export
      @new="openNew"
      @export="onExport"
    />

    <!-- Filtros ⇄ acciones masivas: se reemplazan EN EL MISMO LUGAR (sin generar
         alto extra) con la transición de cubo vertical. -->
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
          <span class="k-bulk-count">{{ selected.length }} seleccionada(s)</span>
          <q-space />
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
              v-model="imagenFilter"
              outlined
              dense
              emit-value
              map-options
              :options="imagenFilterOptions"
              label="Imagen"
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
      <!-- ID (uuid corto) -->
      <template #body-cell-id="props">
        <q-td :props="props">
          <span class="k-id">
            {{ shortId(props.row.id) }}
            <q-tooltip>{{ props.row.id }}</q-tooltip>
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
            class="k-cat-img"
            alt=""
            loading="lazy"
            @error="onImgError"
          >
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

      <!-- Estado (activa / inactiva) -->
      <template #body-cell-estado="props">
        <q-td :props="props">
          <span
            class="k-pill"
            :class="props.row.activo !== false ? 'k-pill--ok' : 'k-pill--muted'"
          >
            <i class="k-dot" />{{ props.row.activo !== false ? 'Activa' : 'Inactiva' }}
          </span>
        </q-td>
      </template>

      <!-- Acciones (3 puntitos → menú Editar / Activar-Desactivar / Eliminar) -->
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
                style="min-width: 168px"
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
      <template #loading>
        <KTableSkeleton />
      </template>
    </q-table>

    <q-dialog
      v-model="show"
      :maximized="$q.screen.lt.sm"
      @hide="onDialogHide"
    >
      <q-card class="k-dialog-md">
        <q-card-section class="k-modal-head">
          <div class="text-h6">
            {{ editingId ? 'Editar marca' : 'Nueva marca' }}
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
        <q-card-section class="row q-col-gutter-lg">
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

          <!-- Campos -->
          <div class="col-12 col-sm-8">
            <div class="row q-col-gutter-md">
              <q-input
                v-model="form.nombre"
                class="col-12"
                outlined
                label="Nombre *"
                autofocus
                :rules="nameRules"
                lazy-rules="ondemand"
                hide-bottom-space
              />
              <q-input
                v-model="form.descripcion"
                class="col-12"
                outlined
                type="textarea"
                autogrow
                label="Descripción"
                input-style="min-height: 92px"
              />
            </div>
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
            unelevated
            :label="editingId ? 'Guardar cambios' : 'Crear marca'"
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
import { useRealtime } from '@/lib/realtime'
import KTableSkeleton from '@/components/KTableSkeleton.vue'
import KModuleHeader from '@/components/KModuleHeader.vue'
import { exportTableXls } from '@/lib/exportTable'
import {
  listBrands,
  createBrand,
  updateBrand,
  deleteBrand,
  setBrandActivo,
} from '@/modules/inventory/inventory.api'
import type { Brand } from '@/types'
// La imagen se guarda en el mismo bucket público de imágenes (`productos`).
import { uploadProductImage, removeProductImage } from '@/modules/products/products.api'
import { validate, nameRules } from '@/lib/validation'
import { notify } from '@/lib/toast'

const $q = useQuasar()
const company = useCompanyStore()
// Realtime: refresca al crear/editar/eliminar marcas.
useRealtime('brands', () => company.current?.id, () => { void load() })
const rows = ref<Brand[]>([])
const loading = ref(false)
const show = ref(false)
const saving = ref(false)
const editingId = ref<string | null>(null)
const form = ref({ nombre: '', descripcion: '', imagen_url: '', activo: true })
// Imagen que tenía la marca al abrir el form: si cambia/se quita, se borra del storage.
const originalImageUrl = ref('')
const uploadingImg = ref(false)
const selected = ref<Brand[]>([])

// Filtros: búsqueda (por nombre o descripción) + presencia de imagen.
const search = ref('')
const searchField = ref<'nombre' | 'descripcion'>('nombre')
const imagenFilter = ref<'all' | 'con' | 'sin'>('all')

const searchFieldOptions = [
  { label: 'Nombre', value: 'nombre' },
  { label: 'Descripción', value: 'descripcion' },
]
const imagenFilterOptions = [
  { label: 'Todas', value: 'all' },
  { label: 'Con imagen', value: 'con' },
  { label: 'Sin imagen', value: 'sin' },
]
const searchFieldLabel = computed(
  () => searchFieldOptions.find((o) => o.value === searchField.value)?.label ?? 'Nombre',
)

const filteredRows = computed(() => {
  // La "X" de q-input clearable emite null; sin guarda, .trim() crashea la tabla.
  const q = (search.value ?? '').trim().toLowerCase()
  return rows.value.filter((b) => {
    if (imagenFilter.value === 'con' && !b.imagen_url) return false
    if (imagenFilter.value === 'sin' && b.imagen_url) return false
    if (!q) return true
    const hay = searchField.value === 'descripcion' ? (b.descripcion ?? '') : b.nombre
    return hay.toLowerCase().includes(q)
  })
})

const columns: QTableColumn<Brand>[] = [
  { name: 'id', label: 'ID', field: 'id', align: 'left' },
  { name: 'imagen', label: 'Imagen', field: 'imagen_url', align: 'center' },
  { name: 'nombre', label: 'Nombre', field: 'nombre', align: 'left', sortable: true },
  { name: 'descripcion', label: 'Descripción', field: (r) => r.descripcion ?? '', align: 'left' },
  { name: 'estado', label: 'Estado', field: (r) => (r.activo === false ? 0 : 1), format: (v) => (v ? 'Activa' : 'Inactiva'), align: 'left', sortable: true },
  { name: 'acciones', label: '', field: 'id', align: 'right' },
]

function shortId(id: string): string {
  return id.slice(0, 8)
}
function onImgError(e: Event) {
  const img = e.target as HTMLImageElement
  if (!img.src.endsWith('/product-placeholder.svg')) img.src = '/product-placeholder.svg'
}

/* ---------------- Imagen ---------------- */
const fileInput = ref<HTMLInputElement | null>(null)
function pickFile() {
  fileInput.value?.click()
}
function onFileChange(e: Event) {
  const input = e.target as HTMLInputElement
  void onPickImage(input.files?.[0] ?? null)
  input.value = '' // permite volver a elegir el mismo archivo
}
async function onPickImage(file: File | null) {
  if (!file || !company.current) return
  uploadingImg.value = true
  try {
    const prev = form.value.imagen_url
    const url = await uploadProductImage(company.current.id, file)
    form.value.imagen_url = url
    // Limpia la subida anterior de ESTA sesión (no la del registro) para no dejar huérfanos.
    if (prev && prev !== originalImageUrl.value && prev !== url) void removeProductImage(prev)
    notify({ type: 'positive', message: 'Imagen subida' })
  } catch (e) {
    notify({ type: 'negative', message: 'No se pudo subir: ' + (e as Error).message })
  } finally {
    uploadingImg.value = false
  }
}

// Quita la imagen del form; si era una subida de esta sesión (no la guardada), la borra del storage.
function clearImage() {
  if (form.value.imagen_url && form.value.imagen_url !== originalImageUrl.value) {
    void removeProductImage(form.value.imagen_url)
  }
  form.value.imagen_url = ''
}

// Al cerrar el diálogo sin guardar, borra la imagen subida en esta sesión que no se persistió.
function onDialogHide() {
  if (form.value.imagen_url && form.value.imagen_url !== originalImageUrl.value) {
    void removeProductImage(form.value.imagen_url)
  }
}

function openNew() {
  editingId.value = null
  form.value = { nombre: '', descripcion: '', imagen_url: '', activo: true }
  originalImageUrl.value = ''
  show.value = true
}

function openEdit(row: Brand) {
  editingId.value = row.id
  form.value = {
    nombre: row.nombre,
    descripcion: row.descripcion ?? '',
    imagen_url: row.imagen_url ?? '',
    activo: row.activo ?? true,
  }
  originalImageUrl.value = row.imagen_url ?? ''
  show.value = true
}

// Activar/desactivar desde el menú de la tabla (baja lógica, sin abrir el form).
async function toggleActivo(row: Brand) {
  const nuevo = row.activo === false
  try {
    await setBrandActivo(row.id, nuevo)
    await load()
    notify({ type: 'positive', message: nuevo ? 'Marca activada' : 'Marca desactivada' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  }
}

function remove(row: Brand) {
  $q.dialog({
    title: 'Eliminar marca',
    message: `¿Eliminar a "${row.nombre}"?`,
    cancel: true,
    persistent: true,
  }).onOk(async () => {
    try {
      await deleteBrand(row.id)
      if (row.imagen_url) await removeProductImage(row.imagen_url)
      await load()
      notify({ type: 'positive', message: 'Marca eliminada' })
    } catch (e) {
      notify({ type: 'negative', message: (e as Error).message })
    }
  })
}

function bulkDelete() {
  const items = [...selected.value]
  if (!items.length) return
  $q.dialog({
    title: 'Eliminar marcas',
    message: `¿Eliminar ${items.length} marca(s)? No se puede deshacer.`,
    cancel: true,
    persistent: true,
  }).onOk(async () => {
    try {
      // allSettled: un fallo parcial (p. ej. RLS) no deja la UI desincronizada.
      const res = await Promise.allSettled(items.map((b) => deleteBrand(b.id)))
      const fail = res.filter((r) => r.status === 'rejected').length
      // Limpia del storage las imágenes de las que sí se borraron (evita huérfanos).
      const toClean = items.filter((b, i) => res[i].status === 'fulfilled' && b.imagen_url)
      await Promise.allSettled(toClean.map((b) => removeProductImage(b.imagen_url)))
      notify(fail
        ? { type: 'warning', message: `${items.length - fail} eliminada(s) · ${fail} fallaron` }
        : { type: 'positive', message: `${items.length} marca(s) eliminada(s)` })
    } finally {
      selected.value = []
      await load()
    }
  })
}

function onExport() {
  exportTableXls('marcas', columns, filteredRows.value)
}

async function load() {
  if (!company.current) return
  loading.value = !rows.value.length
  try {
    rows.value = await listBrands(company.current.id)
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
  ])
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  saving.value = true
  try {
    const payload = {
      nombre: form.value.nombre.trim(),
      descripcion: form.value.descripcion || null,
      imagen_url: form.value.imagen_url || null,
      activo: form.value.activo,
    }
    if (editingId.value) await updateBrand(editingId.value, payload)
    else await createBrand(company.current.id, payload)
    // Si la imagen cambió o se quitó, borra la anterior del storage (evita huérfanos).
    if (originalImageUrl.value && originalImageUrl.value !== (form.value.imagen_url || null)) {
      await removeProductImage(originalImageUrl.value)
    }
    originalImageUrl.value = form.value.imagen_url || ''
    show.value = false
    await load()
    notify({ type: 'positive', message: editingId.value ? 'Marca actualizada' : 'Marca creada' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    saving.value = false
  }
}

onMounted(load)
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

/* Filtros ⇄ acciones masivas comparten el mismo lugar: el que SALE va absoluto
   (no empuja la tabla) y el que ENTRA define el alto. Giro de cubo vertical (eje X),
   sin fade — igual que en Productos. */
/* Animación filtros ⇄ acciones masivas: definida GLOBAL en theme.css (.k-toolbar-swap / .k-swap-*). */

/* Botón de acciones (3 puntitos) */
.k-act-btn {
  color: var(--k-muted);
}
.k-act-btn:hover {
  color: var(--k-text);
}

/* Píldora de estado (activa / inactiva) */
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

/* ID corto en monoespaciada */
.k-id {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  color: var(--k-muted);
}

/* Miniatura de la marca */
.k-cat-img {
  width: 38px;
  height: 38px;
  border-radius: 9px;
  object-fit: cover;
  background: var(--k-surface-2);
  vertical-align: middle;
}

/* Descripción recortada con elipsis */
.k-desc {
  max-width: 320px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12.5px;
  color: var(--k-muted);
}

/* Columna de imagen del formulario */
.k-img-col {
  display: flex;
  flex-direction: column;
  gap: 10px;
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
</style>
