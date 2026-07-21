<template>
  <q-page class="q-pa-md">
    <div class="text-h5 q-mb-md">Emitir comprobante</div>

    <div class="row q-col-gutter-md">
      <!-- Formulario -->
      <div class="col-12 col-md-7">
        <q-card>
          <q-card-section class="q-gutter-sm">
            <div class="row q-col-gutter-sm">
              <q-select
                v-model="tipoDoc"
                class="col-12 col-sm"
                :options="tipoOptions"
                emit-value
                map-options
                label="Tipo"
              />
              <q-select
                v-model="condicionPago"
                class="col-12 col-sm"
                :options="condicionOptions"
                emit-value
                map-options
                label="Condición de pago"
              />
              <q-input
                v-if="condicionPago === 'credito'"
                v-model="fechaVencimiento"
                class="col-12 col-sm"
                type="date"
                label="Vence"
              />
            </div>

            <!-- Cliente registrado (opcional) -->
            <q-select
              v-model="selectedCustomerId"
              :options="customerOptions"
              emit-value
              map-options
              clearable
              use-input
              input-debounce="0"
              label="Cliente registrado (opcional)"
              @filter="filterCustomers"
              @update:model-value="onPickCustomer"
            >
              <template #no-option>
                <q-item><q-item-section class="text-grey">Sin coincidencias · escribe el nombre abajo</q-item-section></q-item>
              </template>
            </q-select>

            <div class="row q-col-gutter-sm">
              <q-input
                v-model="clienteNombre"
                class="col"
                label="Cliente"
                :rules="nameRules"
                lazy-rules
              />
            </div>

            <div v-if="tipoDoc === '01'" class="row q-col-gutter-sm">
              <q-select
                v-model="clienteTipoDoc"
                class="col-4"
                :options="docOptions"
                emit-value
                map-options
                label="Tipo doc"
              />
              <q-input
                v-model="clienteNumDoc"
                class="col"
                :label="clienteTipoDoc === '6' ? 'RUC' : 'DNI'"
                :rules="docRules"
                lazy-rules
              />
            </div>

            <q-separator class="q-my-sm" />
            <div class="text-subtitle2">Ítems</div>

            <div
              v-for="(it, idx) in items"
              :key="idx"
              class="row q-col-gutter-xs items-center"
            >
              <q-select
                v-model="it.productId"
                class="col-12 col-sm-3"
                :options="productOptions"
                emit-value
                map-options
                clearable
                dense
                label="Producto"
                @update:model-value="onPick(idx, $event)"
              />
              <q-input v-model="it.descripcion" class="col" dense label="Descripción" :rules="nameRules" lazy-rules hide-bottom-space />
              <q-input v-model.number="it.cantidad" class="col-2 col-sm-1" dense type="number" label="Cant." :rules="qtyRules" lazy-rules hide-bottom-space />
              <q-input v-model.number="it.precioUnitario" class="col-3 col-sm-2" dense type="number" label="Precio" :rules="priceRules" lazy-rules hide-bottom-space />
              <q-input v-model.number="it.descuento" class="col-3 col-sm-1" dense type="number" label="Desc." hide-bottom-space />
              <q-select v-model="it.tipoAfectacion" class="col-4 col-sm-2" dense :options="afectacionOptions" emit-value map-options label="Afect." />
              <q-btn class="col-auto" flat dense round icon="delete" color="negative" @click="items.splice(idx, 1)" />
            </div>

            <q-btn flat icon="add" label="Agregar ítem" @click="addItem" />
          </q-card-section>
        </q-card>
      </div>

      <!-- Resumen -->
      <div class="col-12 col-md-5">
        <q-card>
          <q-card-section>
            <div class="text-subtitle1 q-mb-sm">Resumen</div>
            <div class="row justify-between"><span>Gravado</span><span>S/ {{ totals.gravado.toFixed(2) }}</span></div>
            <div class="row justify-between"><span>IGV (18%)</span><span>S/ {{ totals.igv.toFixed(2) }}</span></div>
            <div v-if="totals.exonerado > 0" class="row justify-between"><span>Exonerado</span><span>S/ {{ totals.exonerado.toFixed(2) }}</span></div>
            <div v-if="totals.inafecto > 0" class="row justify-between"><span>Inafecto</span><span>S/ {{ totals.inafecto.toFixed(2) }}</span></div>
            <div v-if="totals.exportacion > 0" class="row justify-between"><span>Exportación</span><span>S/ {{ totals.exportacion.toFixed(2) }}</span></div>
            <div v-if="totals.gratuito > 0" class="row justify-between text-grey"><span>Gratuito</span><span>S/ {{ totals.gratuito.toFixed(2) }}</span></div>
            <div class="row justify-between items-center q-mt-xs">
              <span>Descuento global</span>
              <q-input v-model.number="descuentoGlobal" dense borderless input-class="text-right" style="max-width: 90px" type="number" />
            </div>
            <q-separator class="q-my-sm" />
            <div class="row justify-between text-h6"><span>Total</span><span>S/ {{ totals.total.toFixed(2) }}</span></div>

            <q-btn class="full-width q-mt-md" color="primary" size="lg" label="Emitir" :loading="emitting" @click="emit" />

            <q-banner v-if="lastResult" class="q-mt-md" :class="lastResult.estado === 'aceptado' ? 'bg-green-2' : 'bg-red-2'">
              {{ lastResult.mensaje }}
              <span v-if="lastResult.simulado"> (simulado)</span>
            </q-banner>
          </q-card-section>
        </q-card>
      </div>
    </div>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { notify } from '@/lib/toast'
import { useCompanyStore } from '@/stores/company'
import { listProducts } from '@/modules/products/products.api'
import { listCustomers } from '@/modules/customers/customers.api'
import { emitirComprobante } from '@/modules/documents/documents.api'
import type { EmitResult } from '@/modules/sunat'
import { validate, docByTipo, nameRules, qtyRules, priceRules, type Rule } from '@/lib/validation'
import type { Customer, Product, TipoDoc } from '@/types'

const company = useCompanyStore()

const tipoOptions = [
  { label: 'Boleta', value: '03' },
  { label: 'Factura', value: '01' },
]
const docOptions = [
  { label: 'RUC', value: '6' },
  { label: 'DNI', value: '1' },
]
const condicionOptions = [
  { label: 'Contado', value: 'contado' },
  { label: 'Crédito', value: 'credito' },
]
const afectacionOptions = [
  { label: 'Gravado', value: '10' },
  { label: 'Exonerado', value: '20' },
  { label: 'Inafecto', value: '30' },
  { label: 'Exportación', value: '40' },
  { label: 'Gratuito', value: '21' },
]

const tipoDoc = ref<TipoDoc>('03')
const condicionPago = ref('contado')
const fechaVencimiento = ref('')
const clienteNombre = ref('Cliente varios')
const clienteTipoDoc = ref('6')
const clienteNumDoc = ref('')
const selectedCustomerId = ref<string | null>(null)
const descuentoGlobal = ref(0)

interface Item {
  productId: string | null
  descripcion: string
  cantidad: number
  precioUnitario: number
  descuento: number
  tipoAfectacion: string
}
const newItem = (): Item => ({ productId: null, descripcion: '', cantidad: 1, precioUnitario: 0, descuento: 0, tipoAfectacion: '10' })
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

const totals = computed(() => {
  const t = { gravado: 0, igv: 0, exonerado: 0, inafecto: 0, exportacion: 0, gratuito: 0, total: 0 }
  for (const it of items.value) {
    const lineTotal = round2((it.cantidad || 0) * (it.precioUnitario || 0) - (it.descuento || 0))
    const code = it.tipoAfectacion
    if (code === '10') {
      const base = round2(lineTotal / 1.18)
      t.gravado += base
      t.igv += round2(lineTotal - base)
      t.total += lineTotal
    } else if (code === '20') { t.exonerado += lineTotal; t.total += lineTotal }
    else if (code === '30') { t.inafecto += lineTotal; t.total += lineTotal }
    else if (code === '40') { t.exportacion += lineTotal; t.total += lineTotal }
    else { t.gratuito += lineTotal } // 21/gratuito: no suma a pagar
  }
  t.total = round2(t.total - (descuentoGlobal.value || 0))
  for (const k of Object.keys(t) as (keyof typeof t)[]) t[k] = round2(t[k])
  return t
})

const docRules = computed<Rule[]>(() => [docByTipo(clienteTipoDoc.value, true)])

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
    clienteTipoDoc.value = c.tipo_doc === '6' ? '6' : '1'
    clienteNumDoc.value = c.num_doc ?? ''
    if (c.tipo_doc === '6') tipoDoc.value = '01' // tiene RUC → sugiere factura
  }
}

function onPick(idx: number, productId: string | null) {
  const p = products.value.find((x) => x.id === productId)
  if (p) {
    items.value[idx].descripcion = p.nombre
    items.value[idx].precioUnitario = p.precio
    if (p.tipo_afectacion) items.value[idx].tipoAfectacion = p.tipo_afectacion
  }
}

async function emit() {
  if (!company.current) return
  const cabErr = validate([[clienteNombre.value, nameRules]])
  if (cabErr) { notify({ type: 'warning', message: cabErr }); return }
  if (tipoDoc.value === '01') {
    const docErr = validate([[clienteNumDoc.value, docRules.value]])
    if (docErr) { notify({ type: 'warning', message: docErr }); return }
  }
  if (items.value.length === 0) { notify({ type: 'warning', message: 'Agrega al menos un ítem' }); return }
  for (const it of items.value) {
    const itemErr = validate([[it.descripcion, nameRules], [it.cantidad, qtyRules], [it.precioUnitario, priceRules]])
    if (itemErr) { notify({ type: 'warning', message: `Ítem: ${itemErr}` }); return }
  }

  emitting.value = true
  lastResult.value = null
  try {
    const { result } = await emitirComprobante({
      companyId: company.current.id,
      tipoDoc: tipoDoc.value,
      customerId: selectedCustomerId.value,
      cliente: {
        tipoDoc: tipoDoc.value === '01' ? clienteTipoDoc.value : '1',
        numDoc: clienteNumDoc.value || undefined,
        denominacion: clienteNombre.value,
      },
      condicionPago: condicionPago.value,
      fechaVencimiento: condicionPago.value === 'credito' ? fechaVencimiento.value || null : null,
      descuentoGlobal: descuentoGlobal.value || 0,
      items: items.value
        .filter((i) => i.descripcion && i.cantidad > 0)
        .map((i) => ({
          productId: i.productId,
          descripcion: i.descripcion,
          cantidad: i.cantidad,
          precioUnitario: i.precioUnitario,
          descuento: i.descuento || 0,
          tipoAfectacion: i.tipoAfectacion,
        })),
    })
    lastResult.value = result
    notify({ type: 'positive', message: result.mensaje ?? 'Emitido' })
    items.value = [newItem()]
    descuentoGlobal.value = 0
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    emitting.value = false
  }
}

onMounted(async () => {
  if (!company.current) return
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
