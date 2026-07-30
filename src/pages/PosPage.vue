<template>
  <q-page class="q-pa-md">
    <!-- ---------- Encabezado ---------- -->
    <div
      class="row items-center q-mb-md q-gutter-x-sm"
      style="min-height: 48px"
    >
      <div class="text-h5">
        Venta rápida
      </div>
      <span
        class="k-status"
        :class="caja ? 'k-status--on' : 'k-status--off'"
      >
        <i class="k-status-dot" />{{ caja ? 'Caja abierta' : 'Caja cerrada' }}
        <q-tooltip v-if="!caja">
          No hay una caja abierta. Ábrela en <b>Caja</b> para arquear el efectivo del día.
        </q-tooltip>
      </span>
      <q-space />
      <!-- Configuración de impresión (predeterminado por dispositivo) -->
      <q-btn
        flat
        dense
        round
        icon="settings"
        color="grey-7"
      >
        <q-tooltip>Configuración de impresión</q-tooltip>
        <q-menu
          anchor="bottom right"
          self="top right"
        >
          <div class="k-print-menu">
            <div class="k-print-menu-title">
              Ancho del ticket
            </div>
            <div class="text-caption text-muted q-mb-sm">
              Predeterminado de esta caja
            </div>
            <q-list dense>
              <q-item
                v-for="opt in ticketWidthOptions"
                :key="opt.value"
                v-close-popup
                clickable
                @click="ticketWidth = opt.value"
              >
                <q-item-section avatar>
                  <q-icon
                    :name="ticketWidth === opt.value ? 'radio_button_checked' : 'radio_button_unchecked'"
                    :color="ticketWidth === opt.value ? 'primary' : 'grey'"
                  />
                </q-item-section>
                <q-item-section>
                  <q-item-label>{{ opt.label }}</q-item-label>
                  <q-item-label caption>
                    {{ opt.hint }}
                  </q-item-label>
                </q-item-section>
              </q-item>
            </q-list>
          </div>
        </q-menu>
      </q-btn>
    </div>

    <div class="row q-col-gutter-md">
      <!-- ============ Izquierda: catálogo ============ -->
      <div class="col-12 col-md-7">
        <!-- ===== Filtros (sección propia) ===== -->
        <q-card class="q-mb-md">
          <q-card-section class="k-filters-card">
            <div class="row items-center q-mb-sm k-filters-head">
              <q-icon
                name="tune"
                size="18px"
                class="text-muted q-mr-xs"
              />
              <div class="text-subtitle2">
                Filtros
              </div>
              <q-space />
              <q-btn
                v-if="hayFiltros"
                flat
                dense
                no-caps
                size="sm"
                color="primary"
                icon="filter_alt_off"
                label="Limpiar"
                @click="limpiarFiltros"
              />
            </div>

            <div class="row q-col-gutter-sm">
              <q-select
                v-model="sortBy"
                :options="sortOptions"
                outlined
                dense
                emit-value
                map-options
                options-dense
                label="Ordenar por"
                class="col-12 col-sm-4"
              >
                <template #prepend>
                  <q-icon
                    name="swap_vert"
                    size="18px"
                  />
                </template>
              </q-select>
              <q-select
                v-model="tipoFilter"
                :options="tipoFilterOptions"
                outlined
                dense
                emit-value
                map-options
                options-dense
                label="Tipo"
                class="col-6 col-sm-4"
              >
                <template #prepend>
                  <q-icon
                    name="sell"
                    size="18px"
                  />
                </template>
              </q-select>
              <q-select
                v-model="stockFilter"
                :options="stockOptions"
                outlined
                dense
                emit-value
                map-options
                options-dense
                label="Estado de stock"
                class="col-6 col-sm-4"
              >
                <template #prepend>
                  <q-icon
                    name="inventory_2"
                    size="18px"
                  />
                </template>
              </q-select>
            </div>

            <div class="row q-col-gutter-sm q-mt-xs">
              <div class="col-12 col-sm-6">
                <div class="k-range">
                  <span class="k-range-label">Precio S/</span>
                  <q-input
                    v-model.number="precioMin"
                    outlined
                    dense
                    type="number"
                    placeholder="mín"
                    class="k-range-in"
                  />
                  <span class="k-range-sep">–</span>
                  <q-input
                    v-model.number="precioMax"
                    outlined
                    dense
                    type="number"
                    placeholder="máx"
                    class="k-range-in"
                  />
                </div>
              </div>
              <div class="col-12 col-sm-6">
                <div class="k-range">
                  <span class="k-range-label">Stock</span>
                  <q-input
                    v-model.number="stockMin"
                    outlined
                    dense
                    type="number"
                    placeholder="mín"
                    class="k-range-in"
                  />
                  <span class="k-range-sep">–</span>
                  <q-input
                    v-model.number="stockMax"
                    outlined
                    dense
                    type="number"
                    placeholder="máx"
                    class="k-range-in"
                  />
                </div>
              </div>
            </div>
          </q-card-section>
        </q-card>

        <!-- ===== Catálogo ===== -->
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
                <div class="k-tile-media">
                  <img
                    :src="p.imagen_url || '/product-placeholder.svg'"
                    :alt="p.nombre"
                    class="k-tile-photo"
                    loading="lazy"
                    @error="onImgError"
                  >
                  <span
                    v-if="stockLabel(p) !== null"
                    class="k-tile-count"
                    :class="[`k-count--${stockTone(p)}`, { 'k-count--reserved': cartQtyOf(p.id) > 0 }]"
                  >
                    <span
                      class="k-count-dot"
                      aria-hidden="true"
                    />
                    <span class="k-count-num">{{ stockBadge(p) }}</span>
                    <q-tooltip v-if="cartQtyOf(p.id) > 0">
                      {{ cartQtyOf(p.id) }} en el carrito · {{ stockOf(p) }} en stock
                    </q-tooltip>
                  </span>
                </div>
                <div class="k-tile-body">
                  <span class="k-tile-name">{{ p.nombre }}</span>
                  <div class="k-tile-foot">
                    <span class="k-tile-price">S/ {{ money(p.precio) }}</span>
                    <span
                      v-if="p.sku"
                      class="k-tile-sku"
                    >{{ p.sku }}</span>
                  </div>
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
            <!-- Header del panel: título + conteo + vaciar -->
            <div class="row items-center q-mb-md">
              <q-icon
                name="receipt_long"
                size="20px"
                class="q-mr-sm text-muted"
              />
              <div class="text-subtitle1">
                Comprobante
              </div>
              <span
                v-if="cart.length"
                class="k-count q-ml-sm"
              >{{ itemCount }}</span>
              <q-space />
              <button
                v-if="cart.length"
                type="button"
                class="k-clear"
                @click="clearCart"
              >
                <q-icon
                  name="delete_sweep"
                  size="15px"
                />
                Vaciar
              </button>
            </div>

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
                        @keyup.enter="commitQty(item, scope)"
                        @blur="commitQty(item, scope)"
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
                  <span>Op. gravada</span><span>S/ {{ money(totalsByAfectacion.gravado) }}</span>
                </div>
                <div class="row justify-between text-body2 text-muted">
                  <span>IGV (18%)</span><span>S/ {{ money(totalsByAfectacion.igv) }}</span>
                </div>
                <q-separator class="q-my-sm" />
                <div class="row justify-between items-baseline k-total-row">
                  <span>Total</span><span class="k-total-amount">S/ {{ money(totals.total) }}</span>
                </div>
              </div>

              <q-btn
                class="full-width q-mt-md k-cobrar"
                color="primary"
                unelevated
                size="lg"
                icon="arrow_forward"
                :label="`Continuar  ·  S/ ${money(totals.total)}`"
                :disable="cart.length === 0 || !caja"
                @click="showCheckout = true"
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

            <div
              v-if="lastSaleDoc && !cart.length"
              class="row justify-center q-mt-md"
            >
              <q-btn
                color="green-7"
                unelevated
                no-caps
                @click="whatsappUltima"
              >
                <img
                  src="/whatsapp.svg"
                  alt=""
                  class="k-wa-logo"
                >
                Enviar por WhatsApp
              </q-btn>
            </div>
          </q-card-section>
        </q-card>
      </div>
    </div>

    <!-- ============ Modal de cobro ============ -->
    <q-dialog v-model="showCheckout">
      <q-card class="k-checkout">
        <q-card-section class="row items-center q-pb-none">
          <div class="text-h6">
            Cobrar
          </div>
          <q-space />
          <q-btn
            v-close-popup
            flat
            dense
            round
            icon="close"
          />
        </q-card-section>

        <q-card-section class="k-checkout-grid">
          <!-- IZQUIERDA · Vista previa del recibo (en vivo) -->
          <div class="k-receipt-col">
            <ReceiptPreview :data="receiptData" />
          </div>

          <!-- DERECHA · Formulario + botón Cobrar (columna 2) -->
          <div class="k-col2">
            <div class="k-form">
              <!-- Tipo de comprobante -->
              <KSeg
                v-model="tipoDoc"
                :options="tipoOptions"
                class="q-mb-md"
              />

              <!-- Serie (por dispositivo/caja) -->
              <q-select
                v-model="serie"
                :options="serieOptions"
                outlined
                dense
                options-dense
                label="Serie"
                class="q-mb-sm"
              >
                <template #prepend>
                  <q-icon
                    name="tag"
                    size="18px"
                  />
                </template>
              </q-select>

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

              <div class="row q-col-gutter-sm q-mb-md">
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
                    lazy-rules="ondemand"
                    hide-bottom-space
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
              </div>

              <!-- Descuento -->
              <div class="k-section-label">
                Descuento
              </div>
              <div class="row items-start no-wrap q-gutter-x-sm q-mb-md">
                <q-input
                  v-model.number="descuentoValor"
                  class="col k-desc"
                  type="number"
                  dense
                  outlined
                  min="0"
                  placeholder="0"
                  :rules="descuentoRules"
                  hide-bottom-space
                />
                <div
                  class="k-seg k-seg--mini k-seg--match col-auto"
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
                  <span
                    class="k-pay-badge"
                    :style="{ background: m.color }"
                  >
                    <img
                      v-if="m.logo"
                      :src="m.logo"
                      alt=""
                      class="k-pay-img"
                    >
                    <q-icon
                      v-else
                      :name="m.icon ?? ''"
                      size="16px"
                      color="white"
                    />
                  </span>
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
                <div class="k-section-label q-mt-md">
                  Efectivo recibido
                </div>
                <q-input
                  :model-value="efectivoStr"
                  type="text"
                  inputmode="decimal"
                  outlined
                  class="k-efectivo"
                  placeholder="0.00"
                  @update:model-value="onEfectivoInput"
                  @blur="formatEfectivo"
                >
                  <template #prepend>
                    <span class="k-efectivo-cur">S/</span>
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
            </div>

            <q-btn
              class="full-width k-cobrar q-mt-md"
              color="primary"
              unelevated
              size="lg"
              icon="sell"
              :label="`Cobrar  ·  S/ ${money(totals.total)}`"
              :loading="emitting"
              :disable="!caja"
              @click="cobrar"
            />
          </div>
        </q-card-section>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { QInput } from 'quasar'
import { useCompanyStore } from '@/stores/company'
import { useRealtime } from '@/lib/realtime'
import { uid } from '@/lib/uid'
import { listProducts } from '@/modules/products/products.api'
import { listCustomers } from '@/modules/customers/customers.api'
import { listStock } from '@/modules/inventory/inventory.api'
import { getOpenSession, type CashSession } from '@/modules/cash/cash.api'
import { emitirComprobante } from '@/modules/documents/documents.api'
import { useSeries } from '@/modules/documents/useSeries'
import { lookupDoc } from '@/modules/documents/lookup.api'
import { compartirWhatsApp } from '@/lib/share'
import { printTicket } from '@/lib/ticket'
import KSeg from '@/components/KSeg.vue'
import ReceiptPreview from '@/components/ReceiptPreview.vue'
import { computeTotals, round2 } from '@/modules/sunat'
import { firstError, ruc, nonNegative, maxVal, positive, required, type Rule } from '@/lib/validation'
import { notify } from '@/lib/toast'
import type { Product, Customer, TipoDoc, DocumentRow } from '@/types'

interface CartItem {
  productId: string
  nombre: string
  precio: number
  cantidad: number
  /** Afectación IGV (cat. 07) y unidad (cat. 03) del producto, para emitir correctamente. */
  tipoAfectacion: string
  unidadMedida: string
  /** Impuesto a la bolsa plástica (ICBPER): monto fijo por unidad, obligatorio si el producto lo marca. */
  icbper: boolean
}
type FormaPago = 'efectivo' | 'yape' | 'plin' | 'tarjeta' | 'transferencia'

const company = useCompanyStore()
// Realtime: mantén catálogo, stock y estado de caja al día (ventas de otra caja/pestaña).
// `stock` no tiene company_id → el stock se refresca vía ventas (documents) y ajustes (inventory_movements).
useRealtime('products', () => company.current?.id, () => { void reloadCatalog() })
useRealtime('documents', () => company.current?.id, () => { void refreshStock() })
useRealtime('inventory_movements', () => company.current?.id, () => { void refreshStock() })
useRealtime('cash_sessions', () => company.current?.id, () => { void reloadCatalog() })
const router = useRouter()

const tipoOptions: { label: string; value: TipoDoc }[] = [
  { label: 'Boleta', value: '03' },
  { label: 'Factura', value: '01' },
]
// Métodos de pago. Los tipos genéricos (efectivo/tarjeta/transferencia) usan un
// ícono limpio; Yape/Plin usan el logo de marca desde /public/pay (reemplazable
// por el SVG oficial sin tocar código). Se usa para el selector y para etiquetar
// el comprobante/ticket al cobrar.
type MetodoPago = { value: FormaPago; label: string; color: string; icon?: string; logo?: string }
const metodosPago: MetodoPago[] = [
  { value: 'efectivo', label: 'Efectivo', color: '#16a34a', logo: '/pay/efectivo.svg' },
  { value: 'yape', label: 'Yape', color: '#742284', logo: '/pay/yape.png' },
  { value: 'plin', label: 'Plin', color: '#0ac3c9', logo: '/pay/plin.webp' },
  { value: 'tarjeta', label: 'Tarjeta', color: '#1a1f71', logo: '/pay/tarjeta.svg' },
  { value: 'transferencia', label: 'Transf.', color: '#475569', logo: '/pay/transferencia.svg' },
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

const products = ref<Product[]>([])
const stockByProduct = ref<Map<string, number>>(new Map())
const customers = ref<Customer[]>([])
const customerOptions = ref<Customer[]>([])
const cajaSession = ref<CashSession | null>(null)
const caja = computed(() => !!cajaSession.value)
const loading = ref(false)

const search = ref('')
const searchInput = ref<QInput | null>(null)
const sortBy = ref<'nombre' | 'precio_asc' | 'precio_desc' | 'stock'>('nombre')
const stockFilter = ref<'todos' | 'con' | 'bajo' | 'agotado'>('todos')
const tipoFilter = ref<'todos' | 'bien' | 'servicio'>('todos')
const precioMin = ref<number | null>(null)
const precioMax = ref<number | null>(null)
const stockMin = ref<number | null>(null)
const stockMax = ref<number | null>(null)
const sortOptions = [
  { label: 'Nombre (A-Z)', value: 'nombre' },
  { label: 'Precio ↑', value: 'precio_asc' },
  { label: 'Precio ↓', value: 'precio_desc' },
  { label: 'Más stock', value: 'stock' },
]
const stockOptions = [
  { label: 'Todo el stock', value: 'todos' },
  { label: 'Con stock', value: 'con' },
  { label: 'Stock bajo', value: 'bajo' },
  { label: 'Agotados', value: 'agotado' },
]
const tipoFilterOptions = [
  { label: 'Bienes y servicios', value: 'todos' },
  { label: 'Solo bienes', value: 'bien' },
  { label: 'Solo servicios', value: 'servicio' },
]
const cart = ref<CartItem[]>([])
const tipoDoc = ref<TipoDoc>('03')

const clienteNombre = ref('Cliente varios')
const clienteDoc = ref('')
const selectedCustomerId = ref<string | null>(null)

const descuentoModo = ref<'monto' | 'pct'>('pct')
const descuentoValor = ref<number>(0)

const formaPago = ref<FormaPago>('efectivo')
const efectivoRecibido = ref<number | null>(null)
const efectivoStr = ref('') // texto mostrado, forzado a 2 decimales (10 → 10.00)

const emitting = ref(false)
const showCheckout = ref(false)
// Llave de idempotencia: estable durante un intento de cobro (reintentos incluidos).
const ventaKey = ref<string | null>(null)

// Serie por dispositivo/caja (útil en multi-terminal: cada caja usa la suya).
const { serie, serieOptions, loadSeries } = useSeries(computed(() => company.current?.id), tipoDoc)
// Ancho del ticket térmico (80mm por defecto; 58mm para mini impresoras). Recordado.
function readTicketWidth(): 58 | 80 {
  try {
    return typeof localStorage !== 'undefined' && localStorage.getItem('emmisa-ticket-width') === '58' ? 58 : 80
  } catch {
    return 80
  }
}
const ticketWidth = ref<58 | 80>(readTicketWidth())
watch(ticketWidth, (v) => {
  try {
    if (typeof localStorage !== 'undefined') localStorage.setItem('emmisa-ticket-width', String(v))
  } catch {
    /* almacenamiento no disponible: no es crítico */
  }
})
const ticketWidthOptions: Array<{ value: 58 | 80; label: string; hint: string }> = [
  { value: 80, label: '80 mm', hint: 'Estándar (impresoras de mostrador)' },
  { value: 58, label: '58 mm', hint: 'Mini impresoras / móviles' },
]
const buscandoDoc = ref(false)
const lastSaleDoc = ref<DocumentRow | null>(null)

/* ---------------- Búsqueda / filtros / catálogo ---------------- */
const filtered = computed(() => {
  const q = (search.value || '').trim().toLowerCase()
  let list = products.value.filter((p) => p.activo !== false)

  // Texto
  if (q) {
    list = list.filter(
      (p) =>
        p.nombre.toLowerCase().includes(q) ||
        (p.sku || '').toLowerCase().includes(q) ||
        (p.barcode || '').toLowerCase().includes(q),
    )
  }

  // Tipo
  if (tipoFilter.value !== 'todos') list = list.filter((p) => p.tipo === tipoFilter.value)

  // Estado de stock
  if (stockFilter.value !== 'todos') {
    list = list.filter((p) => {
      const s = stockOf(p)
      if (stockFilter.value === 'con') return !p.controla_stock || s === null || s > 0
      if (stockFilter.value === 'agotado') return p.controla_stock && s !== null && s <= 0
      if (stockFilter.value === 'bajo') return p.controla_stock && s !== null && s > 0 && s <= p.stock_minimo
      return true
    })
  }

  // Rango de precio
  if (precioMin.value != null) list = list.filter((p) => p.precio >= precioMin.value!)
  if (precioMax.value != null) list = list.filter((p) => p.precio <= precioMax.value!)

  // Rango de stock (excluye productos sin control de stock cuando el rango está activo)
  if (stockMin.value != null) list = list.filter((p) => { const s = stockOf(p); return s != null && s >= stockMin.value! })
  if (stockMax.value != null) list = list.filter((p) => { const s = stockOf(p); return s != null && s <= stockMax.value! })

  // Orden
  const arr = [...list]
  if (sortBy.value === 'precio_asc') arr.sort((a, b) => a.precio - b.precio)
  else if (sortBy.value === 'precio_desc') arr.sort((a, b) => b.precio - a.precio)
  else if (sortBy.value === 'stock') arr.sort((a, b) => (stockOf(b) ?? -1) - (stockOf(a) ?? -1))
  else arr.sort((a, b) => a.nombre.localeCompare(b.nombre))
  return arr
})

const hayFiltros = computed(
  () =>
    stockFilter.value !== 'todos' ||
    tipoFilter.value !== 'todos' ||
    sortBy.value !== 'nombre' ||
    precioMin.value != null ||
    precioMax.value != null ||
    stockMin.value != null ||
    stockMax.value != null,
)
function limpiarFiltros() {
  stockFilter.value = 'todos'
  tipoFilter.value = 'todos'
  sortBy.value = 'nombre'
  precioMin.value = null
  precioMax.value = null
  stockMin.value = null
  stockMax.value = null
}

function stockOf(p: Product): number | null {
  if (!p.controla_stock) return null
  const v = stockByProduct.value.get(p.id)
  return v === undefined ? null : v
}
/** Unidades de este producto ya en el carrito (para descontar del stock mostrado). */
function cartQtyOf(id: string): number {
  return cart.value.find((i) => i.productId === id)?.cantidad ?? 0
}
/** Stock DISPONIBLE = stock real − lo que ya está en el carrito. Reactivo al carrito. */
function availableOf(p: Product): number | null {
  const s = stockOf(p)
  return s === null ? null : s - cartQtyOf(p.id)
}
function isAgotado(p: Product): boolean {
  const s = availableOf(p)
  return s !== null && s <= 0
}
function stockLabel(p: Product): string | null {
  const s = stockOf(p)
  if (s === null) return null
  return s <= 0 ? 'Agotado' : `${s} und`
}
function stockTone(p: Product): 'ok' | 'low' | 'out' {
  const s = availableOf(p) ?? 0
  if (s <= 0) return 'out'
  if (s <= p.stock_minimo) return 'low'
  return 'ok'
}

/* ---------------- Badge de stock ---------------- */
function stockBadge(p: Product): string {
  const s = availableOf(p)
  if (s === null) return ''
  return s <= 0 ? 'Agotado' : String(s)
}

// Si la foto del producto no carga (URL rota / borrada), cae al placeholder.
function onImgError(e: Event): void {
  const img = e.target as HTMLImageElement
  if (!img.src.endsWith('/product-placeholder.svg')) img.src = '/product-placeholder.svg'
}

/* ---------------- Carrito ---------------- */
const itemCount = computed(() => cart.value.reduce((n, i) => n + i.cantidad, 0))

function addToCart(p: Product) {
  const disponible = availableOf(p)
  if (disponible !== null && disponible <= 0) {
    notify({ type: 'warning', message: `Sin stock disponible de "${p.nombre}".` })
    return
  }
  const existing = cart.value.find((i) => i.productId === p.id)
  if (existing) existing.cantidad += 1
  // El motor asume precio CON IGV incluido: si el producto lo tiene neto (gravado), pásalo a bruto.
  else {
    const bruto = p.incluye_igv === false && (p.tipo_afectacion ?? '10') === '10' ? round2(Number(p.precio) * 1.18) : Number(p.precio)
    cart.value.push({ productId: p.id, nombre: p.nombre, precio: bruto, cantidad: 1, tipoAfectacion: p.tipo_afectacion || '10', unidadMedida: p.unidad_medida || 'NIU', icbper: p.icbper ?? false })
  }
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
  efectivoStr.value = ''
}
/** Confirma la cantidad editada a mano SIN superar el stock real (evita sobreventa). */
function commitQty(item: CartItem, scope: { value: number; set: () => void }) {
  if (!(scope.value >= 1)) return
  const p = products.value.find((x) => x.id === item.productId)
  const stock = p ? stockOf(p) : null
  if (stock !== null && scope.value > stock) {
    scope.value = stock
    notify({ type: 'warning', message: `Solo hay ${stock} en stock de "${item.nombre}".` })
  }
  scope.set()
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
    tipoAfectacion: i.tipoAfectacion,
    unidadMedida: i.unidadMedida,
    icbper: i.icbper,
  })),
)

// Desglose por afectación para el resumen/preview del checkout (coherente con el comprobante).
const totalsByAfectacion = computed(() => {
  let gravadoLT = 0, exonerado = 0, inafecto = 0, exportacion = 0, gratuito = 0
  for (const i of emitLines.value) {
    const lt = round2(i.precioUnitario * i.cantidad)
    switch (i.tipoAfectacion) {
      case '10': gravadoLT += lt; break
      case '20': case '21': exonerado += lt; break
      case '40': exportacion += lt; break
      default:
        if (i.tipoAfectacion >= '30' && i.tipoAfectacion <= '36') inafecto += lt
        else gratuito += lt
    }
  }
  const gravado = round2(gravadoLT / 1.18)
  const igv = round2(gravadoLT - gravado)
  return { gravado, igv, exonerado: round2(exonerado), inafecto: round2(inafecto), exportacion: round2(exportacion), gratuito: round2(gratuito) }
})

// Totales netos (después de descuento) para mostrar y emitir.
const totals = computed(() =>
  computeTotals(emitLines.value.map((i) => ({ cantidad: i.cantidad, precioUnitario: i.precioUnitario }))),
)

const vuelto = computed(() => round2((efectivoRecibido.value || 0) - totals.value.total))

// Datos para la vista previa del recibo (panel izquierdo del modal de cobro).
const receiptData = computed(() => ({
  empresa: {
    razon_social: company.current?.razon_social ?? 'Mi empresa',
    ruc: company.current?.ruc ?? '—',
    direccion: company.current?.direccion ?? null,
  },
  tipoLabel: tipoDoc.value === '01' ? 'FACTURA ELECTRÓNICA' : 'BOLETA DE VENTA ELECTRÓNICA',
  numero: null,
  fecha: null,
  cliente: { denominacion: clienteNombre.value || 'Cliente varios', numDoc: clienteDoc.value || null },
  items: emitLines.value.map((l) => ({
    descripcion: l.descripcion,
    cantidad: l.cantidad,
    precioUnitario: l.precioUnitario,
  })),
  gravado: totalsByAfectacion.value.gravado,
  igv: totalsByAfectacion.value.igv,
  exonerado: totalsByAfectacion.value.exonerado,
  inafecto: totalsByAfectacion.value.inafecto,
  exportacion: totalsByAfectacion.value.exportacion,
  total: totals.value.total,
  moneda: 'PEN',
  formaPago: metodosPago.find((m) => m.value === formaPago.value)?.label ?? null,
  condicionPago: 'Contado',
  recibido: formaPago.value === 'efectivo' ? efectivoRecibido.value : null,
  vuelto: formaPago.value === 'efectivo' && efectivoRecibido.value ? vuelto.value : null,
  width: ticketWidth.value,
  preview: true,
}))

// Reglas coherentes con el resto de la app (validation.ts).
const docRules = computed<Rule[]>(() =>
  tipoDoc.value === '01'
    ? [required('RUC obligatorio'), ruc]
    : clienteDoc.value
      ? [
          (v: unknown): true | string => {
            const n = String(v ?? '').replace(/\D/g, '')
            // En boleta el adquirente puede ser DNI (8) o RUC (11).
            return n.length === 8 || n.length === 11 || 'Ingresa un DNI (8) o RUC (11 dígitos)'
          },
        ]
      : [],
)
const descuentoRules = computed<Rule[]>(() =>
  descuentoModo.value === 'pct'
    ? [nonNegative(), maxVal(100, 'Máximo 100%')]
    : [nonNegative(), maxVal(subtotalBruto.value.total, 'Descuento mayor que el total')],
)

/* ---------------- Cliente ---------------- */
// Solo clientes válidos para el tipo de comprobante: Factura → con RUC (tipo_doc 6);
// Boleta → con DNI u otro (no RUC).
const customersForTipo = computed(() =>
  customers.value.filter((c) => (tipoDoc.value === '01' ? c.tipo_doc === '6' : c.tipo_doc !== '6')),
)
function onCustomerFilter(val: string, update: (fn: () => void) => void) {
  update(() => {
    const needle = val.toLowerCase()
    customerOptions.value = customersForTipo.value.filter(
      (c) => c.denominacion.toLowerCase().includes(needle) || (c.num_doc || '').includes(needle),
    )
  })
}
// Al cambiar Boleta/Factura, refresca la lista base del selector.
watch(tipoDoc, () => {
  customerOptions.value = customersForTipo.value
})
// Estado vacío del selector: ir a registrar un cliente nuevo.
function irAClientes() {
  router.push({ name: 'customers' })
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

// Autocompleta el nombre consultando el RUC/DNI (Edge Function `lookup`). Si no
// hay proveedor configurado, no rompe: el usuario escribe el nombre a mano.
async function autocompletarDoc(manual = false) {
  const num = clienteDoc.value.replace(/\D/g, '')
  const tipo = tipoDoc.value === '01' ? 'ruc' : 'dni'
  if ((tipo === 'ruc' && num.length !== 11) || (tipo === 'dni' && num.length !== 8)) {
    if (manual) notify({ type: 'warning', message: tipo === 'ruc' ? 'El RUC debe tener 11 dígitos' : 'El DNI debe tener 8 dígitos' })
    return
  }
  buscandoDoc.value = true
  try {
    const r = await lookupDoc(tipo, num)
    if (r?.denominacion) {
      clienteNombre.value = r.denominacion
      selectedCustomerId.value = null
      notify({ type: 'positive', message: 'Datos autocompletados' })
    } else if (manual) {
      notify({ type: 'warning', message: 'No se encontró (escribe el nombre a mano)' })
    }
  } finally {
    buscandoDoc.value = false
  }
}
function onDocInput(v: string | number | null) {
  onManualCliente()
  const num = String(v ?? '').replace(/\D/g, '')
  const need = tipoDoc.value === '01' ? 11 : 8
  if (num.length === need) void autocompletarDoc(false)
}
// Comparte la última venta emitida por WhatsApp (enlace wa.me con el PDF).
function whatsappUltima() {
  if (!lastSaleDoc.value || !company.current) return
  compartirWhatsApp(company.current.razon_social, lastSaleDoc.value, { pdfUrl: lastSaleDoc.value.pdf_url })
}

/* ---------------- Cobro ---------------- */
function money(n: number): string {
  return Number(n || 0).toFixed(2)
}
function setEfectivo(value: number) {
  // "Exacto" fija el total; los billetes se ACUMULAN (S/10 + S/20 = 30).
  efectivoRecibido.value =
    value === -1 ? totals.value.total : round2((efectivoRecibido.value || 0) + value)
  efectivoStr.value = efectivoRecibido.value != null ? efectivoRecibido.value.toFixed(2) : ''
}

// El monto se muestra como texto para forzar 2 decimales (10 → 10.00, 0.5 → 0.50).
function onEfectivoInput(v: string | number | null) {
  const s = String(v ?? '').replace(/[^0-9.]/g, '')
  const parts = s.split('.')
  const clean = parts.length > 1 ? `${parts[0]}.${parts.slice(1).join('')}` : s
  efectivoStr.value = clean
  efectivoRecibido.value = clean === '' || clean === '.' ? null : Number(clean)
}
function formatEfectivo() {
  efectivoStr.value =
    efectivoRecibido.value != null && !Number.isNaN(efectivoRecibido.value)
      ? efectivoRecibido.value.toFixed(2)
      : ''
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
  // Boleta ≥ S/700: SUNAT exige identificar al adquirente (DNI 8 o RUC 11 dígitos).
  const docDigits = doc.replace(/\D/g, '')
  if (!esFactura && totals.value.total >= 700 && docDigits.length !== 8 && docDigits.length !== 11) {
    notify({ type: 'warning', message: 'Boleta ≥ S/700: ingresa el DNI o RUC del cliente.' })
    return
  }
  const descErr = firstError(descuentoValor.value, descuentoRules.value)
  if (descErr) {
    notify({ type: 'warning', message: `Descuento: ${descErr}` })
    return
  }
  // No emitir un comprobante en S/ 0.00 (p. ej. descuento 100%): SUNAT lo rechaza y
  // consume el correlativo.
  if (totals.value.total <= 0) {
    notify({ type: 'warning', message: 'El total debe ser mayor que 0.' })
    return
  }
  if (formaPago.value === 'efectivo' && vuelto.value < 0) {
    notify({ type: 'warning', message: 'Ingresa el efectivo recibido: debe cubrir el total.' })
    return
  }

  // Llave estable por intento: si el cobro falla a medias, un reintento no duplica la venta.
  if (!ventaKey.value) ventaKey.value = uid()
  const esEfectivo = formaPago.value === 'efectivo'

  emitting.value = true
  try {
    const { document, result } = await emitirComprobante({
      companyId: company.current.id,
      tipoDoc: tipoDoc.value,
      customerId: selectedCustomerId.value,
      cliente: {
        tipoDoc: esFactura ? '6' : doc.length === 11 ? '6' : doc.length === 8 ? '1' : '0',
        numDoc: esFactura || doc.length === 8 || doc.length === 11 ? doc : undefined,
        denominacion: clienteNombre.value.trim() || 'Cliente varios',
      },
      serie: serie.value || undefined,
      items: emitLines.value,
      formaPago: formaPago.value,
      montoRecibido: esEfectivo ? efectivoRecibido.value : null,
      vuelto: esEfectivo && efectivoRecibido.value ? vuelto.value : null,
      cashSessionId: cajaSession.value.id,
      idempotencyKey: ventaKey.value,
    })
    lastSaleDoc.value = document

    // SUNAT rechazó: no imprimir ticket ni limpiar el carrito; el usuario corrige y
    // reemite (el correlativo rechazado quedó consumido → nuevo documento).
    if (result.estado === 'rechazado') {
      ventaKey.value = null
      notify({
        type: 'negative',
        message: result.mensaje ?? 'SUNAT rechazó el comprobante. Revisa los datos.',
        caption: `${document.serie}-${String(document.correlativo).padStart(8, '0')}`,
      })
      return
    }

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
      width: ticketWidth.value,
    })

    // Reset para la siguiente venta.
    showCheckout.value = false
    clearCart()
    ventaKey.value = null
    clienteDoc.value = ''
    clienteNombre.value = 'Cliente varios'
    selectedCustomerId.value = null
    formaPago.value = 'efectivo'
    descuentoModo.value = 'pct'
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

// Recarga catálogo (quita productos borrados) y estado de caja. La usa el realtime.
async function reloadCatalog() {
  if (!company.current) return
  try {
    const [prods, session] = await Promise.all([
      listProducts(company.current.id),
      getOpenSession(company.current.id).catch(() => null),
    ])
    products.value = prods
    cajaSession.value = session
  } catch {
    /* best-effort: no interrumpir la venta */
  }
  void refreshStock()
}

onMounted(async () => {
  if (!company.current) return
  void loadSeries()
  loading.value = true
  try {
    const [prods, custs, session] = await Promise.all([
      listProducts(company.current.id),
      listCustomers(company.current.id).catch(() => [] as Customer[]),
      getOpenSession(company.current.id).catch(() => null),
    ])
    products.value = prods
    customers.value = custs
    customerOptions.value = customersForTipo.value
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
/* Popup de configuración de impresión */
.k-print-menu {
  padding: 12px 14px 6px;
  min-width: 244px;
}
.k-print-menu-title {
  font-weight: 600;
  font-size: 13px;
}

/* Estado de caja · píldora de tinte suave (estilo Linear/Stripe) */
.k-status {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  padding: 4px 12px;
  border-radius: 999px;
  font-size: 12px;
  font-weight: 600;
  white-space: nowrap;
}
.k-status-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: currentColor;
  flex-shrink: 0;
}
.k-status--on {
  color: var(--q-positive);
  background: color-mix(in srgb, var(--q-positive) 14%, transparent);
}
.k-status--on .k-status-dot {
  animation: k-status-pulse 2s ease-in-out infinite;
}
.k-status--off {
  color: var(--k-muted);
  background: color-mix(in srgb, var(--k-muted) 16%, transparent);
}
@keyframes k-status-pulse {
  0%,
  100% {
    box-shadow: 0 0 0 0 color-mix(in srgb, var(--q-positive) 45%, transparent);
  }
  70% {
    box-shadow: 0 0 0 5px transparent;
  }
}
/* Contador de ítems · píldora neutra */
.k-count {
  min-width: 24px;
  padding: 2px 8px;
  border-radius: 999px;
  background: var(--k-surface-2);
  color: var(--k-muted);
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 12px;
  font-weight: 700;
  text-align: center;
  white-space: nowrap;
}
/* Botón "Vaciar": chip sutil que se pone rojo al hover */
.k-clear {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  border: none;
  background: var(--k-surface-2);
  color: var(--k-muted);
  font-family: inherit;
  font-size: 12px;
  font-weight: 600;
  padding: 5px 12px 5px 10px;
  border-radius: 999px;
  cursor: pointer;
  transition: background 0.15s ease, color 0.15s ease;
}
.k-clear:hover {
  background: color-mix(in srgb, var(--q-negative) 16%, transparent);
  color: var(--q-negative);
}
.k-clear:focus-visible {
  outline: none;
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--q-negative) 45%, transparent);
}

/* ---------- Sección de filtros ---------- */
.k-filters-card {
  padding: 20px;
}
/* Altura estable del header (aparecer/ocultar "Limpiar" no desplaza nada) */
.k-filters-head {
  min-height: 30px;
}
.k-range {
  display: flex;
  align-items: center;
  gap: 8px;
  background: var(--k-surface-2);
  border-radius: var(--k-radius-sm);
  padding: 0 14px;
  min-height: 50px; /* coherente con los demás controles */
  transition: box-shadow 0.15s ease;
}
/* El foco resalta TODA la píldora (no una cajita por input) */
.k-range:focus-within {
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--q-primary) 55%, transparent);
}
.k-range-label {
  font-size: 12px;
  font-weight: 600;
  color: var(--k-muted);
  white-space: nowrap;
  min-width: 58px;
}
.k-range-sep {
  color: var(--k-muted);
}
.k-range-in {
  flex: 1;
  min-width: 0;
  align-self: center; /* centra el input en la píldora (no arriba) */
}
/* Los inputs de rango van sin su propio fondo/altura/anillo (el marco lo da .k-range) */
.k-range-in :deep(.q-field__control) {
  background: transparent;
  min-height: 0;
  padding: 0;
  box-shadow: none !important; /* sin caja/anillo de foco en el input */
}
.k-range-in :deep(.q-field__control):before,
.k-range-in :deep(.q-field__control):after {
  display: none;
}
.k-range-in :deep(.q-field__native) {
  padding: 0;
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

/* ---------- Grilla de productos con foto (3–4 por fila) ---------- */
.k-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(190px, 1fr));
  gap: 16px;
}
.k-tile {
  display: flex;
  flex-direction: column;
  padding: 0;
  border: none;
  border-radius: var(--k-radius-sm);
  background: var(--k-surface);
  color: var(--k-text);
  font-family: inherit;
  text-align: left;
  cursor: pointer;
  overflow: hidden;
  box-shadow: 0 0 0 1px var(--k-border);
  transition: box-shadow 0.16s ease, transform 0.1s ease;
}
.k-tile:hover {
  box-shadow: 0 0 0 1px var(--k-border-hover), 0 10px 28px rgba(0, 0, 0, 0.1);
  transform: translateY(-2px);
}
.k-tile:active {
  transform: translateY(0) scale(0.99);
}
.k-tile:focus-visible {
  outline: none;
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--q-primary) 70%, transparent);
}
.k-tile--out {
  opacity: 0.55;
  cursor: not-allowed;
}

/* Media (foto o placeholder) */
.k-tile-media {
  position: relative;
  aspect-ratio: 4 / 3;
  background: var(--k-surface-2);
  overflow: hidden;
}
.k-tile-photo {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}
/* Stock: pastilla "glass" oscura con punto de estado. Muestra el DISPONIBLE
   (stock real − lo que ya está en el carrito) y se actualiza en vivo. */
.k-tile-count {
  position: absolute;
  top: 8px;
  right: 8px;
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 4px 9px;
  border-radius: 999px;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11.5px;
  font-weight: 700;
  line-height: 1;
  white-space: nowrap;
  background: rgba(18, 18, 26, 0.66);
  -webkit-backdrop-filter: blur(6px);
  backdrop-filter: blur(6px);
  color: #f4f4f6;
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.14), 0 2px 8px rgba(0, 0, 0, 0.28);
  transition: box-shadow 0.16s ease, background 0.16s ease;
}
.k-count-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  flex-shrink: 0;
  background: #34d399; /* ok: verde */
  box-shadow: 0 0 0 3px color-mix(in srgb, #34d399 22%, transparent);
}
.k-count--low .k-count-dot {
  background: #fbbf24; /* stock bajo: ámbar */
  box-shadow: 0 0 0 3px color-mix(in srgb, #fbbf24 24%, transparent);
}
.k-count--out {
  background: var(--q-negative);
  color: #fff;
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.18), 0 2px 8px rgba(0, 0, 0, 0.28);
}
.k-count--out .k-count-dot {
  display: none;
}
/* Reservado: hay unidades de este producto en el carrito → aro índigo + punto índigo */
.k-count--reserved {
  box-shadow:
    inset 0 0 0 1px color-mix(in srgb, var(--q-primary) 85%, transparent),
    0 0 0 2px color-mix(in srgb, var(--q-primary) 42%, transparent),
    0 2px 8px rgba(0, 0, 0, 0.28);
}
.k-count--reserved .k-count-dot {
  background: var(--q-primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--q-primary) 28%, transparent);
}

/* Cuerpo (nombre + precio) */
.k-tile-body {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 12px 14px 14px;
}
.k-tile-name {
  font-weight: 600;
  font-size: 14px;
  line-height: 1.3;
  min-height: 2.6em;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.k-tile-foot {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 8px;
  min-width: 0;
}
.k-tile-price {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 17px;
  font-weight: 800;
  letter-spacing: -0.3px;
  color: var(--q-primary);
  white-space: nowrap;
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
.k-cart-pad {
  padding: 20px;
}
@media (min-width: 1024px) {
  .k-cart-col {
    position: sticky;
    /* Se pega DEBAJO del header global fijo (~60px) para que su cabecera
       ("Comprobante") no quede tapada al hacer scroll. */
    top: 72px;
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
/* Más aire entre Subtotal · Op. gravada · IGV */
.k-totals > .row + .row {
  margin-top: 7px;
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
  margin: 12px 0 6px;
}
.k-pay-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.k-pay {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 7px 14px 7px 8px;
  border: none;
  border-radius: 999px;
  background: var(--k-surface-2);
  color: var(--k-text);
  font-family: inherit;
  cursor: pointer;
  transition: box-shadow 0.15s ease, background 0.15s ease, color 0.15s ease;
}
.k-pay:hover {
  box-shadow: 0 0 0 1px var(--k-border-hover);
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
.k-pay-badge {
  width: 26px;
  height: 26px;
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  overflow: hidden;
}
.k-pay-img {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.k-pay-label {
  font-size: 13px;
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

/* ---------- Modal de cobro (ancho · recibo izquierda + formulario derecha) ---------- */
.k-checkout {
  width: 900px;
  max-width: 95vw;
}
.k-checkout-grid {
  display: flex;
  gap: 24px;
  align-items: flex-start;
}
.k-receipt-col {
  width: 320px;
  flex-shrink: 0;
  display: flex;
  justify-content: center;
}
.k-col2 {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
}
.k-form {
  flex: 1;
  min-width: 0;
  /* padding para que los aros/sombras (foco, método activo) no se corten */
  padding: 4px 8px 4px 4px;
}
/* El campo de descuento va un poco más bajo que el resto */
.k-desc :deep(.q-field__control) {
  min-height: 40px !important;
}
/* El switch S//% iguala la altura del campo de descuento (40px) */
.k-seg--match {
  height: 40px;
  align-items: stretch;
}
.k-seg--match .k-seg-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
/* "Efectivo recibido" como display de monto (pantalla tipo calculadora) */
.k-efectivo :deep(.q-field__control) {
  min-height: 60px !important;
  background: var(--k-bg);
}
.k-efectivo :deep(.q-field__native) {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 26px;
  font-weight: 800;
  letter-spacing: -0.5px;
  text-align: right;
}
.k-efectivo :deep(.q-field__native)::placeholder {
  font-weight: 700;
  color: var(--k-muted);
}
.k-efectivo-cur {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 18px;
  font-weight: 700;
  color: var(--k-muted);
}
/* Móvil: apila el recibo encima del formulario */
@media (max-width: 720px) {
  .k-checkout-grid {
    flex-direction: column;
    align-items: center;
    max-height: none;
  }
  .k-receipt-col {
    width: auto;
    overflow-y: visible;
  }
  .k-col2 {
    width: 100%;
  }
  .k-form {
    overflow-y: visible;
  }
}
/* Logo de WhatsApp dentro del botón de compartir */
.k-wa-logo {
  width: 19px;
  height: 19px;
  margin-right: 8px;
}
</style>
