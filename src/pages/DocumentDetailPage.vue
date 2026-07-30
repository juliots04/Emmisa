<template>
  <q-page class="q-pa-md">
    <div class="k-detail">
      <!-- Barra de acciones (no se imprime): sticky debajo del header global -->
      <div
        ref="actionbarRef"
        class="no-print row items-center q-gutter-x-sm k-actionbar"
        :class="{ 'is-stuck': stuck }"
      >
        <q-btn
          flat
          icon="arrow_back"
          label="Volver"
          @click="goBack"
        />
        <q-space />
        <q-btn
          v-if="document?.fiscal_document_id"
          flat
          dense
          no-caps
          icon="code"
          label="XML"
          :loading="downloadingArtifact === 'signed_xml'"
          @click="downloadArtifact('signed_xml')"
        />
        <q-btn
          v-if="document?.fiscal_document_id"
          flat
          dense
          no-caps
          icon="picture_as_pdf"
          label="PDF"
          :loading="downloadingArtifact === 'pdf'"
          @click="downloadArtifact('pdf')"
        />
        <q-btn
          v-if="document"
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
          WhatsApp
        </q-btn>
        <q-btn
          v-if="document"
          flat
          dense
          no-caps
          icon="mail"
          label="Email"
          @click="abrirEmail"
        />
        <q-btn
          v-if="document"
          color="primary"
          unelevated
          no-caps
          icon="print"
          label="Imprimir"
          :disable="loading"
          @click="print"
        />
      </div>

      <!-- Diálogo: enviar por email -->
      <q-dialog v-model="emailDialog">
        <q-card style="min-width: 340px">
          <q-card-section class="text-subtitle1 text-weight-medium">
            Enviar comprobante por email
          </q-card-section>
          <q-card-section class="q-pt-none">
            <q-input
              v-model="emailDestino"
              outlined
              dense
              type="email"
              label="Correo del cliente"
              autofocus
              @keyup.enter="enviarEmail"
            />
          </q-card-section>
          <q-card-actions align="right">
            <q-btn
              v-close-popup
              flat
              no-caps
              label="Cancelar"
            />
            <q-btn
              unelevated
              no-caps
              color="primary"
              label="Enviar"
              :loading="enviandoEmail"
              @click="enviarEmail"
            />
          </q-card-actions>
        </q-card>
      </q-dialog>

      <!-- Cargando -->
      <div
        v-if="loading"
        class="no-print flex flex-center q-pa-xl"
      >
        <q-spinner
          size="32px"
          color="primary"
        />
      </div>

      <!-- No encontrado -->
      <q-banner
        v-else-if="!document"
        class="no-print"
      >
        <template #avatar>
          <q-icon
            name="error_outline"
            color="negative"
          />
        </template>
        No se encontró el comprobante.
      </q-banner>

      <!-- Detalle -->
      <div
        v-else
        class="row q-col-gutter-md"
      >
        <!-- Izquierda: datos estructurados (no se imprime) -->
        <div class="col-12 col-md-7 no-print">
          <q-card class="q-mb-md">
            <!-- Cabecera -->
            <q-card-section class="k-head">
              <span
                class="k-head-ic"
                :style="docBadge(document.tipo_doc)"
              >
                <q-icon
                  :name="docMeta(document.tipo_doc).icon"
                  size="22px"
                />
              </span>
              <div class="k-head-txt">
                <div class="k-head-num">
                  {{ numero }}
                </div>
                <div class="k-head-tipo">
                  {{ TIPO_LABELS[document.tipo_doc] ?? 'Comprobante' }}
                </div>
              </div>
              <q-space />
              <span
                class="k-pill"
                :class="`k-pill--${estadoTone(document.estado_sunat)}`"
              >
                <i class="k-dot" />{{ document.estado_sunat }}
              </span>
            </q-card-section>
            <q-separator />

            <!-- Datos -->
            <q-card-section class="k-meta">
              <div class="k-meta-item">
                <div class="k-meta-k">
                  Emisión
                </div>
                <div class="k-meta-v">
                  {{ fechaLarga }}
                </div>
              </div>
              <div class="k-meta-item">
                <div class="k-meta-k">
                  Cliente
                </div>
                <div class="k-meta-v">
                  {{ clienteNombre }}
                </div>
              </div>
              <div
                v-if="clienteDoc"
                class="k-meta-item"
              >
                <div class="k-meta-k">
                  Documento
                </div>
                <div class="k-meta-v">
                  {{ clienteDoc }}
                </div>
              </div>
              <div class="k-meta-item">
                <div class="k-meta-k">
                  Moneda
                </div>
                <div class="k-meta-v">
                  {{ monedaLabel }}
                </div>
              </div>
              <div class="k-meta-item">
                <div class="k-meta-k">
                  Condición
                </div>
                <div class="k-meta-v">
                  {{ document.condicion_pago === 'credito' ? 'Crédito' : 'Contado' }}
                </div>
              </div>
              <div
                v-if="document.forma_pago"
                class="k-meta-item"
              >
                <div class="k-meta-k">
                  Forma de pago
                </div>
                <div class="k-meta-v text-capitalize">
                  {{ document.forma_pago }}
                </div>
              </div>
              <div
                v-if="document.condicion_pago === 'credito' && document.fecha_vencimiento"
                class="k-meta-item"
              >
                <div class="k-meta-k">
                  Vencimiento
                </div>
                <div class="k-meta-v">
                  {{ fmtFecha(document.fecha_vencimiento) }}
                </div>
              </div>
              <div
                v-if="estadoPago"
                class="k-meta-item"
              >
                <div class="k-meta-k">
                  Estado de pago
                </div>
                <div class="k-meta-v">
                  {{ estadoPago }}
                </div>
              </div>
            </q-card-section>
            <q-separator />

            <!-- Ítems -->
            <q-card-section>
              <div class="k-sec-title">
                Ítems
              </div>
              <div class="k-items">
                <div class="k-items-head">
                  <span>Cant</span><span>Descripción</span><span class="r">P. Unit</span><span class="r">Importe</span>
                </div>
                <div
                  v-for="it in items"
                  :key="it.id"
                  class="k-items-row"
                >
                  <span>{{ it.cantidad }}</span>
                  <span class="k-items-desc">{{ it.descripcion }}</span>
                  <span class="r k-mono">{{ money(it.precio_unitario) }}</span>
                  <span class="r k-mono">{{ money(it.total) }}</span>
                </div>
                <div
                  v-if="!items.length"
                  class="k-items-empty"
                >
                  — sin ítems —
                </div>
              </div>
            </q-card-section>
            <q-separator />

            <!-- Totales -->
            <q-card-section class="k-tots">
              <div
                v-if="num(document.total_gravado)"
                class="k-tot-row"
              >
                <span>Op. gravada</span><span>{{ simbolo }} {{ money(document.total_gravado) }}</span>
              </div>
              <div
                v-if="num(document.total_exonerado)"
                class="k-tot-row"
              >
                <span>Exonerado</span><span>{{ simbolo }} {{ money(document.total_exonerado) }}</span>
              </div>
              <div
                v-if="num(document.total_inafecto)"
                class="k-tot-row"
              >
                <span>Inafecto</span><span>{{ simbolo }} {{ money(document.total_inafecto) }}</span>
              </div>
              <div class="k-tot-row">
                <span>IGV (18%)</span><span>{{ simbolo }} {{ money(document.total_igv) }}</span>
              </div>
              <div class="k-tot-row k-tot-total">
                <span>Total</span><span>{{ simbolo }} {{ money(document.total) }}</span>
              </div>
            </q-card-section>
          </q-card>

          <!-- SUNAT -->
          <q-card>
            <q-card-section>
              <div class="k-sec-title">
                SUNAT
              </div>
              <div class="k-sunat">
                <div class="k-sunat-row">
                  <span class="k-meta-k">Estado</span>
                  <span
                    class="k-pill"
                    :class="`k-pill--${estadoTone(document.estado_sunat)}`"
                  >
                    <i class="k-dot" />{{ document.estado_sunat }}
                  </span>
                </div>
                <div
                  v-if="document.sunat_ticket"
                  class="k-sunat-row"
                >
                  <span class="k-meta-k">Ticket</span>
                  <span class="k-mono k-ellip">{{ document.sunat_ticket }}</span>
                </div>
                <div
                  v-if="document.hash"
                  class="k-sunat-row"
                >
                  <span class="k-meta-k">Hash</span>
                  <span class="k-mono k-ellip">{{ document.hash }}</span>
                </div>
                <div
                  v-if="document.cdr"
                  class="k-sunat-row"
                >
                  <span class="k-meta-k">CDR</span>
                  <span class="text-positive text-weight-medium">Recibido ✓</span>
                </div>
                <q-banner
                  v-if="document.estado_sunat === 'rechazado' && document.sunat_error"
                  dense
                  class="k-sunat-err"
                >
                  {{ document.sunat_error }}
                </q-banner>
              </div>
            </q-card-section>
          </q-card>
        </div>

        <!-- Derecha: representación impresa (el ticket) -->
        <div class="col-12 col-md-5">
          <div class="k-receipt-hold flex flex-center">
            <ReceiptPreview :data="detailReceiptData" />
          </div>
        </div>
      </div>
    </div>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useCompanyStore } from '@/stores/company'
import { getDocumentDetail, type DocumentItemRow } from '@/modules/documents/document-detail.api'
import {
  descargarArtefactoFiscal,
  enviarComprobantePorEmail,
  type FiscalArtifactKind,
} from '@/modules/documents/documents.api'
import ReceiptPreview from '@/components/ReceiptPreview.vue'
import { compartirWhatsApp } from '@/lib/share'
import type { Customer, DocumentRow } from '@/types'
import { notify } from '@/lib/toast'

const route = useRoute()
const router = useRouter()
const company = useCompanyStore()

const loading = ref(true)
const document = ref<DocumentRow | null>(null)
const items = ref<DocumentItemRow[]>([])
const customer = ref<Customer | null>(null)

// Barra de acciones sticky: detecta cuándo queda "pegada" para la sombra sutil.
const actionbarRef = ref<HTMLElement | null>(null)
const stuck = ref(false)
let stickyObserver: IntersectionObserver | null = null

const TIPO_LABELS: Record<string, string> = {
  '01': 'Factura electrónica',
  '03': 'Boleta de venta electrónica',
  '07': 'Nota de crédito electrónica',
  '08': 'Nota de débito electrónica',
}

/* ---------------- Derivados para el panel ---------------- */
const numero = computed(() =>
  document.value ? `${document.value.serie}-${String(document.value.correlativo).padStart(8, '0')}` : '',
)
const fechaLarga = computed(() => {
  if (!document.value) return ''
  // Fecha FISCAL declarada a SUNAT (fecha_emision), NO el timestamp de inserción (created_at).
  // Se formatea la fecha (date) sin desfase de huso horario.
  const f = document.value.fecha_emision
  if (f) {
    const [y, m, d] = f.slice(0, 10).split('-').map(Number)
    return new Date(y, m - 1, d).toLocaleDateString('es-PE', { dateStyle: 'long' })
  }
  return new Date(document.value.created_at).toLocaleString('es-PE', { dateStyle: 'long', timeStyle: 'short' })
})
const clienteNombre = computed(
  () => customer.value?.denominacion ?? document.value?.receptor_denominacion ?? 'Cliente varios',
)
const clienteDoc = computed(() => customer.value?.num_doc ?? document.value?.receptor_num_doc ?? '')
const simbolo = computed(() => (document.value?.moneda === 'USD' ? 'US$' : 'S/'))
const monedaLabel = computed(() => (document.value?.moneda === 'USD' ? 'Dólares (US$)' : 'Soles (S/)'))
const estadoPago = computed(() => {
  const e = document.value?.estado_pago
  return e ? e.charAt(0).toUpperCase() + e.slice(1) : ''
})

const detailReceiptData = computed(() => {
  const d = document.value
  // Emisor = la empresa DUEÑA del documento (no la empresa activa): al abrir por URL
  // un comprobante de otra empresa del usuario, el RUC/razón social debe ser el correcto.
  const emp = company.companies.find((c) => c.id === d?.company_id) ?? company.current
  const cli = customer.value
    ? {
        denominacion: customer.value.denominacion,
        numDoc: customer.value.num_doc,
        direccion: customer.value.direccion,
      }
    : d?.receptor_denominacion
      ? {
          denominacion: d.receptor_denominacion,
          numDoc: d.receptor_num_doc ?? null,
          direccion: d.receptor_direccion ?? null,
        }
      : null
  return {
    empresa: {
      razon_social: emp?.razon_social ?? 'Emisor',
      ruc: emp?.ruc ?? '—',
      direccion: emp?.direccion ?? null,
    },
    tipoLabel: (d ? (TIPO_LABELS[d.tipo_doc] ?? 'Comprobante') : '').toUpperCase(),
    numero: numero.value || null,
    fecha: fechaLarga.value || null,
    cliente: cli,
    items: items.value.map((it) => ({
      descripcion: it.descripcion,
      cantidad: it.cantidad,
      precioUnitario: it.precio_unitario,
    })),
    gravado: d ? Number(d.total_gravado) : 0,
    igv: d ? Number(d.total_igv) : 0,
    exonerado: d ? Number(d.total_exonerado ?? 0) : 0,
    inafecto: d ? Number(d.total_inafecto ?? 0) : 0,
    exportacion: d ? Number(d.total_exportacion ?? 0) : 0,
    total: d ? Number(d.total) : 0,
    moneda: d?.moneda ?? 'PEN',
    formaPago: d?.forma_pago ?? null,
    condicionPago: d?.condicion_pago === 'credito' ? 'Crédito' : 'Contado',
    hash: d?.hash ?? null,
    codigo_qr: d?.codigo_qr ?? null,
    preview: false,
  }
})

/* ---------------- Formato / estilos ---------------- */
function docMeta(t: string): { icon: string; color: string } {
  if (t === '01') return { icon: 'description', color: '#6366f1' }
  if (t === '03') return { icon: 'receipt_long', color: '#0ea5e9' }
  if (t === '07') return { icon: 'undo', color: '#ef4444' }
  if (t === '08') return { icon: 'north_east', color: '#f59e0b' }
  return { icon: 'description', color: '#6366f1' }
}
function docBadge(t: string): Record<string, string> {
  const c = docMeta(t).color
  return { background: `color-mix(in srgb, ${c} 15%, transparent)`, color: c }
}
function estadoTone(e: string): 'ok' | 'warn' | 'bad' | 'muted' {
  if (e === 'aceptado') return 'ok'
  if (e === 'rechazado') return 'bad'
  if (e === 'anulado') return 'muted'
  return 'warn'
}
function money(n?: number | null): string {
  return Number(n ?? 0).toFixed(2)
}
function num(n?: number | null): number {
  return Number(n ?? 0)
}
function fmtFecha(v: string): string {
  return new Date(v).toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' })
}

/* ---------------- Acciones ---------------- */
function print() {
  window.print()
}
const downloadingArtifact = ref<FiscalArtifactKind | null>(null)
async function downloadArtifact(kind: FiscalArtifactKind) {
  if (!document.value) return
  downloadingArtifact.value = kind
  try {
    await descargarArtefactoFiscal(document.value, kind)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    downloadingArtifact.value = null
  }
}
// Comparte este comprobante por WhatsApp (enlace wa.me con el PDF).
function whatsapp() {
  if (!document.value) return
  const emp = company.companies.find((c) => c.id === document.value!.company_id) ?? company.current
  if (!emp) return
  compartirWhatsApp(emp.razon_social, document.value)
}

// Envío del comprobante por email.
const emailDialog = ref(false)
const emailDestino = ref('')
const enviandoEmail = ref(false)
function abrirEmail() {
  emailDestino.value = (customer.value as { email?: string } | null)?.email ?? ''
  emailDialog.value = true
}
async function enviarEmail() {
  if (!document.value) return
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailDestino.value)) {
    notify({ type: 'warning', message: 'Ingresa un correo válido' })
    return
  }
  enviandoEmail.value = true
  try {
    await enviarComprobantePorEmail(document.value.id, emailDestino.value)
    notify({ type: 'positive', message: 'Comprobante enviado por email' })
    emailDialog.value = false
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    enviandoEmail.value = false
  }
}

function goBack() {
  router.push({ name: 'documents' })
}

onMounted(() => {
  // Se pega cuando su borde superior toca el header (top: 60px + 1).
  if (actionbarRef.value && 'IntersectionObserver' in window) {
    stickyObserver = new IntersectionObserver(
      ([entry]) => {
        stuck.value = entry.intersectionRatio < 1
      },
      { threshold: [1], rootMargin: '-61px 0px 0px 0px' },
    )
    stickyObserver.observe(actionbarRef.value)
  }
})
onBeforeUnmount(() => stickyObserver?.disconnect())

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
.k-detail {
  max-width: 1040px;
  margin: 0 auto;
}

/* Barra de acciones fija: se queda pegada bajo el header global al hacer scroll. */
.k-actionbar {
  position: sticky;
  top: 60px; /* alto del header global (.k-toolbar min-height: 60px) */
  z-index: 10;
  background: var(--k-bg);
  padding: 10px 0;
  margin: 0 0 8px;
  border-bottom: 1px solid transparent;
  transition: border-color 0.2s ease, box-shadow 0.2s ease;
}
/* Al despegarse (queda "atascada"), gana una línea/sombra sutil de separación. */
.k-actionbar.is-stuck {
  border-bottom-color: var(--k-border);
  box-shadow: 0 6px 16px -12px rgba(0, 0, 0, 0.5);
}

/* Cabecera del comprobante */
.k-head {
  display: flex;
  align-items: center;
  gap: 12px;
}
.k-head-ic {
  width: 46px;
  height: 46px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.k-head-num {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 20px;
  font-weight: 800;
  letter-spacing: 0.5px;
}
.k-head-tipo {
  font-size: 12px;
  color: var(--k-muted);
  text-transform: uppercase;
  letter-spacing: 0.4px;
}

/* Píldora de estado */
.k-pill {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 4px 11px;
  border-radius: 999px;
  font-size: 12px;
  font-weight: 700;
  text-transform: capitalize;
  white-space: nowrap;
}
.k-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: currentColor;
}
.k-pill--ok {
  color: var(--q-positive);
  background: color-mix(in srgb, var(--q-positive) 14%, transparent);
}
.k-pill--warn {
  color: #f59e0b;
  background: color-mix(in srgb, #f59e0b 15%, transparent);
}
.k-pill--bad {
  color: var(--q-negative);
  background: color-mix(in srgb, var(--q-negative) 14%, transparent);
}
.k-pill--muted {
  color: var(--k-muted);
  background: color-mix(in srgb, var(--k-muted) 16%, transparent);
}

/* Grilla de datos */
.k-meta {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 14px 22px;
}
.k-meta-k {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.4px;
  color: var(--k-muted);
  margin-bottom: 2px;
}
.k-meta-v {
  font-size: 14px;
  font-weight: 600;
}

/* Secciones */
.k-sec-title {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  color: var(--k-muted);
  font-weight: 700;
  margin-bottom: 10px;
}

/* Ítems */
.k-items {
  font-size: 13px;
}
.k-items-head,
.k-items-row {
  display: grid;
  grid-template-columns: 42px 1fr 84px 90px;
  gap: 8px;
  align-items: start;
}
.k-items-head {
  color: var(--k-muted);
  font-size: 10.5px;
  text-transform: uppercase;
  letter-spacing: 0.3px;
  padding-bottom: 7px;
  border-bottom: 1px solid var(--k-border);
}
.k-items-row {
  padding: 8px 0;
  border-bottom: 1px solid color-mix(in srgb, var(--k-border) 55%, transparent);
}
.k-items-desc {
  overflow-wrap: anywhere;
}
.k-items-empty {
  color: var(--k-muted);
  text-align: center;
  padding: 12px 0;
}
.r {
  text-align: right;
}
.k-mono {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
}

/* Totales */
.k-tots {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.k-tot-row {
  display: flex;
  justify-content: space-between;
  font-size: 14px;
}
.k-tot-row span:last-child {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-weight: 600;
}
.k-tot-total {
  font-size: 18px;
  font-weight: 800;
  margin-top: 6px;
  padding-top: 10px;
  border-top: 1px solid var(--k-border);
}
.k-tot-total span:last-child {
  font-weight: 800;
  color: var(--k-text);
}

/* SUNAT */
.k-sunat {
  display: flex;
  flex-direction: column;
  gap: 11px;
}
.k-sunat-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}
.k-ellip {
  max-width: 62%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12px;
}
.k-sunat-err {
  background: color-mix(in srgb, var(--q-negative) 12%, transparent);
  color: var(--q-negative);
  border-radius: 8px;
  margin-top: 2px;
}

/* Recibo pegado en escritorio */
.k-receipt-hold {
  position: sticky;
  /* Debajo del header global (60px) + la barra de acciones sticky (~56px), para
     que el recibo no se meta detrás de ellos al hacer scroll. */
  top: 124px;
}
@media (max-width: 1023px) {
  .k-receipt-hold {
    position: static;
    margin-top: 4px;
  }
}

/* Logo de WhatsApp dentro del botón (glifo blanco sobre verde) */
.k-wa-logo {
  width: 18px;
  height: 18px;
  margin-right: 8px;
}

/* ---------- Impresión limpia: solo el recibo ---------- */
@media print {
  :global(.q-header),
  :global(.q-drawer),
  :global(.q-drawer__backdrop),
  :global(.q-page-sticky),
  .no-print {
    display: none !important;
  }
  :global(html),
  :global(body),
  :global(.body--dark),
  :global(.body--light),
  :global(.q-page-container),
  :global(.q-page),
  :global(.q-layout) {
    background: #fff !important;
  }
  :global(.q-page-container) {
    padding-left: 0 !important;
    padding-top: 0 !important;
  }
  .k-receipt-hold {
    position: static !important;
  }
  :global(.receipt) {
    box-shadow: none !important;
  }
}
</style>
  :global(.receipt) {
    box-shadow: none !important;
  }
}
</style>
