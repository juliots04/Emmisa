<template>
  <q-page class="q-pa-md">
    <KModuleHeader
      title="Productos"
      subtitle="Catálogo de productos de tu empresa"
      :refresh-fn="load"
      new-label="Nuevo"
      show-import
      show-export
      @new="openNew"
      @export="onExport"
    />

    <!-- Filtros ⇄ acciones masivas: se reemplazan EN EL MISMO LUGAR (sin generar
         alto extra) con una transición líquida (el que sale va absoluto). -->
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
              v-model="stockFilter"
              outlined
              dense
              emit-value
              map-options
              :options="stockFilterOptions"
              label="Stock"
            />
          </div>
          <div class="col-6 col-md k-fcol">
            <q-select
              v-model="marcaFilter"
              outlined
              dense
              emit-value
              map-options
              :options="marcaFilterOptions"
              label="Marca"
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
      <!-- ID: número de fila (el uuid real va en el tooltip) -->
      <template #body-cell-id="props">
        <q-td :props="props">
          <span class="k-id">
            {{ props.rowIndex + 1 }}
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

      <!-- Unidad de medida (código SUNAT cat. 03) -->
      <template #body-cell-unidad="props">
        <q-td :props="props">
          <span class="k-chip">
            {{ props.row.unidad_medida || 'NIU' }}
            <q-tooltip>{{ unidadNombre(props.row.unidad_medida) }}</q-tooltip>
          </span>
        </q-td>
      </template>

      <!-- Stock por datos extra (desglose por almacén) -->
      <template #body-cell-stock_extra="props">
        <q-td
          :props="props"
          class="text-center"
        >
          <q-btn
            flat
            round
            dense
            class="k-ico-btn"
            icon="pie_chart"
          >
            <q-tooltip>Stock por almacén</q-tooltip>
            <q-menu>
              <div class="k-stock-pop">
                <div class="k-stock-pop-title">
                  Stock por almacén
                </div>
                <template v-if="stockDetail(props.row).length">
                  <div
                    v-for="d in stockDetail(props.row)"
                    :key="d.almacen"
                    class="k-stock-pop-row"
                  >
                    <span>{{ d.almacen }}</span>
                    <span class="k-stock-pop-qty">{{ d.cantidad }}</span>
                  </div>
                </template>
                <div
                  v-else
                  class="text-muted"
                >
                  Sin existencias registradas
                </div>
              </div>
            </q-menu>
          </q-btn>
        </q-td>
      </template>

      <!-- Historial (kardex del producto) -->
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
            <q-tooltip>Historial: stock, ventas y compras</q-tooltip>
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

      <!-- Stock (actual + mínimo) · botón que abre el desglose por ubicación -->
      <template #body-cell-stock="props">
        <q-td
          :props="props"
          class="text-center"
        >
          <q-btn
            v-if="stockLabel(props.row) !== null"
            flat
            round
            dense
            class="k-ico-btn"
            icon="bar_chart"
            @click="openStock(props.row)"
          >
            <q-tooltip>Ver stock por ubicación</q-tooltip>
          </q-btn>
          <span
            v-else
            class="text-muted"
          >—</span>
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

      <!-- Acciones (3 puntitos → abre el modal de edición) -->
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
                style="min-width: 184px"
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
                  @click="duplicateProduct(props.row)"
                >
                  <q-item-section avatar>
                    <q-icon
                      name="content_copy"
                      size="18px"
                    />
                  </q-item-section>
                  <q-item-section>Duplicar</q-item-section>
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
                  @click="confirmDelete(props.row)"
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
            name="inventory_2"
            size="42px"
            class="k-state-icon"
          />
          <div class="text-subtitle1 q-mt-sm">
            {{ rows.length ? 'Sin coincidencias' : 'Aún no tienes productos' }}
          </div>
          <div class="text-caption text-muted">
            {{ rows.length ? 'Ajusta la búsqueda o los filtros.' : 'Crea tu primer producto con “Nuevo producto”.' }}
          </div>
        </div>
      </template>

      <template #loading>
        <KTableSkeleton />
      </template>
    </q-table>

    <!-- Crear / Editar -->
    <q-dialog
      v-model="show"
      :maximized="$q.screen.lt.sm"
    >
      <q-card
        class="k-prod-modal k-dialog-lg"
      >
        <q-card-section class="k-modal-head">
          <div class="text-h6">
            {{ editingId ? 'Editar producto' : 'Nuevo producto' }}
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
            name="basico"
            label="Básico"
          />
          <q-tab
            name="general"
            label="General"
          />
          <q-tab
            name="atributos"
            label="Atributos"
          />
          <q-tab
            name="compra"
            label="Compra"
          />
          <q-tab
            name="almacenes"
            label="Almacenes"
          />
        </q-tabs>
        <q-separator />

        <q-tab-panels
          v-model="tab"
          animated
        >
          <!-- BÁSICO -->
          <q-tab-panel name="basico">
            <div class="row q-col-gutter-md items-start">
              <!-- Fila 1: Nombre · Precio · Unidad -->
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
                :label="`Precio Unitario (${form.incluye_igv ? 'con' : 'sin'} IGV) *`"
                :rules="priceRules"
                lazy-rules="ondemand"
                hide-bottom-space
              />
              <q-select
                v-model="form.unidad_medida"
                class="col-6 col-sm-3"
                outlined
                :options="unidadOptions"
                emit-value
                map-options
                label="Unidad"
              />
              <!-- Fila 2: Descripción · Código interno · Incluye IGV -->
              <q-input
                v-model="form.descripcion"
                class="col-12 col-sm-6"
                outlined
                label="Descripción"
              />
              <q-input
                v-model="form.sku"
                class="col-12 col-sm-3"
                outlined
                label="Código interno"
              />
              <div class="col-12 col-sm-3 self-center">
                <q-toggle
                  v-model="form.incluye_igv"
                  :disable="form.tipo_afectacion !== '10'"
                  label="Incluye IGV"
                />
              </div>
            </div>
          </q-tab-panel>

          <!-- GENERAL -->
          <q-tab-panel name="general">
            <div class="row q-col-gutter-md">
              <!-- Fila 1: TODOS los dropdowns → Moneda · Tipo de afectación · Almacén · ¿Maneja series? -->
              <q-select
                v-model="form.moneda"
                class="col-12 col-sm-3"
                outlined
                :options="['PEN', 'USD']"
                label="Moneda"
              />
              <q-select
                v-model="form.tipo_afectacion"
                class="col-12 col-sm-3"
                outlined
                :options="afectacionOptions"
                emit-value
                map-options
                label="Tipo de afectación"
              />
              <!-- Almacén: solo al crear -->
              <template v-if="!editingId">
                <q-select
                  v-if="warehouses.length"
                  v-model="form.warehouse_id"
                  class="col-12 col-sm-3"
                  outlined
                  clearable
                  :options="warehouseOptions"
                  emit-value
                  map-options
                  label="Almacén"
                />
                <div
                  v-else
                  class="col-12 col-sm-3 self-center text-caption text-muted"
                >
                  Aún no hay almacenes (créalos en Inventario).
                </div>
              </template>
              <q-select
                v-model="form.maneja_series"
                class="col-12 col-sm-3"
                outlined
                :options="siNoOptions"
                emit-value
                map-options
                label="¿Maneja series?"
              />

              <!-- Al editar: stock actual (se mueve por Inventario) -->
              <div
                v-if="editingId"
                class="col-12"
              >
                <div class="k-stock-info">
                  <div class="k-field-cap">
                    Stock actual
                  </div>
                  <span
                    class="k-stock-tag"
                    :class="`k-stock-tag--${stockActualTone}`"
                  >
                    <i class="k-stock-dot" />{{ stockActualLabel }}
                  </span>
                  <q-space />
                  <q-btn
                    flat
                    dense
                    no-caps
                    color="primary"
                    icon="tune"
                    label="Ajustar en Inventario"
                    :to="{ name: 'inventory' }"
                  />
                </div>
              </div>

              <!-- Modelo · Código de barra · Stock inicial (crear) · Stock mínimo -->
              <q-input
                v-model="form.modelo"
                class="col-12 col-sm-4"
                outlined
                label="Modelo"
              />
              <q-input
                v-model="form.barcode"
                class="col-12 col-sm-4"
                outlined
                label="Código de barra"
                :rules="barcodeRules"
                lazy-rules="ondemand"
              />
              <q-input
                v-if="!editingId"
                v-model.number="form.stock_inicial"
                class="col-6 col-sm-4"
                outlined
                type="number"
                label="Stock inicial"
                :rules="stockInicialRules"
                lazy-rules="ondemand"
              />
              <q-input
                v-model.number="form.stock_minimo"
                class="col-6 col-sm-4"
                outlined
                type="number"
                label="Stock mínimo"
                :rules="stockMinRules"
                lazy-rules="ondemand"
              />

              <q-input
                v-model="form.codigo_sunat"
                class="col-12 col-sm-4"
                outlined
                label="Código SUNAT"
                :rules="codeRules"
                lazy-rules="ondemand"
              />
              <q-input
                v-model="form.linea_producto"
                class="col-12 col-sm-4"
                outlined
                label="Línea de producto"
              />
              <q-input
                v-model="form.registro_sanitario"
                class="col-12 col-sm-4"
                outlined
                label="Registro sanitario"
              />
              <q-input
                v-model="form.codigo_digemid"
                class="col-12 col-sm-4"
                outlined
                label="Código DIGEMID"
              />
              <q-input
                v-model="form.codigo_fabrica"
                class="col-12 col-sm-4"
                outlined
                label="Código de fábrica"
              />
              <q-input
                v-model="form.fecha_vencimiento"
                class="col-12 col-sm-4"
                outlined
                type="date"
                label="Fecha de vencimiento"
                stack-label
              />

              <!-- Opciones del producto / comprobante -->
              <div class="col-12">
                <div class="row q-col-gutter-sm k-checks">
                  <q-checkbox
                    v-model="form.icbper"
                    class="col-12 col-sm-4"
                    label="Impuesto a la bolsa (ICBPER)"
                  />
                  <q-checkbox
                    v-model="form.percepcion"
                    class="col-12 col-sm-4"
                    label="Incluye percepción"
                  />
                  <q-checkbox
                    v-model="form.maneja_lotes"
                    class="col-12 col-sm-4"
                    label="¿Maneja lotes?"
                  />
                  <q-checkbox
                    v-model="form.incluye_isc"
                    class="col-12 col-sm-4"
                    label="Incluye ISC"
                  />
                  <q-checkbox
                    v-model="form.detraccion"
                    class="col-12 col-sm-4"
                    label="Sujeto a detracción"
                  />
                  <q-checkbox
                    v-model="form.restringir_cpe"
                    class="col-12 col-sm-4"
                    label="Restringir venta en CPE"
                  />
                  <q-checkbox
                    v-model="form.canje_puntos"
                    class="col-12 col-sm-4"
                    label="¿Canjeable por puntos?"
                  />
                  <q-checkbox
                    v-model="form.controla_stock"
                    class="col-12 col-sm-4"
                    label="Controla stock"
                  />
                </div>
                <div
                  v-if="form.maneja_series"
                  class="text-caption text-muted q-mt-sm"
                >
                  Registra los números de serie en Productos/Servicios → Series.
                </div>
              </div>
            </div>
          </q-tab-panel>

          <!-- ATRIBUTOS: imagen + categoría + marca (una sola fila) -->
          <q-tab-panel name="atributos">
            <div class="row q-col-gutter-md items-start">
              <!-- Imagen -->
              <div class="col-12 col-sm-auto k-img-col">
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
                    @click="form.imagen_url = ''"
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
                  class="hidden"
                  @change="onFileChange"
                >
              </div>

              <!-- Categoría · Marca (misma fila que la foto) -->
              <q-select
                v-model="form.category_id"
                class="col-12 col-sm"
                outlined
                clearable
                emit-value
                map-options
                :options="categoryOptions"
                label="Categoría"
              />
              <q-select
                v-model="form.brand_id"
                class="col-12 col-sm"
                outlined
                clearable
                emit-value
                map-options
                :options="brandOptions"
                label="Marca"
              />
              <div class="col-12 k-checks">
                <q-checkbox
                  v-model="form.activo"
                  label="Activo"
                />
              </div>
            </div>
          </q-tab-panel>

          <!-- ALMACENES: precios por almacén -->
          <q-tab-panel name="almacenes">
            <div class="k-field-cap q-mb-sm">
              Precios por almacén
            </div>
            <div
              v-if="warehouses.length"
              class="k-wh-prices"
            >
              <div
                v-for="w in warehouses"
                :key="w.id"
                class="k-wh-row"
              >
                <span class="k-wh-name">{{ w.nombre }}</span>
                <q-input
                  v-model.number="form.precios_almacen[w.id]"
                  class="k-wh-input"
                  outlined
                  dense
                  type="number"
                  min="0"
                  placeholder="Precio"
                />
              </div>
            </div>
            <div
              v-else
              class="text-caption text-muted"
            >
              Aún no hay almacenes. Créalos en Inventario.
            </div>
          </q-tab-panel>

          <!-- COMPRA -->
          <q-tab-panel name="compra">
            <div class="row q-col-gutter-md">
              <q-select
                v-model="form.tipo_afectacion_compra"
                class="col-12 col-sm-8"
                outlined
                :options="afectacionOptions"
                emit-value
                map-options
                label="Tipo de afectación"
              />
              <q-input
                v-model.number="form.costo"
                class="col-12 col-sm-4"
                outlined
                type="number"
                label="Precio Unitario (con IGV)"
                :rules="costRules"
                lazy-rules="ondemand"
              />
              <q-input
                v-model.number="form.porcentaje_ganancia"
                class="col-12 col-sm-5"
                outlined
                type="number"
                label="Porcentaje de ganancia (%)"
                :disable="!form.aplica_ganancia"
                :rules="gananciaRules"
                lazy-rules="ondemand"
              />
              <div class="col-12">
                <div class="row q-col-gutter-sm k-checks">
                  <q-checkbox
                    v-model="form.aplica_ganancia"
                    class="col-12 col-sm-4"
                    label="Aplica ganancia"
                  />
                  <q-checkbox
                    v-model="form.incluye_isc"
                    class="col-12 col-sm-4"
                    label="Incluye ISC"
                  />
                </div>
                <div
                  v-if="form.aplica_ganancia && form.costo > 0"
                  class="text-caption text-muted q-mt-xs"
                >
                  Precio sugerido de venta: {{ simbolo }} {{ precioSugerido.toFixed(2) }}
                  (costo {{ simbolo }} {{ Number(form.costo).toFixed(2) }} + {{ Number(form.porcentaje_ganancia) || 0 }}%)
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
            :label="editingId ? 'Guardar cambios' : 'Crear producto'"
            :loading="saving"
            @click="save"
          />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <!-- Historial del producto: stock actual · últimas ventas · últimas compras -->
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
            name="stock"
            label="Ver stock"
          />
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
          <!-- VER STOCK (por almacén) -->
          <q-tab-panel
            name="stock"
            class="k-hist-panel"
          >
            <q-table
              :rows="histStockRows"
              :columns="stockCols"
              row-key="almacen"
              flat
              bordered
              dense
              hide-pagination
              :rows-per-page-options="[0]"
              class="k-hist-table"
            >
              <template #body-cell-cantidad="props">
                <q-td
                  :props="props"
                  class="text-right"
                >
                  <span
                    class="k-stock"
                    :class="`k-stock--${props.value <= 0 ? 'out' : 'ok'}`"
                  >{{ props.value }}</span>
                </q-td>
              </template>
              <!-- Series disponibles del producto (a nivel de producto, no de almacén) -->
              <template #body-cell-series="props">
                <q-td :props="props">
                  <span
                    v-if="histSerials.length"
                    class="k-chip"
                  >
                    {{ histSerials.length }} {{ histSerials.length === 1 ? 'serie' : 'series' }}
                    <q-tooltip max-width="320px">{{ histSerials.join(', ') }}</q-tooltip>
                  </span>
                  <span
                    v-else
                    class="text-muted"
                  >—</span>
                </q-td>
              </template>
              <template #no-data>
                <div class="k-hist-empty text-muted">
                  <q-icon
                    name="inventory_2"
                    size="30px"
                    class="k-state-icon"
                  />
                  <span>Sin existencias registradas</span>
                </div>
              </template>
            </q-table>
          </q-tab-panel>

          <!-- ÚLTIMAS VENTAS -->
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
                  <span>Sin ventas de este producto</span>
                </div>
              </template>
            </q-table>
          </q-tab-panel>

          <!-- ÚLTIMAS COMPRAS -->
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
                  <span>Sin compras de este producto</span>
                </div>
              </template>
            </q-table>
          </q-tab-panel>
        </q-tab-panels>
      </q-card>
    </q-dialog>

    <!-- Stock de producto: desglose por ubicación (abre desde la columna Stock) -->
    <q-dialog
      v-model="stockShow"
      :maximized="$q.screen.lt.sm"
    >
      <q-card class="k-dialog-md">
        <q-card-section class="k-modal-head">
          <div>
            <div class="text-h6">
              Stock de producto
            </div>
            <div class="text-caption text-muted">
              {{ stockTitle }}
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
        <q-separator />
        <q-card-section class="k-hist-panel">
          <q-table
            :rows="stockModalRows"
            :columns="stockModalCols"
            row-key="almacen"
            flat
            bordered
            dense
            hide-pagination
            :rows-per-page-options="[0]"
            class="k-hist-table"
          >
            <template #body-cell-cantidad="props">
              <q-td
                :props="props"
                class="text-right"
              >
                <span
                  class="k-stock"
                  :class="`k-stock--${props.value <= 0 ? 'out' : 'ok'}`"
                >{{ props.value }}</span>
              </q-td>
            </template>
            <template #no-data>
              <div class="k-hist-empty text-muted">
                <q-icon
                  name="inventory_2"
                  size="30px"
                  class="k-state-icon"
                />
                <span>Sin existencias registradas</span>
              </div>
            </template>
          </q-table>
        </q-card-section>
        <q-separator />
        <q-card-actions align="right">
          <q-btn
            v-close-popup
            flat
            label="Cerrar"
          />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useQuasar, type QTableColumn } from 'quasar'
import { useCompanyStore } from '@/stores/company'
import { useRealtime } from '@/lib/realtime'
import {
  listProducts,
  createProduct,
  updateProduct,
  deleteProduct,
  uploadProductImage,
  removeProductImage,
  listAvailableSerials,
} from '@/modules/products/products.api'
import { listWarehouses, registerMovement, listStock, listCategories, listBrands, type Category } from '@/modules/inventory/inventory.api'
import { listProductSales, type ProductSaleRow } from '@/modules/documents/documents.api'
import { listProductPurchases, type ProductPurchaseRow } from '@/modules/purchases/purchases.api'
import type { Brand } from '@/types'
import { fmtFecha } from '@/lib/date'
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
import KTableSkeleton from '@/components/KTableSkeleton.vue'
import KModuleHeader from '@/components/KModuleHeader.vue'
import { exportTableXls } from '@/lib/exportTable'

const company = useCompanyStore()
// Realtime: refresca catálogo y stock. Ojo: la tabla `stock` no tiene company_id
// (se aísla por join), así que el stock se refresca vía inventory_movements y ventas.
useRealtime('products', () => company.current?.id, () => { void load() })
useRealtime('inventory_movements', () => company.current?.id, () => { void refreshStock() })
useRealtime('documents', () => company.current?.id, () => { void refreshStock() })
const $q = useQuasar()

const rows = ref<Product[]>([])
const loading = ref(false)
const show = ref(false)
const saving = ref(false)
const tab = ref('basico')
const editingId = ref<string | null>(null)
// Imagen que tenía el producto al abrir el form: si cambia o se quita, se borra del
// storage tras guardar (evita objetos huérfanos públicos acumulándose en el bucket).
const originalImageUrl = ref('')
// updated_at del producto al abrir el form: control optimista para no pisar cambios ajenos.
const loadedUpdatedAt = ref<string | null>(null)
const warehouses = ref<{ id: string; nombre: string }[]>([])
const categories = ref<Category[]>([])
const categoryOptions = computed(() => categories.value.map((c) => ({ label: c.nombre, value: c.id })))
const brands = ref<Brand[]>([])
const brandOptions = computed(() => brands.value.map((b) => ({ label: b.nombre, value: b.id })))
const stockByProduct = ref<Map<string, number>>(new Map())
// Detalle de stock por almacén (para el popup "Stock por datos extra").
const stockDetailByProduct = ref<Map<string, { almacen: string; cantidad: number }[]>>(new Map())

const search = ref('')
const searchField = ref('nombre')
const estadoFilter = ref<'all' | 'activo' | 'inactivo'>('all')
const stockFilter = ref<'all' | 'con' | 'bajo' | 'agotado'>('all')
const marcaFilter = ref<string>('all')

// "Filtrar por": campo del producto sobre el que actúa el buscador.
const searchFieldOptions = [
  { label: 'Nombre', value: 'nombre' },
  { label: 'Código interno', value: 'sku' },
  { label: 'Código de barras', value: 'barcode' },
  { label: 'Modelo', value: 'modelo' },
  { label: 'Marca', value: 'marca' },
  { label: 'Fecha vencimiento', value: 'fecha_vencimiento' },
  { label: 'Código lote', value: 'codigo_lote' },
]
const searchFieldLabel = computed(
  () => searchFieldOptions.find((o) => o.value === searchField.value)?.label ?? 'Nombre',
)

const estadoFilterOptions = [
  { label: 'Todos', value: 'all' },
  { label: 'Activo', value: 'activo' },
  { label: 'Inactivo', value: 'inactivo' },
]
const stockFilterOptions = [
  { label: 'Todos', value: 'all' },
  { label: 'Con stock', value: 'con' },
  { label: 'Stock bajo', value: 'bajo' },
  { label: 'Agotado', value: 'agotado' },
]
// Filtro por marca: "Todas" + las marcas de la empresa.
const marcaFilterOptions = computed(() => [{ label: 'Todas', value: 'all' }, ...brandOptions.value])

const unidadOptions = [
  { label: 'Unidades (NIU)', value: 'NIU' },
  { label: 'Servicio (ZZ)', value: 'ZZ' },
  { label: 'Kilogramos (KGM)', value: 'KGM' },
  { label: 'Litros (LTR)', value: 'LTR' },
  { label: 'Metros (MTR)', value: 'MTR' },
  { label: 'Cajas (BX)', value: 'BX' },
]
const afectacionOptions = [
  { label: 'Gravado (10)', value: '10' },
  { label: 'Exonerado (20)', value: '20' },
  { label: 'Inafecto (30)', value: '30' },
  { label: 'Exportación (40)', value: '40' },
  { label: 'Transferencia gratuita (11)', value: '11' },
]
// Opciones Sí/No para selects booleanos (p. ej. ¿Maneja series?).
const siNoOptions = [
  { label: 'No', value: false },
  { label: 'Sí', value: true },
]

// Nombre completo de la unidad (para el tooltip de la columna U.M.).
function unidadNombre(v?: string): string {
  return unidadOptions.find((u) => u.value === (v || 'NIU'))?.label ?? (v || 'NIU')
}


// Reglas coherentes con validation.ts (reutilizadas en template y en la guarda de save()).
const codeRules: Rule[] = [onlyDigits()] // código SUNAT (UNSPSC): numérico
const barcodeRules: Rule[] = [] // código de barra: alfanumérico (Code128, códigos internos) → sin restricción
const stockInicialRules: Rule[] = [nonNegative('El stock inicial no puede ser negativo')]
const gananciaRules: Rule[] = [nonNegative('El porcentaje no puede ser negativo')]

function blankForm() {
  return {
    nombre: '',
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
    icbper: false,
    controla_stock: true,
    stock_minimo: 0,
    codigo_sunat: '',
    linea_producto: '',
    registro_sanitario: '',
    codigo_digemid: '',
    codigo_fabrica: '',
    imagen_url: '',
    activo: true,
    category_id: null as string | null,
    brand_id: null as string | null,
    // Compra / margen
    tipo_afectacion_compra: '10',
    aplica_ganancia: false,
    porcentaje_ganancia: 0,
    incluye_isc: false,
    // Tributos / restricciones del comprobante
    detraccion: false,
    percepcion: false,
    restringir_cpe: false,
    canje_puntos: false,
    // Trazabilidad de existencias
    fecha_vencimiento: '' as string,
    maneja_lotes: false,
    maneja_series: false,
    // Precios por almacén { [warehouse_id]: precio }
    precios_almacen: {} as Record<string, number>,
    warehouse_id: null as string | null,
    stock_inicial: 0,
  }
}
const form = ref(blankForm())
const uploadingImg = ref(false)
// Símbolo de moneda del producto (evita mostrar S/ en productos en USD).
const simbolo = computed(() => (form.value.moneda === 'USD' ? 'US$' : 'S/'))

// Precio sugerido de venta a partir del costo + % de ganancia (solo informativo, pestaña Compra).
const precioSugerido = computed(() => {
  const costo = Number(form.value.costo) || 0
  const margen = Number(form.value.porcentaje_ganancia) || 0
  return round2(costo * (1 + margen / 100))
})

// Precios por almacén: deja solo entradas con precio válido (> 0) antes de guardar.
function cleanPreciosAlmacen(m: Record<string, number>): Record<string, number> {
  const out: Record<string, number> = {}
  for (const [k, v] of Object.entries(m)) {
    const n = Number(v)
    if (Number.isFinite(n) && n > 0) out[k] = n
  }
  return out
}
// Un servicio no controla stock ni cobra ICBPER (bolsa). Se normaliza al elegir tipo.
watch(() => form.value.tipo, (t) => {
  if (t === 'servicio') {
    form.value.controla_stock = false
    form.value.icbper = false
    form.value.maneja_lotes = false
    form.value.maneja_series = false
    form.value.fecha_vencimiento = ''
  }
})

async function onPickImage(file: File | null) {
  if (!file || !company.current) return
  uploadingImg.value = true
  try {
    form.value.imagen_url = await uploadProductImage(company.current.id, file)
    notify({ type: 'positive', message: 'Imagen subida' })
  } catch (e) {
    notify({ type: 'negative', message: 'No se pudo subir: ' + (e as Error).message })
  } finally {
    uploadingImg.value = false
  }
}

const fileInput = ref<HTMLInputElement | null>(null)
function pickFile() {
  fileInput.value?.click()
}
function onFileChange(e: Event) {
  const input = e.target as HTMLInputElement
  void onPickImage(input.files?.[0] ?? null)
  input.value = '' // permite volver a elegir el mismo archivo
}

const warehouseOptions = computed(() => warehouses.value.map((w) => ({ label: w.nombre, value: w.id })))

// Stock actual del producto en edición (solo lectura; se mueve por Inventario).
const stockActualLabel = computed(() => {
  const p = editingId.value ? rows.value.find((r) => r.id === editingId.value) : null
  if (!p) return '—'
  if (p.controla_stock === false) return 'No controla stock'
  const s = stockByProduct.value.get(p.id) ?? 0
  return s <= 0 ? 'Agotado' : String(s)
})

// Tono del stock actual en el modal (color del dot/valor).
const stockActualTone = computed<'ok' | 'low' | 'out' | 'none'>(() => {
  const p = editingId.value ? rows.value.find((r) => r.id === editingId.value) : null
  if (!p || p.controla_stock === false) return 'none'
  const s = stockByProduct.value.get(p.id) ?? 0
  if (s <= 0) return 'out'
  if (s <= p.stock_minimo) return 'low'
  return 'ok'
})


/* ---------------- Stock, filtros y columnas ---------------- */
function stockOf(p: Product): number | null {
  if (!p.controla_stock) return null
  const v = stockByProduct.value.get(p.id)
  return v === undefined ? null : v
}
function stockLabel(p: Product): string | null {
  const s = stockOf(p)
  if (s === null) return null
  return s <= 0 ? 'Agotado' : String(s)
}
function onImgError(e: Event) {
  const img = e.target as HTMLImageElement
  if (!img.src.endsWith('/product-placeholder.svg')) img.src = '/product-placeholder.svg'
}

// Nombre de la marca a partir de su id (columna Marca).
const brandById = computed(() => new Map(brands.value.map((b) => [b.id, b.nombre])))
function brandName(id: string | null): string {
  return id ? brandById.value.get(id) ?? '—' : '—'
}

// Valor de venta unitario SIN IGV (columna "P. venta"): descuenta el IGV si el precio lo incluye.
function valorVentaNeto(p: Product): number {
  const precio = Number(p.precio) || 0
  if (p.tipo_afectacion === '10' && p.incluye_igv) return round2(precio / 1.18)
  return round2(precio)
}

// ID corto (los uuid completos son ilegibles en la tabla).
// Detalle de stock por almacén para el popup "Stock por datos extra".
function stockDetail(p: Product): { almacen: string; cantidad: number }[] {
  return stockDetailByProduct.value.get(p.id) ?? []
}

// Valor del campo elegido en "Filtrar por" (para buscar sobre él).
function searchValue(p: Product, field: string): string {
  switch (field) {
    case 'sku':
      return p.sku ?? ''
    case 'barcode':
      return p.barcode ?? ''
    case 'modelo':
      return p.modelo ?? ''
    case 'marca': {
      const b = brandName(p.brand_id)
      return b === '—' ? '' : b
    }
    case 'fecha_vencimiento':
      return p.fecha_vencimiento ?? ''
    case 'codigo_lote':
      return '' // aún no existe un campo de código de lote en el producto
    default:
      // "Nombre": busca por nombre e ID.
      return `${p.nombre} ${p.id}`
  }
}

const filteredRows = computed(() => {
  const q = search.value.trim().toLowerCase()
  return rows.value.filter((p) => {
    if (marcaFilter.value !== 'all' && p.brand_id !== marcaFilter.value) return false
    if (estadoFilter.value === 'activo' && p.activo === false) return false
    if (estadoFilter.value === 'inactivo' && p.activo !== false) return false
    if (stockFilter.value !== 'all') {
      const s = stockOf(p)
      if (stockFilter.value === 'con' && !(s !== null && s > 0)) return false
      if (stockFilter.value === 'agotado' && !(s !== null && s <= 0)) return false
      if (stockFilter.value === 'bajo' && !(s !== null && s > 0 && s <= p.stock_minimo)) return false
    }
    if (!q) return true
    return searchValue(p, searchField.value).toLowerCase().includes(q)
  })
})

const money = (v: unknown, row: Product) => `${row.moneda === 'USD' ? 'US$' : 'S/'} ${Number(v).toFixed(2)}`

const columns: QTableColumn<Product>[] = [
  { name: 'id', label: 'ID', field: 'id', align: 'left' },
  { name: 'unidad', label: 'Unidad', field: 'unidad_medida', align: 'left', sortable: true },
  { name: 'imagen', label: 'Imagen', field: 'imagen_url', align: 'center' },
  { name: 'producto', label: 'Nombre', field: 'nombre', align: 'left', sortable: true },
  { name: 'descripcion', label: 'Descripción', field: (r) => r.descripcion ?? '', align: 'left' },
  { name: 'modelo', label: 'Modelo', field: (r) => r.modelo || '—', align: 'left', sortable: true },
  { name: 'marca', label: 'Marca', field: (r) => brandName(r.brand_id), align: 'left', sortable: true },
  { name: 'codigo_sunat', label: 'Cód. SUNAT', field: (r) => r.codigo_sunat || '—', align: 'left' },
  { name: 'rs', label: 'R.S.', field: (r) => r.registro_sanitario || '—', align: 'left' },
  { name: 'digemid', label: 'DIGEMID', field: (r) => r.codigo_digemid || '—', align: 'left' },
  { name: 'stock_extra', label: 'Stock por datos extra', field: 'id', align: 'center' },
  { name: 'historial', label: 'Historial', field: 'id', align: 'center' },
  { name: 'stock', label: 'Stock', field: (r) => stockOf(r) ?? -1, align: 'center', sortable: true },
  { name: 'precio_venta', label: 'P.Unitario (Venta)', field: 'precio', align: 'right', sortable: true, format: money },
  { name: 'precio_compra', label: 'P.Unitario (Compra)', field: 'costo', align: 'right', sortable: true, format: money },
  { name: 'p_venta', label: 'P. venta', field: (r) => valorVentaNeto(r), align: 'right', sortable: true, format: money },
  { name: 'igv_venta', label: 'Tiene Igv (Venta)', field: (r) => (r.tipo_afectacion === '10' ? 1 : 0), align: 'center', sortable: true },
  { name: 'igv_compra', label: 'Tiene Igv (Compra)', field: (r) => (r.tipo_afectacion_compra === '10' ? 1 : 0), align: 'center', sortable: true },
  {
    name: 'estado',
    label: 'Estado',
    field: (r) => (r.activo === false ? 0 : 1),
    align: 'left',
    sortable: true,
  },
  { name: 'acciones', label: '', field: 'id', align: 'right' },
]

// Selección múltiple + acciones masivas estándar.
const selected = ref<Product[]>([])

async function bulkSetActivo(activo: boolean) {
  const items = selected.value.filter((p) => (p.activo !== false) !== activo)
  if (!items.length) {
    notify({ type: 'info', message: activo ? 'Ya estaban activos' : 'Ya estaban inactivos' })
    return
  }
  // allSettled: un fallo parcial no deja la UI desincronizada; siempre recarga y reporta.
  try {
    const res = await Promise.allSettled(items.map((p) => updateProduct(p.id, { activo })))
    const fail = res.filter((r) => r.status === 'rejected').length
    notify(fail
      ? { type: 'warning', message: `${items.length - fail} aplicados · ${fail} fallaron` }
      : { type: 'positive', message: `${items.length} producto(s) ${activo ? 'activados' : 'desactivados'}` })
  } finally {
    selected.value = []
    await load()
  }
}

// Duplica los productos seleccionados. La copia va SIN sku/barcode (evita chocar con
// índices únicos) y SIN foto (para no compartir la misma imagen del storage, que al
// borrar un producto dejaría al otro con la imagen rota). El original queda intacto.
async function bulkDuplicate() {
  const items = [...selected.value]
  if (!items.length || !company.current) return
  const companyId = company.current.id
  try {
    const res = await Promise.allSettled(
      items.map((p) => createProduct(companyId, productCopyPayload(p))),
    )
    const fail = res.filter((r) => r.status === 'rejected').length
    notify(
      fail
        ? { type: 'warning', message: `${items.length - fail} duplicado(s) · ${fail} fallaron` }
        : { type: 'positive', message: `${items.length} producto(s) duplicado(s)` },
    )
  } finally {
    selected.value = []
    await load()
  }
}

function bulkDelete() {
  const items = [...selected.value]
  if (!items.length) return
  $q.dialog({
    title: 'Eliminar productos',
    message: `¿Eliminar ${items.length} producto(s)? Los que tengan historial se desactivarán (baja lógica) para conservar la trazabilidad fiscal.`,
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

function openNew() {
  editingId.value = null
  form.value = blankForm()
  originalImageUrl.value = ''
  tab.value = 'basico'
  show.value = true
}

function openEdit(p: Product) {
  editingId.value = p.id
  form.value = {
    ...blankForm(),
    nombre: p.nombre,
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
    icbper: p.icbper ?? false,
    controla_stock: p.controla_stock ?? true,
    stock_minimo: p.stock_minimo ?? 0,
    codigo_sunat: p.codigo_sunat ?? '',
    linea_producto: p.linea_producto ?? '',
    registro_sanitario: p.registro_sanitario ?? '',
    codigo_digemid: p.codigo_digemid ?? '',
    codigo_fabrica: p.codigo_fabrica ?? '',
    imagen_url: p.imagen_url ?? '',
    activo: p.activo ?? true,
    category_id: p.category_id ?? null,
    brand_id: p.brand_id ?? null,
    tipo_afectacion_compra: p.tipo_afectacion_compra ?? '10',
    aplica_ganancia: p.aplica_ganancia ?? false,
    porcentaje_ganancia: p.porcentaje_ganancia ?? 0,
    incluye_isc: p.incluye_isc ?? false,
    detraccion: p.detraccion ?? false,
    percepcion: p.percepcion ?? false,
    restringir_cpe: p.restringir_cpe ?? false,
    canje_puntos: p.canje_puntos ?? false,
    fecha_vencimiento: p.fecha_vencimiento ?? '',
    maneja_lotes: p.maneja_lotes ?? false,
    maneja_series: p.maneja_series ?? false,
    precios_almacen: { ...(p.precios_almacen ?? {}) },
  }
  originalImageUrl.value = p.imagen_url ?? ''
  loadedUpdatedAt.value = p.updated_at ?? null
  tab.value = 'basico'
  show.value = true
}

// Payload para clonar un producto: sin sku/barcode (índices únicos) ni foto (para no
// compartir la misma imagen del storage). El original queda intacto. Lo usan el
// duplicado masivo y el de una sola fila (menú de acciones).
function productCopyPayload(p: Product) {
  return {
    nombre: `${p.nombre} (copia)`,
    precio: p.precio,
    tipo: p.tipo,
    unidad_medida: p.unidad_medida,
    sku: null,
    descripcion: p.descripcion ?? null,
    modelo: p.modelo ?? null,
    barcode: null,
    tipo_afectacion: p.tipo_afectacion,
    moneda: p.moneda ?? 'PEN',
    costo: p.costo,
    incluye_igv: p.incluye_igv ?? true,
    icbper: p.icbper ?? false,
    controla_stock: p.controla_stock ?? true,
    stock_minimo: p.stock_minimo ?? 0,
    codigo_sunat: p.codigo_sunat ?? null,
    linea_producto: p.linea_producto ?? null,
    registro_sanitario: p.registro_sanitario ?? null,
    codigo_digemid: p.codigo_digemid ?? null,
    codigo_fabrica: p.codigo_fabrica ?? null,
    imagen_url: null,
    activo: p.activo ?? true,
    category_id: p.category_id ?? null,
    brand_id: p.brand_id ?? null,
    tipo_afectacion_compra: p.tipo_afectacion_compra ?? null,
    aplica_ganancia: p.aplica_ganancia ?? false,
    porcentaje_ganancia: p.porcentaje_ganancia ?? 0,
    incluye_isc: p.incluye_isc ?? false,
    detraccion: p.detraccion ?? false,
    percepcion: p.percepcion ?? false,
    restringir_cpe: p.restringir_cpe ?? false,
    canje_puntos: p.canje_puntos ?? false,
    fecha_vencimiento: p.fecha_vencimiento ?? null,
    maneja_lotes: p.maneja_lotes ?? false,
    maneja_series: p.maneja_series ?? false,
    precios_almacen: p.precios_almacen ?? {},
  }
}

// Duplica un solo producto (desde el menú de la fila).
async function duplicateProduct(p: Product) {
  if (!company.current) return
  try {
    await createProduct(company.current.id, productCopyPayload(p))
    await load()
    notify({ type: 'positive', message: 'Producto duplicado' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  }
}

// Activa/desactiva (baja lógica) un producto desde el menú de la fila.
async function toggleActivo(p: Product) {
  const activo = p.activo === false
  try {
    await updateProduct(p.id, { activo })
    await load()
    notify({ type: 'positive', message: activo ? 'Producto activado' : 'Producto desactivado' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  }
}

function confirmDelete(p: Product) {
  $q.dialog({
    title: 'Eliminar producto',
    message: `¿Eliminar "${p.nombre}"? Si tiene historial de ventas/inventario se desactivará (baja lógica) para conservar la trazabilidad fiscal.`,
    cancel: true,
    persistent: true,
  }).onOk(async () => {
    try {
      const { softDeleted } = await deleteProduct(p.id, p.imagen_url)
      await load()
      notify({ type: 'positive', message: softDeleted ? 'Producto desactivado (tenía historial)' : 'Producto eliminado' })
    } catch (e) {
      notify({ type: 'negative', message: (e as Error).message })
    }
  })
}

// Exporta a Excel las filas visibles (respeta filtros) reutilizando las columnas.
function onExport() {
  exportTableXls('productos', columns, filteredRows.value)
}

async function load() {
  if (!company.current) return
  loading.value = !rows.value.length
  try {
    // Este módulo es solo de BIENES; los servicios tienen su propio módulo.
    rows.value = (await listProducts(company.current.id)).filter((p) => p.tipo !== 'servicio')
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
    [form.value.barcode, barcodeRules],
    [form.value.codigo_sunat, codeRules],
    [form.value.porcentaje_ganancia, gananciaRules],
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
      descripcion: form.value.descripcion || null,
      modelo: form.value.modelo || null,
      barcode: form.value.barcode || null,
      tipo_afectacion: form.value.tipo_afectacion,
      moneda: form.value.moneda,
      costo: form.value.costo,
      incluye_igv: form.value.incluye_igv,
      icbper: form.value.icbper,
      controla_stock: form.value.controla_stock,
      stock_minimo: form.value.stock_minimo,
      codigo_sunat: form.value.codigo_sunat || null,
      linea_producto: form.value.linea_producto || null,
      registro_sanitario: form.value.registro_sanitario || null,
      codigo_digemid: form.value.codigo_digemid || null,
      codigo_fabrica: form.value.codigo_fabrica || null,
      imagen_url: form.value.imagen_url || null,
      activo: form.value.activo,
      category_id: form.value.category_id || null,
      brand_id: form.value.brand_id || null,
      tipo_afectacion_compra: form.value.tipo_afectacion_compra || null,
      aplica_ganancia: form.value.aplica_ganancia,
      porcentaje_ganancia: form.value.porcentaje_ganancia,
      incluye_isc: form.value.incluye_isc,
      detraccion: form.value.detraccion,
      percepcion: form.value.percepcion,
      restringir_cpe: form.value.restringir_cpe,
      canje_puntos: form.value.canje_puntos,
      fecha_vencimiento: form.value.fecha_vencimiento || null,
      maneja_lotes: form.value.maneja_lotes,
      maneja_series: form.value.maneja_series,
      precios_almacen: cleanPreciosAlmacen(form.value.precios_almacen),
    }
    if (editingId.value) {
      await updateProduct(editingId.value, payload, loadedUpdatedAt.value)
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
        } catch (e) {
          // No se traga en silencio: el usuario debe saber que el stock inicial NO se cargó.
          notify({ type: 'warning', message: 'Producto creado, pero no se pudo registrar el stock inicial: ' + (e as Error).message })
        }
      }
    }
    // Si la imagen cambió o se quitó, borra la anterior del storage (evita huérfanos).
    if (originalImageUrl.value && originalImageUrl.value !== (form.value.imagen_url || null)) {
      await removeProductImage(originalImageUrl.value)
    }
    originalImageUrl.value = form.value.imagen_url || ''
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

async function refreshStock() {
  if (!company.current) return
  try {
    const stockRows = await listStock(company.current.id)
    const map = new Map<string, number>()
    const detail = new Map<string, { almacen: string; cantidad: number }[]>()
    for (const r of stockRows) {
      map.set(r.product_id, (map.get(r.product_id) ?? 0) + r.cantidad)
      const arr = detail.get(r.product_id) ?? []
      arr.push({ almacen: r.almacen, cantidad: r.cantidad })
      detail.set(r.product_id, arr)
    }
    stockByProduct.value = map
    stockDetailByProduct.value = detail
  } catch {
    /* el stock es informativo; si falla no bloquea el catálogo */
  }
}

/* ---------------- Historial del producto (stock · ventas · compras) ---------------- */
const histShow = ref(false)
const histLoading = ref(false)
const histTitle = ref('')
const histTab = ref<'stock' | 'ventas' | 'compras'>('stock')
const histStockRows = ref<{ almacen: string; cantidad: number }[]>([])
const histSales = ref<ProductSaleRow[]>([])
const histPurchases = ref<ProductPurchaseRow[]>([])
// Series disponibles del producto (a nivel de producto, no de almacén).
const histSerials = ref<string[]>([])

// Monto con el símbolo de la moneda de cada fila (una venta/compra puede ir en USD).
const histMoney = (v: unknown, row: { moneda?: string }) =>
  `${row.moneda === 'USD' ? 'US$' : 'S/'} ${Number(v).toFixed(2)}`

const stockCols: QTableColumn<{ almacen: string; cantidad: number }>[] = [
  { name: 'almacen', label: 'Inventario', field: 'almacen', align: 'left' },
  { name: 'cantidad', label: 'Stock', field: 'cantidad', align: 'right' },
  // Series a nivel de producto (mismas en todo inventario); se renderiza vía slot.
  { name: 'series', label: 'Series', field: () => '', align: 'left' },
]
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
  histTab.value = 'stock'
  histStockRows.value = stockDetail(p)
  histSales.value = []
  histPurchases.value = []
  histSerials.value = []
  histShow.value = true
  if (!company.current) return
  histLoading.value = true
  try {
    // allSettled: si una consulta falla, las otras pestañas igual muestran sus datos.
    // Con Promise.all un fallo parcial vaciaba todo y mostraba un "sin datos" falso.
    const [sales, purchases, serials] = await Promise.allSettled([
      listProductSales(company.current.id, p.id),
      listProductPurchases(company.current.id, p.id),
      listAvailableSerials(company.current.id, p.id),
    ])
    if (sales.status === 'fulfilled') histSales.value = sales.value
    if (purchases.status === 'fulfilled') histPurchases.value = purchases.value
    if (serials.status === 'fulfilled') histSerials.value = serials.value
    const err = sales.status === 'rejected' ? sales.reason
      : purchases.status === 'rejected' ? purchases.reason
        : serials.status === 'rejected' ? serials.reason : null
    if (err) notify({ type: 'negative', message: (err as Error).message })
  } finally {
    histLoading.value = false
  }
}

/* ---------------- Stock por ubicación (modal desde la columna Stock) ---------------- */
const stockShow = ref(false)
const stockTitle = ref('')
const stockModalRows = ref<{ almacen: string; cantidad: number }[]>([])
const stockModalCols: QTableColumn<{ almacen: string; cantidad: number }>[] = [
  { name: 'almacen', label: 'Ubicación', field: 'almacen', align: 'left' },
  { name: 'cantidad', label: 'Stock', field: 'cantidad', align: 'right' },
]
function openStock(p: Product) {
  stockTitle.value = p.nombre
  stockModalRows.value = stockDetail(p)
  stockShow.value = true
}

onMounted(async () => {
  await load()
  void refreshStock()
  try {
    if (company.current) {
      ;[warehouses.value, categories.value, brands.value] = await Promise.all([
        listWarehouses(company.current.id),
        listCategories(company.current.id),
        listBrands(company.current.id),
      ])
    }
  } catch {
    /* inventario opcional */
  }
})
</script>

<style scoped>
/* Filtros: proporción flexible (sin tamaños fijos). El buscador crece un poco más
   que los selects, sin ocupar todo. Solo en escritorio (una sola fila). */
@media (min-width: 1024px) {
  .k-search-col {
    flex-grow: 2.6;
  }
  .k-fcol {
    flex-grow: 1;
  }
}

/* Columna de selección (checkbox): más compacta y checkbox un poco más pequeño. */
.k-prod-table :deep(th:first-child),
.k-prod-table :deep(td:first-child) {
  width: 30px;
  padding-left: 8px;
  padding-right: 0;
}
.k-prod-table :deep(th:first-child .q-checkbox),
.k-prod-table :deep(td:first-child .q-checkbox) {
  transform: scale(0.78);
}

/* Imagen del producto (columna izquierda de Básica) */
.k-img-preview-wrap {
  width: 100%;
  max-width: 170px;
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
.k-upload-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  width: 100%;
  border: none;
  background: var(--k-surface-2);
  color: var(--k-text);
  font-family: inherit;
  font-size: 13.5px;
  font-weight: 600;
  padding: 13px;
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
/* Cambiar + Quitar en una sola fila (2 columnas) */
/* Botones de imagen apilados (la columna es angosta, ~150px): así "Cambiar" y
   "Quitar" quedan a ancho completo y no se ven apretados. */
.k-img-actions {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.k-img-actions .k-upload-btn {
  width: 100%;
  padding: 9px;
  font-size: 12.5px;
}

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

/* ---------- Celda producto ---------- */
.k-prod {
  display: flex;
  align-items: center;
  gap: 11px;
}
.k-prod-img {
  width: 38px;
  height: 38px;
  border-radius: 9px;
  object-fit: cover;
  background: var(--k-surface-2);
  flex-shrink: 0;
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

/* ---------- Chip de tipo ---------- */
.k-chip {
  display: inline-block;
  padding: 2px 10px;
  border-radius: 999px;
  background: var(--k-surface-2);
  color: var(--k-muted);
  font-size: 11.5px;
  font-weight: 600;
}

/* ---------- Stock ---------- */
.k-stock {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-weight: 700;
  font-size: 13px;
}
.k-stock--ok {
  color: var(--k-text);
}
.k-stock--low {
  color: var(--q-warning);
}
.k-stock--out {
  color: var(--q-negative);
}

/* ---------- Píldora de estado ---------- */
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

/* ---------- Estado vacío ---------- */
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

/* ---------- Botón de opciones (3 puntitos) ---------- */
.k-act-td {
  white-space: nowrap;
}
.k-act-btn {
  color: var(--k-muted);
}
.k-act-btn:hover {
  color: var(--k-text);
}

/* ---------- Columna de imagen (Básica) · espaciado uniforme ---------- */
.k-img-col {
  display: flex;
  flex-direction: column;
  gap: 10px;
  max-width: 170px;
}

/* ---------- Barra de precio + toggles (una sola fila) ---------- */
.k-price-bar {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 22px;
  padding: 6px 2px;
  background: transparent;
  font-variant-numeric: tabular-nums;
}
.k-pb-lbl {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 10.5px;
  text-transform: uppercase;
  letter-spacing: 0.3px;
  color: var(--k-muted);
}
.k-pb-val {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 15px;
  font-weight: 700;
  margin-top: 3px;
  color: var(--k-text);
}
.k-pb-total {
  font-size: 18px;
  font-weight: 800;
  letter-spacing: -0.3px;
}
.k-pb-sep {
  width: 1px;
  align-self: stretch;
  min-height: 32px;
  background: var(--k-border);
}
/* Opciones booleanas del producto como checkboxes (monocromas, limpias y sutiles) */
.k-checks :deep(.q-checkbox) {
  min-height: 34px;
}
/* Checkbox un poco más pequeño (default 40px) → presencia más sutil */
.k-checks :deep(.q-checkbox__inner) {
  font-size: 30px;
}
/* Relleno más suave (no el acento a full) para que no resalte tanto */
.k-checks :deep(.q-checkbox__inner--truthy) {
  color: color-mix(in srgb, var(--k-text) 80%, transparent);
}
.k-checks :deep(.q-checkbox__label) {
  font-size: 13.5px;
  color: var(--k-text);
}

/* Almacenes: precios por almacén */
.k-wh-prices {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.k-wh-row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 12px;
  border: 1px solid var(--k-border);
  border-radius: var(--k-radius-sm);
}
.k-wh-name {
  flex: 1;
  font-size: 13.5px;
  font-weight: 600;
}
.k-wh-input {
  width: 140px;
  flex: none;
}

/* Zona de peligro */
.k-danger {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 16px 18px;
  border-radius: var(--k-radius-sm);
  background: color-mix(in srgb, var(--q-negative) 8%, transparent);
}
.k-danger-title {
  font-weight: 600;
  font-size: 14px;
}
.k-danger-desc {
  font-size: 12.5px;
  color: var(--k-muted);
  margin-top: 2px;
}

/* Estandariza la altura de los campos del modal: los que tienen reglas ya no
   quedan más altos (no se reserva el espacio de mensaje vacío que descuadraba). */
.k-prod-modal :deep(.q-field--with-bottom .q-field__bottom) {
  min-height: 0;
  padding-top: 3px;
}

/* Almacén · stock actual */
.k-field-cap {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.3px;
  color: var(--k-muted);
  margin-bottom: 2px;
}
.k-stock-info {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 14px;
  border-radius: var(--k-radius-sm);
  border: 1px solid var(--k-border);
  background: transparent;
}
.k-stock-info .k-field-cap {
  margin-bottom: 0;
}
.k-stock-tag {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 14px;
  font-weight: 700;
  letter-spacing: -0.2px;
  color: var(--k-text);
}
.k-stock-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: currentColor;
  flex: none;
}
.k-stock-tag--out {
  color: #e5484d;
}
.k-stock-tag--low {
  color: #f5a623;
}
.k-stock-tag--ok {
  color: #46a758;
}
.k-stock-tag--none {
  color: var(--k-muted);
}

/* Columna Stock: valor actual + mínimo debajo */
.k-stock-cell {
  display: inline-flex;
  flex-direction: column;
  align-items: flex-end;
  line-height: 1.15;
}
.k-stock-min {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 10.5px;
  color: var(--k-muted);
  margin-top: 1px;
}

/* Chip de afectación IGV */
.k-afect {
  display: inline-flex;
  align-items: center;
  padding: 2px 9px;
  border-radius: 999px;
  border: 1px solid var(--k-border);
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.2px;
}
.k-afect--grav {
  color: var(--k-text);
}
.k-afect--gra {
  color: #46a758;
}
.k-afect--exo {
  color: #f5a623;
}
.k-afect--ina {
  color: var(--k-muted);
}
.k-afect--exp {
  color: #38bdf8;
}

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

/* Filtros ⇄ acciones masivas comparten el mismo lugar: el que SALE se posiciona
   absoluto (no empuja la tabla) y el que ENTRA define el alto → sin espacio extra.
   Movimiento "líquido" con el mismo easing global de la app. */
/* Animación filtros ⇄ acciones masivas: definida GLOBAL en theme.css (.k-toolbar-swap / .k-swap-*). */

/* La tabla es ancha: las celdas no se parten → fuerza el scroll horizontal.
   El estilo de la barra de scroll es GLOBAL (ver theme.css: .q-table__middle). */
.k-prod-table :deep(th),
.k-prod-table :deep(td) {
  white-space: nowrap;
}

/* ID corto en monoespaciada */
.k-id {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  color: var(--k-muted);
}

/* Descripción recortada con elipsis */
.k-desc {
  max-width: 260px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12.5px;
  color: var(--k-muted);
}

/* Popup "Stock por datos extra" */
.k-stock-pop {
  padding: 10px 12px;
  min-width: 200px;
}
.k-stock-pop-title {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 10.5px;
  text-transform: uppercase;
  letter-spacing: 0.3px;
  color: var(--k-muted);
  margin-bottom: 6px;
}
.k-stock-pop-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 3px 0;
  font-size: 13px;
}
.k-stock-pop-qty {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-weight: 700;
}

/* Acciones de la tabla en modo solo-ícono (Stock, Stock por almacén, Historial):
   círculo teñido de primario con el ícono que mejor representa cada acción. */
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

/* Diálogo de historial (pestañas stock/ventas/compras) */
.k-hist-panel {
  padding: 12px;
}
.k-hist-table {
  max-height: 56vh;
}
.k-hist-table :deep(th),
.k-hist-table :deep(td) {
  white-space: nowrap;
}
/* Más aire vertical en las filas (contrarresta el `dense` de las tablas). */
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
/* Zebra sutil: aunque un separador de 1px se "caiga" por redondeo sub-pixel del
   navegador (zoom ≠ 100%), las filas siguen distinguiéndose por el fondo alterno. */
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
/* Píldora de estado en tono negativo (rechazado/anulado) */
.k-pill--err {
  color: var(--q-negative);
  background: color-mix(in srgb, var(--q-negative) 15%, transparent);
}
</style>
