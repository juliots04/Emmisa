<template>
  <q-page class="q-pa-md">
    <!-- ---------- Encabezado ---------- -->
    <div class="row items-center q-mb-md q-gutter-x-sm">
      <div class="text-h5">
        Venta rápida
      </div>
      <q-chip
        :color="caja ? 'positive' : 'grey-7'"
        text-color="white"
        size="sm"
        :icon="caja ? 'point_of_sale' : 'lock'"
        :label="caja ? 'Caja abierta' : 'Caja cerrada'"
        class="k-caja-chip"
      >
        <q-tooltip v-if="!caja">
          No hay una caja abierta. Ábrela en <b>Caja</b> para arquear el efectivo del día.
        </q-tooltip>
      </q-chip>
      <q-space />
      <q-badge
        v-if="cart.length"
        color="primary"
        :label="`${itemCount} ítem(s)`"
      />
      <q-btn
        v-if="cart.length"
        flat
        dense
        no-caps
        size="sm"
        color="negative"
        icon="delete_sweep"
        label="Vaciar"
        @click="clearCart"
      />
    </div>

    <div class="row q-col-gutter-md">
      <!-- ============ Izquierda: catálogo ============ -->
      <div class="col-12 col-md-7">
        <q-card>
          <q-card-section class="q-gutter-md">
            <q-input
              ref="searchInput"
              v-model="search"
              outlined
              clearable
              autofocus
              placeholder="Buscar por nombre, SKU o código de barras…  (Enter para agregar)"
              @keyup.enter="addByCode"
            >
              <template #prepend>
                <q-icon name="qr_code_scanner" />
              </template>
              <template #append>
                <q-badge
                  v-if="search"
                  color="primary"
                  outline
                  :label="`${filtered.length}`"
                />
              </template>
            </q-input>

            <div
              v-if="loading"
              class="k-catalog-state"
            >
              <q-spinner
                size="28px"
                color="primary"
              />
            </div>

            <!-- Sin productos en la empresa -->
            <div
              v-else-if="products.length === 0"
              class="k-catalog-state"
            >
              <q-icon
                name="inventory_2"
                size="42px"
                class="k-state-icon"
              />
              <div class="text-subtitle1 q-mt-sm">
                Aún no tienes productos
              </div>
              <div class="text-caption text-muted q-mb-md">
                Agrega productos primero para poder venderlos.
              </div>
              <q-btn
                color="primary"
                unelevated
                icon="add"
                label="Ir a Productos"
                :to="{ name: 'products' }"
              />
            </div>

            <!-- Sin coincidencias de búsqueda -->
            <div
              v-else-if="filtered.length === 0"
              class="k-catalog-state"
            >
              <q-icon
                name="search_off"
                size="42px"
                class="k-state-icon"
              />
              <div class="text-subtitle1 q-mt-sm">
                Sin resultados
              </div>
              <div class="text-caption text-muted">
                Prueba con otro término o código.
              </div>
            </div>

            <!-- Grilla de productos -->
            <div
              v-else
              class="k-grid"
            >
              <button
                v-for="p in filtered"
                :key="p.id"
                type="button"
                class="k-tile"
                :class="{ 'k-tile--out': isAgotado(p) }"
                :disabled="isAgotado(p)"
                @click="addToCart(p)"
              >
                <div class="k-tile-head">
                  <span
                    class="k-tile-avatar"
                    :style="avatarStyle(p)"
                  >{{ initial(p) }}</span>
                  <span
                    v-if="stockLabel(p) !== null"
                    class="k-tile-stock"
                    :class="`k-stock--${stockTone(p)}`"
                  >
                    <i class="k-dot" />{{ stockLabel(p) }}
                  </span>
                </div>
                <span class="k-tile-name">{{ p.nombre }}</span>
                <div class="k-tile-foot">
                  <span class="k-tile-price">S/ {{ money(p.precio) }}</span>
                  <span
                    v-if="p.sku"
                    class="k-tile-sku"
                  >{{ p.sku }}</span>
                </div>
              </button>
            </div>
          </q-card-section>
        </q-card>
      </div>

      <!-- ============ Derecha: carrito y cobro ============ -->
      <div class="col-12 col-md-5">
        <q-card class="k-cart-col">
          <q-card-section class="k-cart-pad">
            <!-- Tipo de comprobante · control segmentado -->
            <div
              class="k-seg q-mb-md"
              role="group"
              aria-label="Tipo de comprobante"
            >
              <button
                v-for="o in tipoOptions"
                :key="o.value"
                type="button"
                class="k-seg-btn"
                :class="{ 'k-seg-btn--on': tipoDoc === o.value }"
                :aria-pressed="tipoDoc === o.value"
                @click="tipoDoc = o.value"
              >
                {{ o.label }}
              </button>
            </div>

            <!-- Cliente -->
            <q-select
              :model-value="null"
              :options="customerOptions"
              option-label="denominacion"
              use-input
              clearable
              outlined
              hide-dropdown-icon
              input-debounce="200"
              placeholder="Buscar cliente registrado"
              class="q-mb-sm"
              @filter="onCustomerFilter"
              @update:model-value="pickCustomer"
            >
              <template #prepend>
                <q-icon name="person_search" />
              </template>
              <template #option="scope">
                <q-item v-bind="scope.itemProps">
                  <q-item-section>
                    <q-item-label>{{ scope.opt.denominacion }}</q-item-label>
                    <q-item-label caption>
                      {{ scope.opt.num_doc || 'Sin documento' }}
                    </q-item-label>
                  </q-item-section>
                </q-item>
              </template>
              <template #no-option>
                <q-item>
                  <q-item-section class="text-muted">
                    Sin coincidencias
                  </q-item-section>
                </q-item>
              </template>
            </q-select>

            <div class="row q-col-gutter-sm q-mb-sm">
              <div class="col">
                <q-input
                  v-model="clienteNombre"
                  outlined
                  label="Nombre / Razón social"
                  @update:model-value="onManualCliente"
                />
              </div>
              <div
                class="col-auto"
                style="width: 150px"
              >
                <q-input
                  v-model="clienteDoc"
                  outlined
                  :label="tipoDoc === '01' ? 'RUC *' : 'DNI (opcional)'"
                  :mask="tipoDoc === '01' ? '###########' : '########'"
                  :rules="docRules"
                  lazy-rules
                  hide-bottom-space
                  @update:model-value="onManualCliente"
                />
              </div>
            </div>

            <q-separator class="q-my-md" />

            <!-- Carrito vacío -->
            <div
              v-if="cart.length === 0"
              class="k-cart-empty"
            >
              <q-icon
                name="shopping_cart"
                size="34px"
                class="k-state-icon"
              />
              <div class="text-caption text-muted q-mt-xs">
                Toca un producto o escanea un código.
              </div>
            </div>

            <!-- Ítems del carrito -->
            <div
              v-else
              class="k-cart-list"
            >
              <div
                v-for="item in cart"
                :key="item.productId"
                class="k-cart-row"
              >
                <div class="k-cart-info">
                  <div class="k-cart-name">
                    {{ item.nombre }}
                  </div>
                  <div class="k-cart-unit">
                    S/ {{ money(item.precio) }} c/u
                  </div>
                </div>
                <div class="k-stepper">
                  <q-btn
                    round
                    dense
                    flat
                    icon="remove"
                    size="sm"
                    @click="decrement(item)"
                  />
                  <span class="k-cart-count">
                    {{ item.cantidad }}
                    <q-popup-edit
                      v-slot="scope"
                      v-model.number="item.cantidad"
                      :cover="false"
                      auto-save
                    >
                      <q-input
                        v-model.number="scope.value"
                        type="number"
                        dense
                        autofocus
                        min="1"
                        :rules="[positive('Cantidad inválida')]"
                        style="width: 72px"
                        @keyup.enter="scope.value >= 1 && scope.set()"
                        @blur="scope.value >= 1 && scope.set()"
                      />
                    </q-popup-edit>
                  </span>
                  <q-btn
                    round
                    dense
                    flat
                    icon="add"
                    size="sm"
                    @click="increment(item)"
                  />
                </div>
                <div class="k-cart-line">
                  S/ {{ money(item.precio * item.cantidad) }}
                </div>
                <q-btn
                  round
                  dense
                  flat
                  size="sm"
                  icon="close"
                  color="negative"
                  @click="removeItem(item)"
                />
              </div>
            </div>

            <template v-if="cart.length">
              <q-separator class="q-my-md" />

              <!-- Descuento -->
              <div class="row items-center q-col-gutter-sm q-mb-sm">
                <div class="col-auto text-body2 text-muted">
                  Descuento
                </div>
                <div class="col">
                  <q-input
                    v-model.number="descuentoValor"
                    type="number"
                    dense
                    outlined
                    min="0"
                    placeholder="0"
                    :rules="descuentoRules"
                    hide-bottom-space
                  >
                    <template #append>
                      <div
                        class="k-seg k-seg--mini"
                        role="group"
                        aria-label="Tipo de descuento"
                      >
                        <button
                          v-for="m in descuentoModos"
                          :key="m.value"
                          type="button"
                          class="k-seg-btn"
                          :class="{ 'k-seg-btn--on': descuentoModo === m.value }"
                          :aria-pressed="descuentoModo === m.value"
                          @click="descuentoModo = m.value"
                        >
                          {{ m.label }}
                        </button>
                      </div>
                    </template>
                  </q-input>
                </div>
              </div>

              <!-- Totales -->
              <div class="k-totals">
                <div class="row justify-between text-body2 text-muted">
                  <span>Subtotal</span><span>S/ {{ money(subtotalBruto.total) }}</span>
                </div>
                <div
                  v-if="descuentoMonto > 0"
                  class="row justify-between text-body2 text-negative"
                >
                  <span>Descuento</span><span>− S/ {{ money(descuentoMonto) }}</span>
                </div>
                <div class="row justify-between text-body2 text-muted">
                  <span>Op. gravada</span><span>S/ {{ money(totals.gravado) }}</span>
                </div>
                <div class="row justify-between text-body2 text-muted">
                  <span>IGV (18%)</span><span>S/ {{ money(totals.igv) }}</span>
                </div>
                <q-separator class="q-my-sm" />
                <div class="row justify-between items-baseline k-total-row">
                  <span>Total</span><span class="k-total-amount">S/ {{ money(totals.total) }}</span>
                </div>
              </div>

              <!-- Forma de pago · logos de marca -->
              <div class="k-section-label">
                Forma de pago
              </div>
              <div
                class="k-pay-grid"
                role="group"
                aria-label="Forma de pago"
              >
                <button
                  v-for="m in metodosPago"
                  :key="m.value"
                  type="button"
                  class="k-pay"
                  :class="{ 'k-pay--on': formaPago === m.value }"
                  :aria-pressed="formaPago === m.value"
                  @click="formaPago = m.value"
                >
                  <img
                    :src="m.logo"
                    alt=""
                    class="k-pay-logo"
                    width="30"
                    height="30"
                  >
                  <span class="k-pay-label">{{ m.label }}</span>
                </button>
              </div>

              <!-- Efectivo recibido + vuelto -->
              <template v-if="formaPago === 'efectivo'">
                <div class="k-denoms q-mt-sm">
                  <button
                    v-for="d in denominaciones"
                    :key="d.label"
                    type="button"
                    class="k-denom"
                    @click="setEfectivo(d.value)"
                  >
                    {{ d.label }}
                  </button>
                </div>
                <q-input
                  v-model.number="efectivoRecibido"
                  type="number"
                  outlined
                  class="q-mt-sm"
                  placeholder="Efectivo recibido"
                  min="0"
                >
                  <template #prepend>
                    <q-icon name="payments" />
                  </template>
                </q-input>
                <div
                  v-if="efectivoRecibido !== null && efectivoRecibido > 0"
                  class="row justify-between q-mt-sm text-subtitle1"
                  :class="vuelto >= 0 ? 'text-positive' : 'text-negative'"
                >
                  <span>{{ vuelto >= 0 ? 'Vuelto' : 'Falta' }}</span>
                  <span>S/ {{ money(Math.abs(vuelto)) }}</span>
                </div>
              </template>

              <q-btn
                class="full-width q-mt-md k-cobrar"
                color="primary"
                unelevated
                size="lg"
                icon="sell"
                :label="`Cobrar  ·  S/ ${money(totals.total)}`"
                :loading="emitting"
                :disable="cart.length === 0 || !caja"
                @click="cobrar"
              />
              <div
                v-if="!caja"
                class="row items-center justify-center q-mt-sm text-caption text-warning"
              >
                <q-icon
                  name="lock"
                  size="14px"
                  class="q-mr-xs"
                />
                Abre una caja para poder cobrar.
                <q-btn
                  flat
                  dense
                  no-caps
                  size="sm"
                  color="primary"
                  label="Ir a Caja"
                  :to="{ name: 'cash' }"
                  class="q-ml-xs"
                />
              </div>
            </template>
          </q-card-section>
        </q-card>
      </div>
    </div>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { QInput } from 'quasar'
import { useCompanyStore } from '@/stores/company'
import { listProducts } from '@/modules/products/products.api'
import { listCustomers } from '@/modules/customers/customers.api'
import { listStock } from '@/modules/inventory/inventory.api'
import { getOpenSession, type CashSession } from '@/modules/cash/cash.api'
import { emitirComprobante } from '@/modules/documents/documents.api'
import { printTicket } from '@/lib/ticket'
import { computeTotals, round2 } from '@/modules/sunat'
import { firstError, ruc, dni, nonNegative, maxVal, positive, required, type Rule } from '@/lib/validation'
import { notify } from '@/lib/toast'
import type { Product, Customer, TipoDoc } from '@/types'

interface CartItem {
  productId: string
  nombre: string
  precio: number
  cantidad: number
}
type FormaPago = 'efectivo' | 'yape' | 'plin' | 'tarjeta' | 'transferencia'

const company = useCompanyStore()

const tipoOptions: { label: string; value: TipoDoc }[] = [
  { label: 'Boleta', value: '03' },
  { label: 'Factura', value: '01' },
]
// Métodos de pago con logo de marca (en /public/pay). Se usan para el selector
// y para etiquetar el comprobante/ticket al cobrar.
const metodosPago: { value: FormaPago; label: string; logo: string }[] = [
  { value: 'efectivo', label: 'Efectivo', logo: '/pay/efectivo.svg' },
  { value: 'yape', label: 'Yape', logo: '/pay/yape.svg' },
  { value: 'plin', label: 'Plin', logo: '/pay/plin.svg' },
  { value: 'tarjeta', label: 'Tarjeta', logo: '/pay/tarjeta.svg' },
  { value: 'transferencia', label: 'Transf.', logo: '/pay/transferencia.svg' },
]
const descuentoModos: { label: string; value: 'monto' | 'pct' }[] = [
  { label: 'S/', value: 'monto' },
  { label: '%', value: 'pct' },
]
const denominaciones = [
  { label: 'Exacto', value: -1 },
  { label: 'S/10', value: 10 },
  { label: 'S/20', value: 20 },
  { label: 'S/50', value: 50 },
  { label: 'S/100', value: 100 },
  { label: 'S/200', value: 200 },
]
// Paleta suave para el avatar de cada producto (determinística por nombre).
const avatarPalette = ['#6366f1', '#0ea5e9', '#22c55e', '#f59e0b', '#ec4899', '#8b5cf6', '#14b8a6', '#ef4444']

const products = ref<Product[]>([])
const stockByProduct = ref<Map<string, number>>(new Map())
const customers = ref<Customer[]>([])
const customerOptions = ref<Customer[]>([])
const cajaSession = ref<CashSession | null>(null)
const caja = computed(() => !!cajaSession.value)
const loading = ref(false)

const search = ref('')
const searchInput = ref<QInput | null>(null)
const cart = ref<CartItem[]>([])
const tipoDoc = ref<TipoDoc>('03')

const clienteNombre = ref('Cliente varios')
const clienteDoc = ref('')
const selectedCustomerId = ref<string | null>(null)

const descuentoModo = ref<'monto' | 'pct'>('monto')
const descuentoValor = ref<number>(0)

const formaPago = ref<FormaPago>('efectivo')
const efectivoRecibido = ref<number | null>(null)

const emitting = ref(false)
// Llave de idempotencia: estable durante un intento de cobro (reintentos incluidos).
const ventaKey = ref<string | null>(null)

/* ---------------- Búsqueda / catálogo ---------------- */
const filtered = computed(() => {
  const q = (search.value || '').trim().toLowerCase()
  const activos = products.value.filter((p) => p.activo !== false)
  if (!q) return activos
  return activos.filter(
    (p) =>
      p.nombre.toLowerCase().includes(q) ||
      (p.sku || '').toLowerCase().includes(q) ||
      (p.barcode || '').toLowerCase().includes(q),
  )
})

function stockOf(p: Product): number | null {
  if (!p.controla_stock) return null
  const v = stockByProduct.value.get(p.id)
  return v === undefined ? null : v
}
function isAgotado(p: Product): boolean {
  const s = stockOf(p)
  return s !== null && s <= 0
}
function stockLabel(p: Product): string | null {
  const s = stockOf(p)
  if (s === null) return null
  return s <= 0 ? 'Agotado' : `${s} und`
}
function stockTone(p: Product): 'ok' | 'low' | 'out' {
  const s = stockOf(p) ?? 0
  if (s <= 0) return 'out'
  if (s <= p.stock_minimo) return 'low'
  return 'ok'
}

/* ---------------- Avatar del producto ---------------- */
function initial(p: Product): string {
  return (p.nombre || '?').trim().charAt(0).toUpperCase()
}
function avatarStyle(p: Product): Record<string, string> {
  let h = 0
  for (let i = 0; i < p.id.length; i++) h = (h * 31 + p.id.charCodeAt(i)) >>> 0
  const c = avatarPalette[h % avatarPalette.length]
  return { background: `color-mix(in srgb, ${c} 16%, transparent)`, color: c }
}

/* ---------------- Carrito ---------------- */
const itemCount = computed(() => cart.value.reduce((n, i) => n + i.cantidad, 0))

function addToCart(p: Product) {
  const existing = cart.value.find((i) => i.productId === p.id)
  const nextQty = (existing?.cantidad ?? 0) + 1
  const stock = stockOf(p)
  if (stock !== null && nextQty > stock) {
    notify({ type: 'warning', message: `Stock insuficiente de "${p.nombre}" (quedan ${stock}).` })
    return
  }
  if (existing) existing.cantidad = nextQty
  else cart.value.push({ productId: p.id, nombre: p.nombre, precio: Number(p.precio), cantidad: 1 })
}

/** Agrega por código exacto (barcode/SKU) o el primer resultado. Soporta lector de código de barras. */
function addByCode() {
  const q = (search.value || '').trim().toLowerCase()
  if (!q) return
  const exact = products.value.find(
    (p) => (p.barcode || '').toLowerCase() === q || (p.sku || '').toLowerCase() === q,
  )
  const target = exact ?? filtered.value[0]
  if (target) {
    addToCart(target)
    search.value = ''
    searchInput.value?.focus()
  } else {
    notify({ type: 'warning', message: 'No se encontró un producto con ese código.' })
  }
}

function increment(item: CartItem) {
  const p = products.value.find((x) => x.id === item.productId)
  if (p) addToCart(p)
  else item.cantidad += 1
}
function decrement(item: CartItem) {
  if (item.cantidad <= 1) removeItem(item)
  else item.cantidad -= 1
}
function removeItem(item: CartItem) {
  cart.value = cart.value.filter((i) => i.productId !== item.productId)
}
function clearCart() {
  cart.value = []
  descuentoValor.value = 0
  efectivoRecibido.value = null
}

/* ---------------- Descuento y totales ---------------- */
// Subtotal bruto (precios con IGV incluido, antes de descuento).
const subtotalBruto = computed(() =>
  computeTotals(cart.value.map((i) => ({ cantidad: i.cantidad, precioUnitario: i.precio }))),
)

// Monto de descuento, acotado a [0, subtotal].
const descuentoMonto = computed(() => {
  const base = subtotalBruto.value.total
  const raw =
    descuentoModo.value === 'pct'
      ? (base * (descuentoValor.value || 0)) / 100
      : descuentoValor.value || 0
  return round2(Math.min(Math.max(raw, 0), base))
})

// Factor a aplicar sobre cada precio unitario para reflejar el descuento en el comprobante.
const factor = computed(() => {
  const base = subtotalBruto.value.total
  return base > 0 ? (base - descuentoMonto.value) / base : 1
})

// Líneas con el precio ya ajustado por descuento (lo que se emite y se guarda).
const emitLines = computed(() =>
  cart.value.map((i) => ({
    productId: i.productId,
    descripcion: i.nombre,
    cantidad: i.cantidad,
    precioUnitario: round2(i.precio * factor.value),
  })),
)

// Totales netos (después de descuento) para mostrar y emitir.
const totals = computed(() =>
  computeTotals(emitLines.value.map((i) => ({ cantidad: i.cantidad, precioUnitario: i.precioUnitario }))),
)

const vuelto = computed(() => round2((efectivoRecibido.value || 0) - totals.value.total))

// Reglas coherentes con el resto de la app (validation.ts).
const docRules = computed<Rule[]>(() =>
  tipoDoc.value === '01' ? [required('RUC obligatorio'), ruc] : clienteDoc.value ? [dni] : [],
)
const descuentoRules = computed<Rule[]>(() =>
  descuentoModo.value === 'pct'
    ? [nonNegative(), maxVal(100, 'Máximo 100%')]
    : [nonNegative(), maxVal(subtotalBruto.value.total, 'Descuento mayor que el total')],
)

/* ---------------- Cliente ---------------- */
function onCustomerFilter(val: string, update: (fn: () => void) => void) {
  update(() => {
    const needle = val.toLowerCase()
    customerOptions.value = customers.value.filter(
      (c) => c.denominacion.toLowerCase().includes(needle) || (c.num_doc || '').includes(needle),
    )
  })
}
function pickCustomer(c: Customer | null) {
  if (!c) return
  selectedCustomerId.value = c.id
  clienteNombre.value = c.denominacion
  clienteDoc.value = c.num_doc || ''
  if ((c.num_doc || '').length === 11) tipoDoc.value = '01'
}
function onManualCliente() {
  // Si el usuario edita a mano, deja de estar ligado a un cliente registrado.
  selectedCustomerId.value = null
}

/* ---------------- Cobro ---------------- */
function money(n: number): string {
  return Number(n || 0).toFixed(2)
}
function setEfectivo(value: number) {
  efectivoRecibido.value = value === -1 ? totals.value.total : value
}

async function cobrar() {
  if (!company.current || cart.value.length === 0) return

  if (!cajaSession.value) {
    notify.warning('Abre una caja para poder cobrar', 'La venta debe registrarse en una caja abierta.')
    return
  }

  const esFactura = tipoDoc.value === '01'
  const doc = clienteDoc.value.trim()

  const docErr = firstError(doc, docRules.value)
  if (docErr) {
    notify({ type: 'warning', message: `Cliente: ${docErr}` })
    return
  }
  const descErr = firstError(descuentoValor.value, descuentoRules.value)
  if (descErr) {
    notify({ type: 'warning', message: `Descuento: ${descErr}` })
    return
  }
  if (formaPago.value === 'efectivo' && efectivoRecibido.value && vuelto.value < 0) {
    notify({ type: 'warning', message: 'El efectivo recibido es menor al total.' })
    return
  }

  // Llave estable por intento: si el cobro falla a medias, un reintento no duplica la venta.
  if (!ventaKey.value) ventaKey.value = crypto.randomUUID()
  const esEfectivo = formaPago.value === 'efectivo'

  emitting.value = true
  try {
    const { document, result } = await emitirComprobante({
      companyId: company.current.id,
      tipoDoc: tipoDoc.value,
      customerId: selectedCustomerId.value,
      cliente: {
        tipoDoc: esFactura ? '6' : doc.length === 8 ? '1' : '0',
        numDoc: esFactura || doc.length === 8 ? doc : undefined,
        denominacion: clienteNombre.value.trim() || 'Cliente varios',
      },
      items: emitLines.value,
      formaPago: formaPago.value,
      montoRecibido: esEfectivo ? efectivoRecibido.value : null,
      vuelto: esEfectivo && efectivoRecibido.value ? vuelto.value : null,
      cashSessionId: cajaSession.value.id,
      idempotencyKey: ventaKey.value,
    })

    const pagoLabel = metodosPago.find((o) => o.value === formaPago.value)?.label ?? ''
    const vueltoTxt =
      formaPago.value === 'efectivo' && efectivoRecibido.value ? ` · Vuelto S/ ${money(vuelto.value)}` : ''
    notify({
      type: result.estado === 'aceptado' ? 'positive' : 'warning',
      message: result.mensaje ?? 'Comprobante emitido',
      caption: `${document.serie}-${String(document.correlativo).padStart(8, '0')} · ${pagoLabel} · S/ ${money(document.total)}${vueltoTxt}`,
    })

    // Ticket térmico (best-effort; no bloquea la venta si el popup está bloqueado).
    printTicket({
      empresa: {
        razon_social: company.current.razon_social,
        ruc: company.current.ruc,
        direccion: company.current.direccion,
      },
      doc: document,
      cliente: { denominacion: clienteNombre.value.trim() || 'Cliente varios', numDoc: clienteDoc.value || null },
      lines: emitLines.value.map((l) => ({ descripcion: l.descripcion, cantidad: l.cantidad, precioUnitario: l.precioUnitario })),
      formaPago: pagoLabel,
      efectivo: esEfectivo ? efectivoRecibido.value : null,
      vuelto: esEfectivo && efectivoRecibido.value ? vuelto.value : null,
    })

    // Reset para la siguiente venta.
    clearCart()
    ventaKey.value = null
    clienteDoc.value = ''
    clienteNombre.value = 'Cliente varios'
    selectedCustomerId.value = null
    formaPago.value = 'efectivo'
    descuentoModo.value = 'monto'
    searchInput.value?.focus()
    void refreshStock()
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    emitting.value = false
  }
}

/* ---------------- Carga inicial ---------------- */
async function refreshStock() {
  if (!company.current) return
  try {
    const rows = await listStock(company.current.id)
    const map = new Map<string, number>()
    for (const r of rows) map.set(r.product_id, (map.get(r.product_id) ?? 0) + r.cantidad)
    stockByProduct.value = map
  } catch {
    // El stock es informativo; si falla (sin almacenes) no bloquea la venta.
  }
}

onMounted(async () => {
  if (!company.current) return
  loading.value = true
  try {
    const [prods, custs, session] = await Promise.all([
      listProducts(company.current.id),
      listCustomers(company.current.id).catch(() => [] as Customer[]),
      getOpenSession(company.current.id).catch(() => null),
    ])
    products.value = prods
    customers.value = custs
    customerOptions.value = custs
    cajaSession.value = session
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
  void refreshStock()
})
</script>

<style scoped>
.k-caja-chip {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
}

/* ---------- Estados vacíos / carga ---------- */
.k-catalog-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 40px 16px;
}
.k-state-icon {
  color: var(--k-muted);
  opacity: 0.7;
}

/* ---------- Grilla de productos (borderless · soft-fill) ---------- */
.k-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
  gap: 12px;
}
.k-tile {
  display: flex;
  flex-direction: column;
  gap: 10px;
  min-height: 110px;
  padding: 14px;
  border: none;
  border-radius: var(--k-radius-sm);
  background: var(--k-surface-2);
  color: var(--k-text);
  font-family: inherit;
  text-align: left;
  cursor: pointer;
  transition: box-shadow 0.15s ease, transform 0.08s ease, background 0.15s ease;
}
.k-tile:hover {
  background: color-mix(in srgb, var(--k-surface-2) 60%, var(--k-surface));
  box-shadow: 0 0 0 1px var(--k-border-hover), 0 6px 18px rgba(0, 0, 0, 0.06);
  transform: translateY(-1px);
}
.k-tile:active {
  transform: scale(0.98);
}
.k-tile:focus-visible {
  outline: none;
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--q-primary) 70%, transparent);
}
.k-tile--out {
  opacity: 0.5;
  cursor: not-allowed;
}
.k-tile-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 6px;
}
.k-tile-avatar {
  width: 30px;
  height: 30px;
  border-radius: 9px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 700;
  font-size: 14px;
  flex-shrink: 0;
}
.k-tile-name {
  font-weight: 600;
  font-size: 13.5px;
  line-height: 1.3;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.k-tile-foot {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 6px;
  margin-top: auto;
}
.k-tile-price {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 14px;
  font-weight: 700;
  color: var(--q-primary);
}
.k-tile-sku {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 10px;
  color: var(--k-muted);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
/* Stock: punto de color + texto (sutil, sin pill pesado) */
.k-tile-stock {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 10.5px;
  color: var(--k-muted);
  white-space: nowrap;
}
.k-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: currentColor;
  flex-shrink: 0;
}
.k-stock--ok { color: var(--k-muted); }
.k-stock--ok .k-dot { background: var(--q-positive); }
.k-stock--low { color: var(--q-warning); }
.k-stock--out { color: var(--q-negative); }

/* ---------- Columna de cobro (sticky en desktop) ---------- */
.k-cart-pad {
  padding: 20px;
}
@media (min-width: 1024px) {
  .k-cart-col {
    position: sticky;
    top: 12px;
  }
}

/* ---------- Control segmentado (Boleta/Factura, S//%) ---------- */
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
  padding: 7px 12px;
  border-radius: calc(var(--k-radius-sm) - 3px);
  cursor: pointer;
  transition: color 0.15s ease, background 0.15s ease, box-shadow 0.15s ease;
}
.k-seg-btn:hover {
  color: var(--k-text);
}
.k-seg-btn:focus-visible {
  outline: none;
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--q-primary) 70%, transparent);
}
.k-seg-btn--on {
  background: var(--k-surface);
  color: var(--q-primary);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
}
/* En oscuro, --k-surface es más OSCURO que el riel (--k-surface-2): el segmento
   activo se hunde y la sombra desaparece. Usamos el tinte índigo + aro (mismo
   patrón que .k-pay--on) para que Boleta/Factura se distinga con claridad. */
.body--dark .k-seg-btn--on {
  background: var(--k-active-bg);
  color: var(--k-active-text);
  box-shadow: 0 0 0 1px color-mix(in srgb, var(--q-primary) 45%, transparent);
}
/* Variante mini para el sufijo S//% del descuento */
.k-seg--mini {
  padding: 2px;
  gap: 2px;
}
.k-seg--mini .k-seg-btn {
  font-size: 12px;
  padding: 3px 9px;
  min-width: 34px;
}

/* ---------- Carrito ---------- */
.k-cart-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  padding: 28px 16px;
}
.k-cart-list {
  max-height: 42vh;
  overflow-y: auto;
  margin: 0 -4px;
  padding: 0 4px;
}
.k-cart-row {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 0;
  border-bottom: 1px solid var(--k-border);
}
.k-cart-info {
  flex: 1 1 auto;
  min-width: 0;
}
.k-cart-name {
  font-weight: 600;
  font-size: 13.5px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.k-cart-unit {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  color: var(--k-muted);
}
.k-stepper {
  display: flex;
  align-items: center;
  gap: 2px;
  flex-shrink: 0;
  background: var(--k-surface-2);
  border-radius: 999px;
  padding: 2px;
}
.k-cart-count {
  min-width: 26px;
  text-align: center;
  font-weight: 600;
  font-size: 13.5px;
  cursor: pointer;
}
.k-cart-line {
  min-width: 68px;
  text-align: right;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 13px;
  flex-shrink: 0;
}
.k-totals {
  font-variant-numeric: tabular-nums;
}
.k-total-row {
  font-size: 15px;
  font-weight: 700;
}
.k-total-amount {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 22px;
  font-weight: 800;
  letter-spacing: -0.5px;
}

/* ---------- Selección de forma de pago (logos de marca) ---------- */
.k-section-label {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.4px;
  color: var(--k-muted);
  margin: 16px 0 8px;
}
.k-pay-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(72px, 1fr));
  gap: 8px;
}
.k-pay {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  padding: 10px 6px;
  border: none;
  border-radius: var(--k-radius-sm);
  background: var(--k-surface-2);
  color: var(--k-muted);
  font-family: inherit;
  cursor: pointer;
  transition: box-shadow 0.15s ease, background 0.15s ease, color 0.15s ease;
}
.k-pay:hover {
  color: var(--k-text);
}
.k-pay:focus-visible {
  outline: none;
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--q-primary) 70%, transparent);
}
.k-pay--on {
  background: var(--k-active-bg);
  color: var(--k-active-text);
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--q-primary) 70%, transparent);
}
.k-pay-logo {
  border-radius: 9px;
  display: block;
}
.k-pay-label {
  font-size: 11.5px;
  font-weight: 600;
}

/* ---------- Chips de denominación (borderless) ---------- */
.k-denoms {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}
.k-denom {
  border: none;
  background: var(--k-surface-2);
  color: var(--k-text);
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 12.5px;
  font-weight: 600;
  padding: 7px 14px;
  border-radius: 999px;
  cursor: pointer;
  transition: box-shadow 0.15s ease, background 0.15s ease;
}
.k-denom:hover {
  box-shadow: 0 0 0 1px var(--k-border-hover);
  background: color-mix(in srgb, var(--k-surface-2) 60%, var(--k-surface));
}
.k-denom:focus-visible {
  outline: none;
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--q-primary) 70%, transparent);
}

/* ---------- Botón cobrar ---------- */
.k-cobrar {
  height: 52px;
  font-size: 16px;
  border-radius: 14px;
}
</style>
