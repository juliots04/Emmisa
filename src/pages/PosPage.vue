<template>
  <q-page class="q-pa-md">
    <!-- ---------- Encabezado ---------- -->
    <div class="row items-center q-mb-md q-gutter-x-sm">
      <div class="text-h5">Venta rápida</div>
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
      <q-badge v-if="cart.length" color="primary" :label="`${itemCount} ítem(s)`" />
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
          <q-card-section class="q-gutter-sm">
            <q-input
              ref="searchInput"
              v-model="search"
              outlined
              dense
              clearable
              autofocus
              placeholder="Buscar por nombre, SKU o código de barras…  (Enter para agregar)"
              @keyup.enter="addByCode"
            >
              <template #prepend><q-icon name="qr_code_scanner" /></template>
              <template #append>
                <q-badge v-if="search" color="primary" outline :label="`${filtered.length}`" />
              </template>
            </q-input>

            <div v-if="loading" class="k-catalog-state">
              <q-spinner size="28px" color="primary" />
            </div>

            <!-- Sin productos en la empresa -->
            <div v-else-if="products.length === 0" class="k-catalog-state">
              <q-icon name="inventory_2" size="42px" class="k-state-icon" />
              <div class="text-subtitle1 q-mt-sm">Aún no tienes productos</div>
              <div class="text-caption text-grey q-mb-md">Agrega productos primero para poder venderlos.</div>
              <q-btn color="primary" icon="add" label="Ir a Productos" :to="{ name: 'products' }" />
            </div>

            <!-- Sin coincidencias de búsqueda -->
            <div v-else-if="filtered.length === 0" class="k-catalog-state">
              <q-icon name="search_off" size="42px" class="k-state-icon" />
              <div class="text-subtitle1 q-mt-sm">Sin resultados</div>
              <div class="text-caption text-grey">Prueba con otro término o código.</div>
            </div>

            <!-- Grilla de productos -->
            <div v-else class="k-grid">
              <button
                v-for="p in filtered"
                :key="p.id"
                type="button"
                class="k-tile"
                :class="{ 'k-tile--out': isAgotado(p) }"
                :disabled="isAgotado(p)"
                @click="addToCart(p)"
              >
                <div class="k-tile-top">
                  <span class="k-tile-name">{{ p.nombre }}</span>
                  <q-badge
                    v-if="stockLabel(p) !== null"
                    :color="stockColor(p)"
                    :label="stockLabel(p) ?? ''"
                    class="k-tile-stock"
                  />
                </div>
                <div class="k-tile-bottom">
                  <span class="k-tile-price">S/ {{ money(p.precio) }}</span>
                  <span v-if="p.sku" class="k-tile-sku">{{ p.sku }}</span>
                </div>
              </button>
            </div>
          </q-card-section>
        </q-card>
      </div>

      <!-- ============ Derecha: carrito y cobro ============ -->
      <div class="col-12 col-md-5">
        <q-card class="k-cart-col">
          <q-card-section>
            <!-- Tipo de comprobante -->
            <q-btn-toggle
              v-model="tipoDoc"
              class="full-width q-mb-md"
              no-caps
              spread
              unelevated
              toggle-color="primary"
              :options="tipoOptions"
            />

            <!-- Cliente -->
            <q-select
              :model-value="null"
              :options="customerOptions"
              option-label="denominacion"
              use-input
              clearable
              outlined
              dense
              hide-dropdown-icon
              input-debounce="200"
              label="Buscar cliente registrado"
              class="q-mb-sm"
              @filter="onCustomerFilter"
              @update:model-value="pickCustomer"
            >
              <template #prepend><q-icon name="person_search" /></template>
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
                <q-item><q-item-section class="text-grey">Sin coincidencias</q-item-section></q-item>
              </template>
            </q-select>

            <div class="row q-col-gutter-sm q-mb-sm">
              <div class="col">
                <q-input v-model="clienteNombre" outlined dense label="Nombre / Razón social" @update:model-value="onManualCliente" />
              </div>
              <div class="col-auto" style="width: 150px">
                <q-input
                  v-model="clienteDoc"
                  outlined
                  dense
                  :label="tipoDoc === '01' ? 'RUC *' : 'DNI (opcional)'"
                  :mask="tipoDoc === '01' ? '###########' : '########'"
                  :rules="docRules"
                  lazy-rules
                  @update:model-value="onManualCliente"
                />
              </div>
            </div>

            <q-separator class="q-my-md" />

            <!-- Carrito vacío -->
            <div v-if="cart.length === 0" class="k-cart-empty">
              <q-icon name="shopping_cart" size="34px" class="k-state-icon" />
              <div class="text-caption text-grey q-mt-xs">Toca un producto o escanea un código.</div>
            </div>

            <!-- Ítems del carrito -->
            <div v-else class="k-cart-list">
              <div v-for="item in cart" :key="item.productId" class="k-cart-row">
                <div class="k-cart-info">
                  <div class="k-cart-name">{{ item.nombre }}</div>
                  <div class="k-cart-unit">S/ {{ money(item.precio) }} c/u</div>
                </div>
                <div class="k-cart-qty">
                  <q-btn round dense flat icon="remove" size="sm" @click="decrement(item)" />
                  <span class="k-cart-count">
                    {{ item.cantidad }}
                    <q-popup-edit v-slot="scope" v-model.number="item.cantidad" :cover="false" auto-save>
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
                  <q-btn round dense flat icon="add" size="sm" @click="increment(item)" />
                </div>
                <div class="k-cart-line">S/ {{ money(item.precio * item.cantidad) }}</div>
                <q-btn round dense flat size="sm" icon="close" color="negative" @click="removeItem(item)" />
              </div>
            </div>

            <template v-if="cart.length">
              <q-separator class="q-my-md" />

              <!-- Descuento -->
              <div class="row items-center q-col-gutter-sm q-mb-sm">
                <div class="col-auto text-body2 text-grey">Descuento</div>
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
                      <q-btn-toggle
                        v-model="descuentoModo"
                        flat
                        dense
                        no-caps
                        size="sm"
                        toggle-color="primary"
                        :options="[
                          { label: 'S/', value: 'monto' },
                          { label: '%', value: 'pct' },
                        ]"
                      />
                    </template>
                  </q-input>
                </div>
              </div>

              <!-- Totales -->
              <div class="k-totals">
                <div class="row justify-between text-body2 text-grey">
                  <span>Subtotal</span><span>S/ {{ money(subtotalBruto.total) }}</span>
                </div>
                <div v-if="descuentoMonto > 0" class="row justify-between text-body2 text-negative">
                  <span>Descuento</span><span>− S/ {{ money(descuentoMonto) }}</span>
                </div>
                <div class="row justify-between text-body2 text-grey">
                  <span>Op. gravada</span><span>S/ {{ money(totals.gravado) }}</span>
                </div>
                <div class="row justify-between text-body2 text-grey">
                  <span>IGV (18%)</span><span>S/ {{ money(totals.igv) }}</span>
                </div>
                <q-separator class="q-my-sm" />
                <div class="row justify-between text-h6">
                  <span>Total</span><span>S/ {{ money(totals.total) }}</span>
                </div>
              </div>

              <!-- Forma de pago -->
              <div class="text-caption text-grey q-mt-md q-mb-xs">FORMA DE PAGO</div>
              <q-btn-toggle
                v-model="formaPago"
                class="full-width"
                no-caps
                spread
                unelevated
                toggle-color="primary"
                :options="pagoOptions"
              />

              <!-- Efectivo recibido + vuelto -->
              <template v-if="formaPago === 'efectivo'">
                <div class="row q-col-gutter-xs q-mt-sm">
                  <div v-for="d in denominaciones" :key="d.label" class="col">
                    <q-btn
                      class="full-width"
                      outline
                      no-caps
                      dense
                      size="sm"
                      color="primary"
                      :label="d.label"
                      @click="setEfectivo(d.value)"
                    />
                  </div>
                </div>
                <q-input
                  v-model.number="efectivoRecibido"
                  type="number"
                  outlined
                  dense
                  class="q-mt-sm"
                  label="Efectivo recibido"
                  min="0"
                >
                  <template #prepend><q-icon name="payments" /></template>
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
                class="full-width q-mt-md"
                color="primary"
                size="lg"
                icon="sell"
                :label="`Cobrar  ·  S/ ${money(totals.total)}`"
                :loading="emitting"
                :disable="cart.length === 0 || !caja"
                @click="cobrar"
              />
              <div v-if="!caja" class="row items-center justify-center q-mt-sm text-caption text-warning">
                <q-icon name="lock" size="14px" class="q-mr-xs" />
                Abre una caja para poder cobrar.
                <q-btn flat dense no-caps size="sm" color="primary" label="Ir a Caja" :to="{ name: 'cash' }" class="q-ml-xs" />
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

const tipoOptions = [
  { label: 'Boleta', value: '03' },
  { label: 'Factura', value: '01' },
]
const pagoOptions = [
  { label: 'Efectivo', value: 'efectivo', icon: 'payments' },
  { label: 'Yape', value: 'yape', icon: 'smartphone' },
  { label: 'Plin', value: 'plin', icon: 'smartphone' },
  { label: 'Tarjeta', value: 'tarjeta', icon: 'credit_card' },
  { label: 'Transf.', value: 'transferencia', icon: 'account_balance' },
]
const denominaciones = [
  { label: 'Exacto', value: -1 },
  { label: 'S/10', value: 10 },
  { label: 'S/20', value: 20 },
  { label: 'S/50', value: 50 },
  { label: 'S/100', value: 100 },
  { label: 'S/200', value: 200 },
]

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
function stockColor(p: Product): string {
  const s = stockOf(p) ?? 0
  if (s <= 0) return 'negative'
  if (s <= p.stock_minimo) return 'warning'
  return 'grey-7'
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

    const pagoLabel = pagoOptions.find((o) => o.value === formaPago.value)?.label ?? ''
    const vueltoTxt =
      formaPago.value === 'efectivo' && efectivoRecibido.value ? ` · Vuelto S/ ${money(vuelto.value)}` : ''
    notify({
      type: result.estado === 'aceptado' ? 'positive' : 'warning',
      message: result.mensaje ?? 'Comprobante emitido',
      caption: `${document.serie}-${String(document.correlativo).padStart(8, '0')} · ${pagoLabel} · S/ ${money(document.total)}${vueltoTxt}`,
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

/* ---------- Grilla de productos ---------- */
.k-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(148px, 1fr));
  gap: 10px;
}
.k-tile {
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  gap: 8px;
  min-height: 88px;
  padding: 12px 14px;
  border: 1px solid var(--k-border);
  border-radius: var(--k-radius-sm);
  background: var(--k-surface-2);
  color: var(--k-text);
  font-family: inherit;
  text-align: left;
  cursor: pointer;
  transition: border-color 0.15s ease, transform 0.05s ease;
}
.k-tile:hover {
  border-color: var(--k-border-hover);
}
.k-tile:active {
  transform: scale(0.98);
}
.k-tile--out {
  opacity: 0.5;
  cursor: not-allowed;
}
.k-tile-top {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 6px;
}
.k-tile-name {
  font-weight: 600;
  font-size: 13.5px;
  line-height: 1.25;
}
.k-tile-stock {
  flex-shrink: 0;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 10px;
}
.k-tile-bottom {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 6px;
}
.k-tile-price {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 13px;
  font-weight: 600;
  color: var(--k-text);
}
.k-tile-sku {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 10px;
  color: var(--k-muted);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

/* ---------- Columna de cobro (sticky en desktop) ---------- */
@media (min-width: 1024px) {
  .k-cart-col {
    position: sticky;
    top: 12px;
  }
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
}
.k-cart-row {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 0;
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
.k-cart-qty {
  display: flex;
  align-items: center;
  gap: 2px;
  flex-shrink: 0;
}
.k-cart-count {
  min-width: 26px;
  text-align: center;
  font-weight: 600;
  font-size: 13.5px;
  cursor: pointer;
  border-radius: 6px;
  padding: 2px 0;
}
.k-cart-count:hover {
  background: var(--k-surface-2);
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
</style>
