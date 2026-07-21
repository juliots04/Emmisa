<template>
  <q-page class="q-pa-md flex flex-center column">
    <!-- Barra de acciones (no se imprime) -->
    <div class="no-print full-width row items-center q-mb-md voucher-wrap">
      <q-btn flat icon="arrow_back" label="Volver" @click="goBack" />
      <q-space />
      <q-btn
        color="primary"
        icon="print"
        label="Imprimir"
        :disable="loading || !document"
        @click="print"
      />
    </div>

    <!-- Cargando -->
    <div v-if="loading" class="voucher-wrap flex flex-center q-pa-xl">
      <q-spinner size="32px" color="primary" />
    </div>

    <!-- No encontrado / error -->
    <q-banner v-else-if="!document" class="voucher-wrap no-print">
      <template #avatar>
        <q-icon name="error_outline" color="negative" />
      </template>
      No se encontró el comprobante.
    </q-banner>

    <!-- Voucher imprimible -->
    <q-card v-else class="voucher voucher-wrap">
      <q-card-section class="voucher-header">
        <div class="col">
          <div class="text-h6 emisor-nombre">{{ emisorNombre }}</div>
          <div class="text-caption emisor-ruc">RUC {{ emisorRuc }}</div>
        </div>
        <div class="voucher-box">
          <div class="voucher-box__tipo">{{ tipoLabel }} ELECTRÓNICA</div>
          <div class="voucher-box__ruc">RUC {{ emisorRuc }}</div>
          <div class="voucher-box__num">{{ numero }}</div>
        </div>
      </q-card-section>

      <q-separator />

      <q-card-section class="row items-start justify-between q-gutter-y-sm">
        <div class="col-12 col-sm">
          <div class="field-label">Fecha de emisión</div>
          <div>{{ fecha }}</div>
        </div>
        <div class="col-12 col-sm">
          <div class="field-label">Moneda</div>
          <div>{{ monedaLabel }}</div>
        </div>
        <div class="col-12 col-sm-auto text-right">
          <div class="field-label">Estado SUNAT</div>
          <q-badge :color="estadoColor(document.estado_sunat)" :label="document.estado_sunat" />
        </div>
      </q-card-section>

      <!-- Cliente -->
      <template v-if="customer">
        <q-separator />
        <q-card-section>
          <div class="field-label">Cliente</div>
          <div class="text-weight-medium">{{ customer.denominacion }}</div>
          <div v-if="customer.num_doc" class="text-caption emisor-ruc">
            {{ tipoDocClienteLabel }} {{ customer.num_doc }}
          </div>
          <div v-if="customer.direccion" class="text-caption emisor-ruc">
            {{ customer.direccion }}
          </div>
        </q-card-section>
      </template>

      <q-separator />

      <!-- Ítems -->
      <q-card-section class="q-pa-none">
        <q-markup-table flat square class="voucher-table">
          <thead>
            <tr>
              <th class="text-left">Descripción</th>
              <th class="text-right">Cant.</th>
              <th class="text-right">P. Unit.</th>
              <th class="text-right">Total</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="it in items" :key="it.id">
              <td class="text-left">{{ it.descripcion }}</td>
              <td class="text-right">{{ it.cantidad }}</td>
              <td class="text-right">{{ money(it.precio_unitario) }}</td>
              <td class="text-right">{{ money(it.total) }}</td>
            </tr>
            <tr v-if="items.length === 0">
              <td colspan="4" class="text-center emisor-ruc">Sin ítems.</td>
            </tr>
          </tbody>
        </q-markup-table>
      </q-card-section>

      <q-separator />

      <!-- Totales -->
      <q-card-section class="row justify-end">
        <div class="voucher-totals">
          <div class="row justify-between">
            <span>Gravado</span><span>{{ money(document.total_gravado) }}</span>
          </div>
          <div class="row justify-between">
            <span>IGV (18%)</span><span>{{ money(document.total_igv) }}</span>
          </div>
          <q-separator class="q-my-sm" />
          <div class="row justify-between text-h6">
            <span>Total</span><span>{{ money(document.total) }}</span>
          </div>
        </div>
      </q-card-section>
    </q-card>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useCompanyStore } from '@/stores/company'
import {
  getDocumentDetail,
  type DocumentItemRow,
} from '@/modules/documents/document-detail.api'
import type { Customer, DocumentRow } from '@/types'
import { notify } from '@/lib/toast'

const route = useRoute()
const router = useRouter()
const company = useCompanyStore()

const loading = ref(true)
const document = ref<DocumentRow | null>(null)
const items = ref<DocumentItemRow[]>([])
const customer = ref<Customer | null>(null)

const TIPO_LABELS: Record<string, string> = {
  '01': 'Factura',
  '03': 'Boleta',
  '07': 'Nota de crédito',
}

const emisorNombre = computed(() => company.current?.razon_social ?? 'Emisor')
const emisorRuc = computed(() => company.current?.ruc ?? '—')

const tipoLabel = computed(() =>
  document.value ? (TIPO_LABELS[document.value.tipo_doc] ?? 'Comprobante') : '',
)

const numero = computed(() =>
  document.value
    ? `${document.value.serie}-${String(document.value.correlativo).padStart(8, '0')}`
    : '',
)

const fecha = computed(() =>
  document.value
    ? new Date(document.value.created_at).toLocaleString('es-PE', {
        dateStyle: 'long',
        timeStyle: 'short',
      })
    : '',
)

const monedaLabel = computed(() => {
  const m = document.value?.moneda ?? 'PEN'
  return m === 'PEN' ? 'Soles (S/)' : m
})

const tipoDocClienteLabel = computed(() => {
  const t = customer.value?.tipo_doc
  if (t === '6') return 'RUC'
  if (t === '1') return 'DNI'
  return 'Doc.'
})

function symbol() {
  return document.value?.moneda === 'PEN' || !document.value?.moneda ? 'S/' : ''
}

function money(n: number) {
  return `${symbol()} ${Number(n ?? 0).toFixed(2)}`.trim()
}

function estadoColor(estado: string) {
  if (estado === 'aceptado') return 'positive'
  if (estado === 'rechazado') return 'negative'
  if (estado === 'anulado') return 'grey'
  return 'orange'
}

function print() {
  window.print()
}

function goBack() {
  router.push({ name: 'documents' })
}

onMounted(async () => {
  const id = String(route.params.id ?? '')
  if (!id) {
    loading.value = false
    return
  }
  try {
    const detail = await getDocumentDetail(id)
    document.value = detail.document
    items.value = detail.items
    customer.value = detail.customer
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
})
</script>

<style scoped>
.voucher-wrap {
  width: 100%;
  max-width: 820px;
}

.voucher {
  width: 100%;
}

.voucher-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}

.emisor-nombre {
  letter-spacing: -0.4px;
}

.emisor-ruc {
  color: var(--k-muted);
}

.voucher-box {
  border: 1px solid var(--k-border-hover);
  border-radius: var(--k-radius-sm);
  padding: 10px 16px;
  text-align: center;
  min-width: 220px;
}

.voucher-box__tipo {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 12px;
  letter-spacing: 0.4px;
  color: var(--k-muted);
}

.voucher-box__ruc {
  font-weight: 600;
  margin-top: 2px;
}

.voucher-box__num {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 18px;
  font-weight: 700;
  margin-top: 2px;
}

.field-label {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.3px;
  color: var(--k-muted);
  margin-bottom: 2px;
}

.voucher-table {
  background: transparent;
  color: var(--k-text);
}
.voucher-table th {
  color: var(--k-muted);
  text-transform: uppercase;
  font-size: 11px;
}

.voucher-totals {
  width: 100%;
  max-width: 280px;
}

/* ---------- Impresión limpia ---------- */
@media print {
  /* Oculta menús/cromo de la app y controles de la página */
  :global(.q-header),
  :global(.q-drawer),
  :global(.q-drawer__backdrop),
  :global(.q-page-sticky),
  .no-print {
    display: none !important;
  }

  /* Fondo blanco, texto negro */
  :global(html),
  :global(body),
  :global(.q-body--dark),
  :global(.body--dark),
  :global(.body--light),
  :global(.q-page-container),
  :global(.q-page),
  :global(.q-layout) {
    background: #fff !important;
    color: #000 !important;
  }

  :global(.q-page-container) {
    padding-left: 0 !important;
    padding-top: 0 !important;
  }

  .voucher-wrap {
    max-width: 100%;
  }

  /* El voucher sin sombra ni relleno de tarjeta oscura */
  .voucher {
    border: none !important;
    box-shadow: none !important;
    background: #fff !important;
    color: #000 !important;
  }

  .emisor-ruc,
  .field-label,
  .voucher-box__tipo,
  .voucher-table th {
    color: #333 !important;
  }

  .voucher-box {
    border-color: #000 !important;
  }
}
</style>
