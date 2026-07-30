<template>
  <q-page class="q-pa-md">
    <div
      class="row items-center q-mb-md q-gutter-x-md"
      style="min-height: 48px"
    >
      <div class="text-h5">
        Emitir comprobante
      </div>
      <q-select
        v-model="tipoDoc"
        :options="tipoOptions"
        emit-value
        map-options
        options-dense
        outlined
        dense
        label="Tipo de comprobante"
        class="k-tipo-select"
      >
        <template #prepend>
          <q-icon
            name="receipt_long"
            size="20px"
          />
        </template>
      </q-select>
      <q-select
        v-model="serie"
        :options="serieOptions"
        outlined
        dense
        options-dense
        label="Serie"
        class="k-serie-select"
      >
        <template #prepend>
          <q-icon
            name="tag"
            size="18px"
          />
        </template>
      </q-select>
      <q-select
        v-model="moneda"
        :options="monedaOptions"
        emit-value
        map-options
        options-dense
        outlined
        dense
        label="Moneda"
        class="k-moneda-select"
      />
    </div>

    <div class="row q-col-gutter-md">
      <!-- ============ Izquierda: formulario ============ -->
      <div class="col-12 col-md-8">
        <!-- Datos del comprobante -->
        <q-card class="q-mb-md">
          <q-card-section class="k-pad">
            <div class="k-label">
              Cliente
            </div>
            <q-select
              v-model="selectedCustomerId"
              :options="customerOptions"
              emit-value
              map-options
              clearable
              use-input
              outlined
              dense
              input-debounce="0"
              placeholder="Buscar cliente registrado (opcional)"
              @filter="filterCustomers"
              @update:model-value="onPickCustomer"
            >
              <template #prepend>
                <q-icon name="person_search" />
              </template>
              <template #no-option>
                <q-item
                  v-close-popup
                  clickable
                  @click="irAClientes"
                >
                  <q-item-section>
                    <q-item-label class="text-muted">
                      <q-icon
                        name="person_add"
                        size="16px"
                        class="q-mr-xs"
                      />
                      Añadir cliente
                    </q-item-label>
                  </q-item-section>
                </q-item>
              </template>
            </q-select>

            <div class="k-cliente-row q-mt-md">
              <div class="k-nombre">
                <q-input
                  v-model="clienteNombre"
                  outlined
                  dense
                  label="Nombre / Razón social"
                  :rules="nameRules"
                  lazy-rules="ondemand"
                  hide-bottom-space
                />
              </div>
              <!-- Doc del receptor: RUC (factura) o RUC/DNI opcional (boleta, obligatorio ≥ S/700). -->
              <Transition name="k-liquid">
                <div
                  v-if="tipoDoc === '01' || tipoDoc === '03'"
                  class="k-docfields"
                >
                  <q-select
                    v-model="clienteTipoDoc"
                    outlined
                    dense
                    :options="docOptions"
                    emit-value
                    map-options
                    label="Doc"
                    class="k-doc-tipo"
                  />
                  <q-input
                    v-model="clienteNumDoc"
                    outlined
                    dense
                    :label="clienteTipoDoc === '6' ? 'RUC' : 'DNI'"
                    :rules="docRules"
                    lazy-rules="ondemand"
                    hide-bottom-space
                    class="k-doc-num"
                    :class="{ 'k-doc-num--ruc': clienteTipoDoc === '6' }"
                    @update:model-value="onDocInput"
                    @keyup.enter="autocompletarDoc(true)"
                  >
                    <template #append>
                      <q-btn
                        flat
                        dense
                        round
                        size="sm"
                        icon="search"
                        :loading="buscandoDoc"
                        @click="autocompletarDoc(true)"
                      >
                        <q-tooltip>Autocompletar por RUC/DNI</q-tooltip>
                      </q-btn>
                    </template>
                  </q-input>
                </div>
              </Transition>
            </div>
          </q-card-section>
        </q-card>

        <!-- Ítems -->
        <q-card>
          <q-card-section class="k-pad">
            <div class="row items-center q-mb-sm">
              <div class="text-subtitle1">
                Ítems
              </div>
              <q-space />
              <div class="text-caption text-muted">
                {{ items.length }} línea(s)
              </div>
            </div>

            <div class="k-items-wrap">
              <!-- Cabecera de columnas (una sola vez) -->
              <div class="k-items-head">
                <div>Producto</div>
                <div>Descripción</div>
                <div class="k-r">
                  Cant.
                </div>
                <div>
                  Precio
                </div>
                <div class="k-r">
                  Desc. %
                </div>
                <div class="k-r">
                  Importe
                </div>
                <div />
              </div>

              <TransitionGroup
                name="k-item-liquid"
                tag="div"
                class="k-items-list"
              >
                <div
                  v-for="(it, idx) in items"
                  :key="it._id"
                  class="k-item"
                >
                  <q-select
                    v-model="it.productId"
                    class="k-c k-c-prod"
                    :options="productOptions"
                    emit-value
                    map-options
                    options-dense
                    clearable
                    borderless
                    dense
                    @update:model-value="onPick(idx, $event)"
                  >
                    <template
                      v-if="!it.productId"
                      #selected
                    >
                      <span class="k-cell-ph">Seleccionar</span>
                    </template>
                  </q-select>
                  <q-input
                    v-model="it.descripcion"
                    class="k-c"
                    borderless
                    dense
                    type="textarea"
                    autogrow
                    placeholder="Descripción"
                    hide-bottom-space
                  />
                  <q-input
                    v-model.number="it.cantidad"
                    class="k-c"
                    borderless
                    dense
                    type="number"
                    input-class="text-right"
                    hide-bottom-space
                  />
                  <q-input
                    v-model="it.precio"
                    class="k-c k-c-precio"
                    borderless
                    dense
                    type="text"
                    inputmode="decimal"
                    :prefix="simbolo"
                    placeholder="0.00"
                    hide-bottom-space
                    @blur="formatPrecio(it)"
                  />
                  <q-input
                    v-model="it.descuentoPct"
                    class="k-c"
                    borderless
                    dense
                    type="text"
                    inputmode="numeric"
                    suffix="%"
                    placeholder="0"
                    input-class="text-right"
                    hide-bottom-space
                    @blur="clampDesc(it)"
                  />
                  <div class="k-c-imp">
                    <span
                      v-if="esGratis(it)"
                      class="k-gratis-tag"
                    >Gratis</span>
                    <template v-else>
                      {{ simbolo }} {{ money(lineTotal(it)) }}
                    </template>
                  </div>
                  <div class="k-c-x">
                    <q-btn
                      flat
                      dense
                      round
                      size="sm"
                      :icon="esGratis(it) ? 'redeem' : 'card_giftcard'"
                      :color="esGratis(it) ? 'primary' : 'grey-6'"
                      @click="toggleGratis(it)"
                    >
                      <q-tooltip>{{ esGratis(it) ? 'Quitar regalo' : 'Marcar como regalo (gratis)' }}</q-tooltip>
                    </q-btn>
                    <q-btn
                      flat
                      dense
                      round
                      size="sm"
                      icon="close"
                      color="negative"
                      @click="items.splice(idx, 1)"
                    >
                      <q-tooltip>Quitar ítem</q-tooltip>
                    </q-btn>
                  </div>
                </div>
              </TransitionGroup>
            </div>

            <q-btn
              flat
              no-caps
              color="primary"
              icon="add"
              label="Agregar ítem"
              class="q-mt-sm"
              @click="addItem"
            />
          </q-card-section>
        </q-card>
      </div>

      <!-- ============ Derecha: resumen ============ -->
      <div class="col-12 col-md-4">
        <q-card class="k-summary-col">
          <q-card-section class="k-pad">
            <div class="text-subtitle1 q-mb-md">
              Resumen
            </div>

            <!-- Condición de pago (contado por defecto; crédito genera cuenta por cobrar) -->
            <q-select
              v-model="condicionPago"
              :options="condicionOptions"
              emit-value
              map-options
              options-dense
              outlined
              dense
              label="Condición de pago"
              class="q-mb-sm"
            />
            <q-input
              v-if="condicionPago === 'credito'"
              v-model="fechaVencimiento"
              outlined
              dense
              type="date"
              label="Fecha de vencimiento"
              class="q-mb-sm"
            />
            <q-input
              v-if="moneda === 'USD'"
              v-model.number="tipoCambio"
              outlined
              dense
              type="number"
              label="Tipo de cambio (S/ por US$)"
              :hint="tcHint"
              class="q-mb-sm"
              @update:model-value="tcManual = true"
            >
              <template #append>
                <q-btn
                  flat
                  dense
                  round
                  size="sm"
                  icon="refresh"
                  :loading="tc.loading"
                  @click="tcManual = false; tc.refresh()"
                >
                  <q-tooltip>Actualizar tipo de cambio</q-tooltip>
                </q-btn>
              </template>
            </q-input>
            <q-separator class="q-mb-md" />

            <div class="k-sum">
              <div class="k-sum-row">
                <span>Gravado</span><span>{{ simbolo }} {{ money(totals.gravado) }}</span>
              </div>
              <div class="k-sum-row">
                <span>IGV (18%)</span><span>{{ simbolo }} {{ money(totals.igv) }}</span>
              </div>
              <div
                v-if="totals.exonerado > 0"
                class="k-sum-row"
              >
                <span>Exonerado</span><span>{{ simbolo }} {{ money(totals.exonerado) }}</span>
              </div>
              <div
                v-if="totals.inafecto > 0"
                class="k-sum-row"
              >
                <span>Inafecto</span><span>{{ simbolo }} {{ money(totals.inafecto) }}</span>
              </div>
              <div
                v-if="totals.exportacion > 0"
                class="k-sum-row"
              >
                <span>Exportación</span><span>{{ simbolo }} {{ money(totals.exportacion) }}</span>
              </div>
              <div
                v-if="totals.gratuito > 0"
                class="k-sum-row k-sum-muted"
              >
                <span>Gratuito</span><span>{{ simbolo }} {{ money(totals.gratuito) }}</span>
              </div>
              <div class="k-sum-row items-center">
                <span>Descuento global</span>
                <q-input
                  v-model.number="descuentoGlobal"
                  dense
                  borderless
                  input-class="text-right k-mono"
                  style="max-width: 90px"
                  type="number"
                  placeholder="0"
                />
              </div>
            </div>

            <q-separator class="q-my-md" />
            <div class="k-total-row">
              <span>Total</span><span class="k-total-amount">{{ simbolo }} {{ money(totals.total) }}</span>
            </div>

            <q-btn
              class="full-width q-mt-md k-emit"
              color="primary"
              unelevated
              size="lg"
              icon="receipt_long"
              :label="`Emitir  ·  ${simbolo} ${money(totals.total)}`"
              :loading="emitting"
              @click="emit"
            />

            <q-banner
              v-if="lastResult"
              class="q-mt-md k-banner"
              :class="`k-banner--${bannerTone}`"
            >
              <template #avatar>
                <q-icon
                  :name="bannerTone === 'ok' ? 'check_circle' : bannerTone === 'err' ? 'error' : 'hourglass_top'"
                  :color="bannerTone === 'ok' ? 'positive' : bannerTone === 'err' ? 'negative' : 'warning'"
                />
              </template>
              {{ lastResult.mensaje }}
            </q-banner>

            <q-btn
              v-if="lastDoc"
              class="full-width q-mt-sm k-wa"
              color="green-7"
              unelevated
              no-caps
              @click="whatsapp"
            >
              <img
                src="/whatsapp.svg"
                alt=""
                class="k-wa-logo"
              >
              Enviar por WhatsApp
            </q-btn>
          </q-card-section>
        </q-card>
      </div>
    </div>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { notify } from '@/lib/toast'
import { uid } from '@/lib/uid'
import { todayLocal } from '@/lib/date'
import { useCompanyStore } from '@/stores/company'
import { useTipoCambioStore } from '@/stores/tipoCambio'
import { listProducts } from '@/modules/products/products.api'
import { listCustomers } from '@/modules/customers/customers.api'
import { emitirComprobante } from '@/modules/documents/documents.api'
import { useSeries } from '@/modules/documents/useSeries'
import { lookupDoc } from '@/modules/documents/lookup.api'
import { compartirWhatsApp } from '@/lib/share'
import type { EmitResult } from '@/modules/sunat'
import { validate, docByTipo, nameRules, qtyRules, priceRules, type Rule } from '@/lib/validation'
import type { Customer, Product, TipoDoc, DocumentRow } from '@/types'

const company = useCompanyStore()
const router = useRouter()
// Estado vacío del selector de cliente: ir a registrar uno nuevo.
function irAClientes() {
  router.push({ name: 'customers' })
}

const tipoOptions: { label: string; value: TipoDoc }[] = [
  { label: 'Boleta', value: '03' },
  { label: 'Factura', value: '01' },
]
// Para Factura (01) el adquirente SOLO puede ser RUC (SUNAT rechaza factura con DNI).
const docOptions = computed(() =>
  tipoDoc.value === '01'
    ? [{ label: 'RUC', value: '6' }]
    : [
        { label: 'RUC', value: '6' },
        { label: 'DNI', value: '1' },
      ],
)
const condicionOptions = [
  { label: 'Contado', value: 'contado' },
  { label: 'Crédito', value: 'credito' },
]
const tipoDoc = ref<TipoDoc>('03')
const condicionPago = ref('contado')
const fechaVencimiento = ref('')
const clienteNombre = ref('Cliente varios')
const clienteTipoDoc = ref('6')
const clienteNumDoc = ref('')
const selectedCustomerId = ref<string | null>(null)
const descuentoGlobal = ref(0)
const moneda = ref('PEN')

// Tipo de cambio: por defecto el GLOBAL (SUNAT/mercado), editable a mano.
const tc = useTipoCambioStore()
const tipoCambio = ref(Number(tc.venta.toFixed(2)))
const tcManual = ref(false)
const tcHint = computed(() => {
  const o = tc.origen === 'SUNAT' ? 'SUNAT' : tc.origen === 'mercado' ? 'mercado' : 'por defecto'
  return tc.fecha ? `Tipo de cambio ${o} · ${tc.fecha}` : `Tipo de cambio ${o}`
})
// Mientras no lo toquen a mano, se mantiene sincronizado con el TC global.
watch(
  () => tc.venta,
  (v) => {
    if (!tcManual.value) tipoCambio.value = Number(v.toFixed(2))
  },
)
const monedaOptions = [
  { label: 'Soles (S/)', value: 'PEN' },
  { label: 'Dólares (US$)', value: 'USD' },
]
const simbolo = computed(() => (moneda.value === 'USD' ? 'US$' : 'S/'))
const { serie, serieOptions, loadSeries } = useSeries(computed(() => company.current?.id), tipoDoc)
const lastDoc = ref<DocumentRow | null>(null)
const buscandoDoc = ref(false)

interface Item {
  _id: string
  productId: string | null
  descripcion: string
  cantidad: number
  /** Precio unitario como texto (para mostrar símbolo de moneda y 2 decimales). */
  precio: string
  /** Descuento de la línea EN PORCENTAJE (texto, 0-100). */
  descuentoPct: string
  tipoAfectacion: string
  /** Unidad de medida SUNAT (cat. 03). Por defecto NIU. */
  unidadMedida: string
}
const newItem = (): Item => ({ _id: uid(), productId: null, descripcion: '', cantidad: 1, precio: '', descuentoPct: '', tipoAfectacion: '10', unidadMedida: 'NIU' })
const items = ref<Item[]>([newItem()])
const products = ref<Product[]>([])
const customers = ref<Customer[]>([])
const customerFilter = ref('')
const emitting = ref(false)
const lastResult = ref<EmitResult | null>(null)

const productOptions = computed(() =>
  products.value.map((p) => ({ label: `${p.nombre} (S/ ${p.precio})`, value: p.id })),
)
const customerOptions = computed(() =>
  customers.value
    .filter((c) => !customerFilter.value || c.denominacion.toLowerCase().includes(customerFilter.value.toLowerCase()) || (c.num_doc ?? '').includes(customerFilter.value))
    .map((c) => ({ label: `${c.denominacion}${c.num_doc ? ' · ' + c.num_doc : ''}`, value: c.id })),
)

function round2(n: number) {
  return Math.round((n + Number.EPSILON) * 100) / 100
}
function money(n: number): string {
  return Number(n || 0).toFixed(2)
}
function precioNum(it: Item): number {
  return Math.max(0, Number(it.precio) || 0)
}
// Descuento por línea EN PORCENTAJE (0-100).
function descPct(it: Item): number {
  return Math.min(100, Math.max(0, Number(it.descuentoPct) || 0))
}
// El % se convierte a MONTO (lo que espera la RPC emitir_venta).
function descuentoMonto(it: Item): number {
  return round2((it.cantidad || 0) * precioNum(it) * descPct(it) / 100)
}
function lineTotal(it: Item): number {
  return round2((it.cantidad || 0) * precioNum(it) - descuentoMonto(it))
}
// Al salir del campo: precio a 2 decimales (10 → 10.00); descuento acotado a 0-100.
function formatPrecio(it: Item): void {
  it.precio = it.precio === '' ? '' : precioNum(it).toFixed(2)
}
function clampDesc(it: Item): void {
  it.descuentoPct = it.descuentoPct === '' ? '' : String(descPct(it))
}
// Gratuitas (regalo/bonificación) · cat.07 11-17, 21, 31-36. El ítem no suma al total;
// el precio se envía como valor REFERENCIAL. El toggle usa 13 (bonificación gravada).
const GRAT_CODES = new Set(['11', '12', '13', '14', '15', '16', '17', '21', '31', '32', '33', '34', '35', '36'])
function esGratis(it: Item): boolean {
  return GRAT_CODES.has(it.tipoAfectacion)
}
function toggleGratis(it: Item): void {
  it.tipoAfectacion = esGratis(it) ? '10' : '13'
}

const totals = computed(() => {
  // Suma por afectación en "importe de línea" (el gravado incluye IGV).
  let gravadoLT = 0
  let exonerado = 0
  let inafecto = 0
  let exportacion = 0
  let gratuito = 0
  for (const it of items.value) {
    const lt = lineTotal(it)
    switch (it.tipoAfectacion) {
      case '10': gravadoLT += lt; break
      case '20': exonerado += lt; break
      case '30': inafecto += lt; break
      case '40': exportacion += lt; break
      default: gratuito += lt
    }
  }
  // El descuento global se PRORRATEA sobre lo descontable (no sobre lo gratuito),
  // reduciendo la base gravada → así el IGV se recalcula y el desglose cuadra con el Total.
  const descontable = gravadoLT + exonerado + inafecto + exportacion
  const desc = Math.min(Math.max(descuentoGlobal.value || 0, 0), descontable)
  const factor = descontable > 0 ? (descontable - desc) / descontable : 1
  gravadoLT = round2(gravadoLT * factor)
  exonerado = round2(exonerado * factor)
  inafecto = round2(inafecto * factor)
  exportacion = round2(exportacion * factor)
  const gravado = round2(gravadoLT / 1.18)
  const igv = round2(gravadoLT - gravado)
  // Las operaciones GRATUITAS no forman parte del importe total a pagar (SUNAT las
  // consigna en un campo referencial aparte). No se suman al Total.
  const total = round2(gravado + igv + exonerado + inafecto + exportacion)
  return { gravado, igv, exonerado, inafecto, exportacion, gratuito: round2(gratuito), total }
})

// El documento es obligatorio en factura; en boleta es opcional (< S/700).
const docRules = computed<Rule[]>(() => [docByTipo(clienteTipoDoc.value, tipoDoc.value === '01')])

// Factura → el receptor debe ser RUC; fuerza el tipo de doc a RUC al pasar a Factura.
watch(tipoDoc, (t) => {
  if (t === '01' && clienteTipoDoc.value !== '6') clienteTipoDoc.value = '6'
})

// Al cambiar de moneda, reconvierte los precios ya ingresados por el TC
// (evita enviar magnitudes en soles como dólares o viceversa).
watch(moneda, (nueva, previa) => {
  if (nueva === previa) return
  const tcv = tipoCambio.value || 1
  for (const it of items.value) {
    const p = Number(it.precio)
    if (!it.precio || Number.isNaN(p)) continue
    if (previa === 'PEN' && nueva === 'USD') it.precio = (p / tcv).toFixed(2)
    else if (previa === 'USD' && nueva === 'PEN') it.precio = (p * tcv).toFixed(2)
  }
})

function addItem() {
  items.value.push(newItem())
}
function filterCustomers(val: string, update: (fn: () => void) => void) {
  update(() => { customerFilter.value = val })
}
function onPickCustomer(id: string | null) {
  const c = customers.value.find((x) => x.id === id)
  if (c) {
    clienteNombre.value = c.denominacion
    // Respeta el tipo de documento real del cliente (6=RUC, 1=DNI, 4=CE, 7=Pasaporte).
    clienteTipoDoc.value = c.tipo_doc || '1'
    clienteNumDoc.value = c.num_doc ?? ''
    if (c.tipo_doc === '6') tipoDoc.value = '01'
  }
}
function onPick(idx: number, productId: string | null) {
  const p = products.value.find((x) => x.id === productId)
  if (p) {
    items.value[idx].descripcion = p.nombre
    let precioBase = p.precio ?? 0
    // El motor asume precio CON IGV incluido: si el catálogo lo guarda neto (gravado), pásalo a bruto.
    if (p.incluye_igv === false && (p.tipo_afectacion ?? '10') === '10') precioBase = round2(precioBase * 1.18)
    // El catálogo está en SOLES: si el comprobante está en USD, convertir por el TC.
    const precioMoneda = moneda.value === 'USD' && tipoCambio.value > 0 ? precioBase / tipoCambio.value : precioBase
    items.value[idx].precio = precioMoneda.toFixed(2)
    if (p.tipo_afectacion) items.value[idx].tipoAfectacion = p.tipo_afectacion
    items.value[idx].unidadMedida = p.unidad_medida || 'NIU'
  }
}

// Deriva el documento de identidad del RECEPTOR según el tipo de comprobante y el número real.
// Factura → siempre RUC. Boleta → CE/pasaporte si el cliente lo tiene; si no, por longitud
// (11=RUC, 8=DNI); sin número → '0' (sin documento), como exige SUNAT para "Cliente varios".
function receptorCliente(): { tipoDoc: string; numDoc?: string } {
  const raw = clienteNumDoc.value.trim()
  const num = raw.replace(/\D/g, '')
  if (tipoDoc.value === '01') return { tipoDoc: '6', numDoc: raw || undefined }
  if (!raw) return { tipoDoc: '0', numDoc: undefined }
  if (clienteTipoDoc.value === '4' || clienteTipoDoc.value === '7') return { tipoDoc: clienteTipoDoc.value, numDoc: raw }
  if (num.length === 11) return { tipoDoc: '6', numDoc: num }
  if (num.length === 8) return { tipoDoc: '1', numDoc: num }
  return { tipoDoc: '0', numDoc: undefined }
}

// Autocompleta el nombre/razón social consultando el RUC/DNI (Edge Function `lookup`).
// Si no hay proveedor configurado, no rompe: el usuario escribe el nombre a mano.
async function autocompletarDoc(manual = false) {
  const num = clienteNumDoc.value.replace(/\D/g, '')
  const tipo = clienteTipoDoc.value === '6' ? 'ruc' : 'dni'
  if ((tipo === 'ruc' && num.length !== 11) || (tipo === 'dni' && num.length !== 8)) {
    if (manual) notify({ type: 'warning', message: tipo === 'ruc' ? 'El RUC debe tener 11 dígitos' : 'El DNI debe tener 8 dígitos' })
    return
  }
  buscandoDoc.value = true
  try {
    const r = await lookupDoc(tipo, num)
    if (r?.denominacion) {
      clienteNombre.value = r.denominacion
      notify({ type: 'positive', message: 'Datos autocompletados' })
    } else if (manual) {
      notify({ type: 'warning', message: 'No se encontró (escribe el nombre a mano)' })
    }
  } finally {
    buscandoDoc.value = false
  }
}

// Al terminar de escribir el número (8 dígitos DNI / 11 RUC), autocompleta solo.
function onDocInput(v: string | number | null) {
  const num = String(v ?? '').replace(/\D/g, '')
  const need = clienteTipoDoc.value === '6' ? 11 : 8
  if (num.length === need) void autocompletarDoc(false)
}

// Estado visual del banner: ok · en proceso (pendiente) · rechazado.
const bannerTone = computed<'ok' | 'pending' | 'err'>(() => {
  const e = lastResult.value?.estado
  return e === 'aceptado' ? 'ok' : e === 'rechazado' ? 'err' : 'pending'
})

// Comparte el último comprobante emitido por WhatsApp (enlace wa.me con el PDF).
function whatsapp() {
  if (!lastDoc.value || !company.current) return
  compartirWhatsApp(company.current.razon_social, lastDoc.value, { pdfUrl: lastDoc.value.pdf_url })
}

// Llave de idempotencia estable por intento: reintentar NO emite un segundo comprobante.
const ventaKey = ref<string | null>(null)
async function emit() {
  if (!company.current) return
  const cabErr = validate([[clienteNombre.value, nameRules]])
  if (cabErr) { notify({ type: 'warning', message: cabErr }); return }
  if (tipoDoc.value === '01') {
    const docErr = validate([[clienteNumDoc.value, docRules.value]])
    if (docErr) { notify({ type: 'warning', message: docErr }); return }
  }
  // USD: exige tipo de cambio > 0. Sin él, el comprobante se convertiría mal a soles
  // en el servidor y el umbral de S/700 se evaluaría como si 1 USD = 1 PEN.
  if (moneda.value === 'USD' && !(Number(tipoCambio.value) > 0)) {
    notify({ type: 'warning', message: 'Ingresa un tipo de cambio válido (> 0) para emitir en dólares.' })
    return
  }
  // Boleta ≥ S/700: SUNAT exige identificar al adquirente (DNI 8 o RUC 11 dígitos).
  // El umbral es en SOLES → si la boleta es en USD, se convierte con el tipo de cambio.
  const numDocDigits = clienteNumDoc.value.replace(/\D/g, '')
  const totalSoles = moneda.value === 'USD' ? totals.value.total * (tipoCambio.value || 1) : totals.value.total
  if (tipoDoc.value === '03' && totalSoles >= 700 && numDocDigits.length !== 8 && numDocDigits.length !== 11) {
    notify({ type: 'warning', message: 'Boleta ≥ S/700: selecciona un cliente con DNI o RUC.' })
    return
  }
  // Descuento global: no negativo y no mayor al importe DESCONTABLE (excluye gratuitos,
  // que no aportan al total pagable). Antes incluir gratuitos permitía total 0 con IGV > 0.
  const subtotalItems = items.value.filter((it) => !esGratis(it)).reduce((s, it) => s + lineTotal(it), 0)
  if (descuentoGlobal.value < 0 || descuentoGlobal.value > subtotalItems) {
    notify({ type: 'warning', message: 'El descuento no puede ser negativo ni mayor al total.' })
    return
  }
  if (items.value.length === 0) { notify({ type: 'warning', message: 'Agrega al menos un ítem' }); return }
  for (const it of items.value) {
    const itemErr = validate([[it.descripcion, nameRules], [it.cantidad, qtyRules], [precioNum(it), priceRules]])
    if (itemErr) { notify({ type: 'warning', message: `Ítem: ${itemErr}` }); return }
  }
  // Venta al crédito: SUNAT exige fecha de vencimiento (forma de pago "Credito"); no puede
  // ser anterior a la emisión.
  if (condicionPago.value === 'credito') {
    if (!fechaVencimiento.value) {
      notify({ type: 'warning', message: 'Una venta al crédito requiere fecha de vencimiento.' })
      return
    }
    if (fechaVencimiento.value < todayLocal()) {
      notify({ type: 'warning', message: 'La fecha de vencimiento no puede ser anterior a hoy.' })
      return
    }
  }

  if (!ventaKey.value) ventaKey.value = uid()
  emitting.value = true
  lastResult.value = null
  try {
    const { document, result } = await emitirComprobante({
      companyId: company.current.id,
      idempotencyKey: ventaKey.value,
      tipoDoc: tipoDoc.value,
      customerId: selectedCustomerId.value,
      cliente: {
        ...receptorCliente(),
        denominacion: clienteNombre.value,
      },
      serie: serie.value || undefined,
      moneda: moneda.value,
      tipoCambio: moneda.value === 'USD' ? (tipoCambio.value || 1) : 1,
      condicionPago: condicionPago.value,
      fechaVencimiento: condicionPago.value === 'credito' ? fechaVencimiento.value || null : null,
      descuentoGlobal: descuentoGlobal.value || 0,
      items: items.value
        .filter((i) => i.descripcion && i.cantidad > 0)
        .map((i) => ({
          productId: i.productId,
          descripcion: i.descripcion,
          cantidad: i.cantidad,
          precioUnitario: precioNum(i),
          descuento: descuentoMonto(i),
          tipoAfectacion: i.tipoAfectacion,
          unidadMedida: i.unidadMedida,
        })),
    })
    lastResult.value = result
    ventaKey.value = null // el intento terminó → la próxima venta usa una llave nueva
    if (result.estado === 'rechazado') {
      // SUNAT rechazó: NO limpiar el carrito (para corregir y reemitir), no ofrecer
      // WhatsApp de un comprobante rechazado. El correlativo quedó consumido.
      lastDoc.value = null
      notify({ type: 'negative', message: result.mensaje ?? 'SUNAT rechazó el comprobante. Revisa los datos.' })
    } else {
      lastDoc.value = document
      const aceptado = result.estado === 'aceptado'
      notify({
        type: aceptado ? 'positive' : 'warning',
        message: result.mensaje ?? (aceptado ? 'Emitido' : 'Comprobante en proceso en SUNAT'),
      })
      items.value = [newItem()]
      descuentoGlobal.value = 0
    }
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    emitting.value = false
  }
}

onMounted(async () => {
  if (!company.current) return
  void loadSeries()
  // Asegura un tipo de cambio fresco al entrar a Emitir (por si cambió de día o falló al arrancar).
  void tc.refresh()
  try {
    ;[products.value, customers.value] = await Promise.all([
      listProducts(company.current.id),
      listCustomers(company.current.id),
    ])
  } catch {
    /* sin datos aún: se puede emitir escribiendo a mano */
  }
})
</script>

<style scoped>
.k-pad {
  padding: 20px;
}
.k-label {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.4px;
  color: var(--k-muted);
  margin-bottom: 6px;
}
/* Selector de tipo de comprobante en el header (junto al título) */
.k-tipo-select {
  min-width: 210px;
}
.k-serie-select {
  min-width: 130px;
}
.k-moneda-select {
  min-width: 160px;
}
@media (max-width: 599px) {
  .k-tipo-select,
  .k-serie-select,
  .k-moneda-select {
    width: 100%;
    min-width: 0;
  }
}

/* ---------- Fila cliente: Nombre (flex) + Doc/RUC (aparecen en Factura) ---------- */
.k-cliente-row {
  display: flex;
  align-items: flex-start;
  gap: 8px;
}
.k-nombre {
  flex: 1 1 auto;
  min-width: 0;
}
.k-docfields {
  display: flex;
  gap: 8px;
  flex-shrink: 0;
}
.k-doc-tipo {
  width: 110px;
}
.k-doc-num {
  width: 150px;
}
/* RUC = 11 dígitos + botón de búsqueda: necesita más ancho que el DNI. */
.k-doc-num--ruc {
  width: 210px;
}
/* Animación "líquida": al cambiar a Factura, los campos ganan ancho suavemente
   (y el Nombre se encoge para darles espacio). overflow oculto SOLO durante la
   transición para no cortar el aro de foco cuando ya están abiertos. */
.k-liquid-enter-active,
.k-liquid-leave-active {
  transition:
    max-width 0.45s cubic-bezier(0.22, 1, 0.36, 1),
    opacity 0.3s ease,
    transform 0.45s cubic-bezier(0.22, 1, 0.36, 1);
  overflow: hidden;
}
.k-liquid-enter-from,
.k-liquid-leave-to {
  max-width: 0;
  opacity: 0;
  transform: translateX(12px);
}
.k-liquid-enter-to,
.k-liquid-leave-from {
  /* Debe ser ≥ el ancho real de los campos (Doc 110 + gap 8 + RUC 210 = 328px)
     para que al quitar el tope al final NO salte a su tamaño real. */
  max-width: 340px;
  opacity: 1;
  transform: translateX(0);
}
@media (max-width: 599px) {
  .k-cliente-row {
    flex-direction: column;
  }
  .k-nombre,
  .k-docfields {
    width: 100%;
  }
  .k-doc-tipo,
  .k-doc-num {
    flex: 1;
    width: auto;
  }
  /* En móvil (apilado) el efecto es un fade + leve deslizamiento vertical. */
  .k-liquid-enter-from,
  .k-liquid-leave-to {
    max-width: 100%;
    transform: translateY(-6px);
  }
  .k-liquid-enter-to,
  .k-liquid-leave-from {
    max-width: 100%;
  }
}

/* ---------- Control segmentado ---------- */
.k-seg {
  display: flex;
  gap: 3px;
  padding: 3px;
  border-radius: var(--k-radius-sm);
  background: var(--k-surface-2);
}
.k-seg-btn {
  flex: 1;
  border: none;
  background: transparent;
  color: var(--k-muted);
  font-family: inherit;
  font-weight: 600;
  font-size: 13.5px;
  padding: 8px 12px;
  border-radius: calc(var(--k-radius-sm) - 3px);
  cursor: pointer;
  transition: color 0.15s ease, background 0.15s ease, box-shadow 0.15s ease;
}
.k-seg-btn:hover { color: var(--k-text); }
.k-seg-btn--on {
  background: var(--k-surface);
  color: var(--q-primary);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
}
.body--dark .k-seg-btn--on {
  background: var(--k-active-bg);
  color: var(--k-active-text);
  box-shadow: 0 0 0 1px color-mix(in srgb, var(--q-primary) 45%, transparent);
}

/* ---------- Ítems: tabla de facturación (cabecera + filas) ---------- */
.k-items-wrap {
  overflow-x: auto;
}
.k-items-head,
.k-item {
  display: grid;
  grid-template-columns:
    minmax(150px, 2.1fr) minmax(120px, 1.3fr) 58px 82px 66px minmax(80px, auto) 64px;
  gap: 6px;
  align-items: center;
  min-width: 600px;
}
.k-items-head {
  padding: 0 12px 8px;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 10.5px;
  text-transform: uppercase;
  letter-spacing: 0.4px;
  color: var(--k-muted);
}
/* Alinea el TEXTO del encabezado con el texto de los inputs de abajo. Los campos
   Quasar corren su contenido ~4px hacia adentro (padding del control), así que el
   encabezado necesita el mismo inset para que el título caiga justo sobre el valor. */
.k-items-head > div {
  padding: 0 4px;
}
.k-items-head .k-r {
  text-align: right;
}
.k-items-list {
  background: var(--k-surface-2);
  border-radius: var(--k-radius-sm);
  overflow: hidden;
}
.k-item {
  padding: 3px 12px;
  border-bottom: 1px solid var(--k-border);
}
.k-item:last-child {
  border-bottom: none;
}
/* Resalta la fila activa (fila en edición) */
.k-item:focus-within {
  background: color-mix(in srgb, var(--k-surface) 55%, var(--k-surface-2));
}
.k-c-imp {
  text-align: right;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-weight: 700;
  font-size: 14px;
  color: var(--k-text);
  white-space: nowrap;
}
.k-c-x {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 0;
}
.k-gratis-tag {
  display: inline-block;
  font-size: 11px;
  font-weight: 700;
  color: var(--q-primary);
  background: color-mix(in srgb, var(--q-primary) 16%, transparent);
  padding: 2px 9px;
  border-radius: 999px;
}
/* Celdas: inputs borderless compactos (sin caja individual) */
.k-item :deep(.q-field__control) {
  min-height: 42px;
  padding: 0 4px;
}
.k-item :deep(.q-field--borderless .q-field__control) {
  background: transparent;
}
/* Placeholder del select de producto (cuando no hay selección) */
.k-cell-ph {
  color: var(--k-muted);
}
/* Producto: si el nombre es largo, envuelve y crece (no se corta con ellipsis) */
.k-c-prod :deep(.q-field__native) {
  flex-wrap: wrap;
}
.k-c-prod :deep(.q-field__native > span) {
  white-space: normal;
  overflow: visible;
  text-overflow: clip;
  line-height: 1.35;
  padding: 6px 0;
}
/* Descripción: textarea que envuelve y crece en alto (no corre horizontal) */
.k-item :deep(.q-textarea textarea) {
  line-height: 1.35;
  padding: 9px 2px;
  resize: none;
  min-height: 24px;
}

/* Animación "líquida" al agregar / quitar una línea */
.k-item-liquid-enter-active,
.k-item-liquid-leave-active {
  transition:
    max-height 0.45s cubic-bezier(0.4, 0, 0.2, 1),
    opacity 0.3s ease,
    transform 0.45s cubic-bezier(0.34, 1.28, 0.5, 1),
    padding 0.45s cubic-bezier(0.4, 0, 0.2, 1);
  overflow: hidden;
}
.k-item-liquid-enter-from,
.k-item-liquid-leave-to {
  max-height: 0;
  opacity: 0;
  transform: translateY(-8px) scale(0.98);
  padding-top: 0;
  padding-bottom: 0;
}
.k-item-liquid-enter-to,
.k-item-liquid-leave-from {
  max-height: 90px;
  opacity: 1;
}
.k-item-liquid-move {
  transition: transform 0.4s cubic-bezier(0.4, 0, 0.2, 1);
}

/* ---------- Resumen ---------- */
@media (min-width: 1024px) {
  .k-summary-col {
    position: sticky;
    top: 72px; /* descuenta el header global fijo (~60px) + aire */
  }
}
.k-sum {
  font-variant-numeric: tabular-nums;
}
.k-sum-row {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  padding: 3px 0;
  font-size: 14px;
  color: var(--k-text);
}
.k-sum-row span:first-child { color: var(--k-muted); }
.k-sum-row span:last-child { font-family: 'JetBrains Mono', ui-monospace, monospace; }
.k-sum-muted span { color: var(--k-muted) !important; }
.k-total-row {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  font-size: 15px;
  font-weight: 700;
}
.k-total-amount {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 24px;
  font-weight: 800;
  letter-spacing: -0.5px;
  color: var(--k-text);
}
.k-emit {
  height: 52px;
  font-size: 16px;
  border-radius: 14px;
}
.k-banner {
  background: var(--k-surface-2);
  border-radius: var(--k-radius-sm);
  font-size: 13px;
}
.k-banner--ok {
  background: color-mix(in srgb, var(--q-positive) 12%, transparent);
}
.k-banner--pending {
  background: color-mix(in srgb, var(--q-warning) 14%, transparent);
}
.k-banner--err {
  background: color-mix(in srgb, var(--q-negative) 12%, transparent);
}
.k-wa-logo {
  width: 20px;
  height: 20px;
  margin-right: 8px;
}
</style>
