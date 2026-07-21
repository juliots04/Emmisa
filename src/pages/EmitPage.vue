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
                class="col"
                :options="tipoOptions"
                emit-value
                map-options
                label="Tipo"
              />
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
              class="row q-col-gutter-sm items-center"
            >
              <q-select
                v-model="it.productId"
                class="col-12 col-sm-4"
                :options="productOptions"
                emit-value
                map-options
                clearable
                label="Producto"
                @update:model-value="onPick(idx, $event)"
              />
              <q-input
                v-model="it.descripcion"
                class="col"
                label="Descripción"
                :rules="nameRules"
                lazy-rules
                hide-bottom-space
              />
              <q-input
                v-model.number="it.cantidad"
                class="col-3 col-sm"
                type="number"
                label="Cant."
                :rules="qtyRules"
                lazy-rules
                hide-bottom-space
              />
              <q-input
                v-model.number="it.precioUnitario"
                class="col-3 col-sm"
                type="number"
                label="Precio"
                :rules="priceRules"
                lazy-rules
                hide-bottom-space
              />
              <q-btn
                class="col-auto"
                flat
                dense
                round
                icon="delete"
                color="negative"
                @click="items.splice(idx, 1)"
              />
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
            <div class="row justify-between">
              <span>Gravado</span><span>S/ {{ totals.gravado.toFixed(2) }}</span>
            </div>
            <div class="row justify-between">
              <span>IGV (18%)</span><span>S/ {{ totals.igv.toFixed(2) }}</span>
            </div>
            <q-separator class="q-my-sm" />
            <div class="row justify-between text-h6">
              <span>Total</span><span>S/ {{ totals.total.toFixed(2) }}</span>
            </div>

            <q-btn
              class="full-width q-mt-md"
              color="primary"
              size="lg"
              label="Emitir"
              :loading="emitting"
              @click="emit"
            />

            <q-banner
              v-if="lastResult"
              class="q-mt-md"
              :class="lastResult.estado === 'aceptado' ? 'bg-green-2' : 'bg-red-2'"
            >
              {{ lastResult.mensaje }}
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
import { emitirComprobante } from '@/modules/documents/documents.api'
import { computeTotals, type EmitResult } from '@/modules/sunat'
import { validate, docByTipo, nameRules, qtyRules, priceRules, type Rule } from '@/lib/validation'
import type { Product, TipoDoc } from '@/types'

const company = useCompanyStore()

const tipoOptions = [
  { label: 'Boleta', value: '03' },
  { label: 'Factura', value: '01' },
]
const docOptions = [
  { label: 'RUC', value: '6' },
  { label: 'DNI', value: '1' },
]

const tipoDoc = ref<TipoDoc>('03')
const clienteNombre = ref('Cliente varios')
const clienteTipoDoc = ref('6')
const clienteNumDoc = ref('')

interface Item {
  productId: string | null
  descripcion: string
  cantidad: number
  precioUnitario: number
}
const items = ref<Item[]>([{ productId: null, descripcion: '', cantidad: 1, precioUnitario: 0 }])
const products = ref<Product[]>([])
const emitting = ref(false)
const lastResult = ref<EmitResult | null>(null)

const productOptions = computed(() =>
  products.value.map((p) => ({ label: `${p.nombre} (S/ ${p.precio})`, value: p.id })),
)
const totals = computed(() =>
  computeTotals(
    items.value.map((i) => ({ cantidad: i.cantidad || 0, precioUnitario: i.precioUnitario || 0 })),
  ),
)

// Documento del cliente: obligatorio en factura (RUC o DNI según el tipo elegido).
const docRules = computed<Rule[]>(() => [docByTipo(clienteTipoDoc.value, true)])

function addItem() {
  items.value.push({ productId: null, descripcion: '', cantidad: 1, precioUnitario: 0 })
}

function onPick(idx: number, productId: string | null) {
  const p = products.value.find((x) => x.id === productId)
  if (p) {
    items.value[idx].descripcion = p.nombre
    items.value[idx].precioUnitario = p.precio
  }
}

async function emit() {
  if (!company.current) return

  // Guarda de validación antes de emitir.
  const cabErr = validate([[clienteNombre.value, nameRules]])
  if (cabErr) {
    notify({ type: 'warning', message: cabErr })
    return
  }
  if (tipoDoc.value === '01') {
    const docErr = validate([[clienteNumDoc.value, docRules.value]])
    if (docErr) {
      notify({ type: 'warning', message: docErr })
      return
    }
  }
  if (items.value.length === 0) {
    notify({ type: 'warning', message: 'Agrega al menos un ítem' })
    return
  }
  for (const it of items.value) {
    const itemErr = validate([
      [it.descripcion, nameRules],
      [it.cantidad, qtyRules],
      [it.precioUnitario, priceRules],
    ])
    if (itemErr) {
      notify({ type: 'warning', message: `Ítem: ${itemErr}` })
      return
    }
  }

  emitting.value = true
  lastResult.value = null
  try {
    const { result } = await emitirComprobante({
      companyId: company.current.id,
      tipoDoc: tipoDoc.value,
      cliente: {
        tipoDoc: tipoDoc.value === '01' ? clienteTipoDoc.value : '1',
        numDoc: clienteNumDoc.value || undefined,
        denominacion: clienteNombre.value,
      },
      items: items.value.filter((i) => i.descripcion && i.cantidad > 0),
    })
    lastResult.value = result
    notify({ type: 'positive', message: result.mensaje ?? 'Emitido' })
    items.value = [{ productId: null, descripcion: '', cantidad: 1, precioUnitario: 0 }]
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    emitting.value = false
  }
}

onMounted(async () => {
  if (company.current) {
    try {
      products.value = await listProducts(company.current.id)
    } catch {
      /* sin productos aún: se puede emitir escribiendo la descripción a mano */
    }
  }
})
</script>
