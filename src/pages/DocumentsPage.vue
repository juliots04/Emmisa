<template>
  <q-page class="q-pa-md">
    <!-- ---------- Encabezado ---------- -->
    <div class="row items-center q-mb-md q-gutter-x-sm">
      <div class="text-h5">
        Comprobantes
      </div>
      <q-badge
        v-if="!loading"
        color="primary"
        outline
        :label="`${rows.length}`"
      />
      <q-space />
      <q-btn
        flat
        dense
        round
        icon="refresh"
        :loading="loading"
        @click="load"
      >
        <q-tooltip>Actualizar</q-tooltip>
      </q-btn>
      <q-btn
        outline
        no-caps
        icon="download"
        label="Exportar"
        :disable="!filteredRows.length"
        @click="exportXls"
      />
      <q-btn
        unelevated
        no-caps
        color="primary"
        icon="add"
        label="Nuevo"
        :to="{ name: 'emit' }"
      />
    </div>

    <!-- ---------- Tarjetas de resumen (KPIs) ---------- -->
    <div class="row q-col-gutter-md q-mb-md">
      <div
        v-for="k in kpis"
        :key="k.label"
        class="col-6 col-md-3"
      >
        <q-card class="k-stat">
          <div class="k-stat-label">
            <q-icon
              :name="k.icon"
              size="14px"
            />{{ k.label }}
          </div>
          <div
            class="k-stat-value"
            :style="k.valueColor ? { color: k.valueColor } : undefined"
          >
            {{ k.value }}
          </div>
        </q-card>
      </div>
    </div>

    <!-- ---------- Barra de filtros (contenedor propio) ---------- -->
    <q-card class="q-mb-md">
      <q-card-section class="k-filters-card">
        <div class="row items-center q-mb-sm">
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
        <div class="k-filter-flow">
          <!-- Búsqueda: ancha, ocupa el espacio libre de la fila -->
          <q-input
            v-model="search"
            class="k-ff-search"
            outlined
            dense
            clearable
            placeholder="Buscar por número o cliente…"
          >
            <template #prepend>
              <q-icon name="search" />
            </template>
          </q-input>
          <!-- El resto de filtros se autoajustan al ancho de su texto -->
          <q-select
            v-model="tipoFilter"
            class="k-ff-item"
            outlined
            dense
            emit-value
            map-options
            options-dense
            :options="tipoFilters"
            label="Tipo"
          />
          <q-select
            v-model="estadoFilter"
            class="k-ff-item"
            outlined
            dense
            emit-value
            map-options
            options-dense
            :options="estadoFilters"
            label="Estado"
          />
          <q-select
            v-model="serieFilter"
            class="k-ff-item"
            outlined
            dense
            emit-value
            map-options
            options-dense
            :options="serieOptions"
            label="Serie"
          />
          <q-select
            v-model="pagoFilter"
            class="k-ff-item"
            outlined
            dense
            emit-value
            map-options
            options-dense
            :options="pagoOptions"
            label="Forma de pago"
          />
          <q-select
            v-model="monedaFilter"
            class="k-ff-item"
            outlined
            dense
            emit-value
            map-options
            options-dense
            :options="monedaOptions"
            label="Moneda"
          />
          <KDate
            v-model="desde"
            class="k-ff-item"
            placeholder="Desde"
          />
          <KDate
            v-model="hasta"
            class="k-ff-item"
            placeholder="Hasta"
          />
        </div>
      </q-card-section>
    </q-card>

    <!-- ---------- Barra de acciones masivas ---------- -->
    <div
      v-if="selected.length"
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
        icon="code"
        label="XML"
        @click="bulkDescargar('signed_xml', 'XML')"
      />
      <q-btn
        flat
        dense
        no-caps
        icon="picture_as_pdf"
        label="PDF"
        @click="bulkDescargar('pdf', 'PDF')"
      />
      <q-btn
        flat
        dense
        no-caps
        icon="send"
        label="Enviar"
        @click="bulkEnviar"
      />
      <q-btn
        flat
        dense
        no-caps
        color="negative"
        icon="block"
        label="Anular"
        @click="bulkAnular"
      />
    </div>

    <!-- ---------- Tabla ---------- -->
    <q-table
      v-model:pagination="pagination"
      v-model:selected="selected"
      selection="multiple"
      :rows="filteredRows"
      :columns="columns"
      row-key="id"
      :loading="loading"
      flat
      bordered
      class="k-doc-table"
      :rows-per-page-options="[12, 25, 50, 0]"
    >
      <!-- Comprobante (número + tipo con badge) -->
      <template #body-cell-numero="props">
        <q-td :props="props">
          <div class="k-doc">
            <span
              class="k-doc-ic"
              :style="docBadge(props.row.tipo_doc)"
            >
              <q-icon
                :name="docMeta(props.row.tipo_doc).icon"
                size="17px"
              />
            </span>
            <div class="k-doc-txt">
              <div class="k-doc-num">
                {{ numero(props.row) }}
              </div>
              <div class="k-doc-tipo">
                {{ tipoLabel(props.row.tipo_doc) }}
              </div>
            </div>
          </div>
        </q-td>
      </template>

      <!-- Cliente -->
      <template #body-cell-cliente="props">
        <q-td :props="props">
          <div class="k-cli-name">
            {{ props.row.receptor_denominacion || 'Cliente varios' }}
          </div>
          <div
            v-if="props.row.receptor_num_doc"
            class="k-cli-doc"
          >
            {{ props.row.receptor_num_doc }}
          </div>
        </q-td>
      </template>

      <!-- Fecha -->
      <template #body-cell-fecha="props">
        <q-td :props="props">
          <div class="k-fecha-d">
            {{ fmtFecha(props.row.fecha_emision ?? props.row.created_at) }}
          </div>
          <div class="k-fecha-h">
            {{ fmtHora(props.row.created_at) }}
          </div>
        </q-td>
      </template>

      <!-- Estado SUNAT -->
      <template #body-cell-estado="props">
        <q-td :props="props">
          <span
            class="k-pill"
            :class="`k-pill--${estadoTone(props.row.estado_sunat)}`"
          >
            <i class="k-dot" />{{ estadoLabel(props.row.estado_sunat) }}
            <q-tooltip v-if="(props.row.estado_sunat === 'rechazado' || props.row.estado_sunat === 'baja_pendiente') && props.row.sunat_error">
              {{ props.row.sunat_error }}
            </q-tooltip>
          </span>
        </q-td>
      </template>

      <!-- Estado de pago -->
      <template #body-cell-pago="props">
        <q-td :props="props">
          <span
            class="k-pill"
            :class="`k-pill--${pagoTone(props.row.estado_pago)}`"
          >
            <i class="k-dot" />{{ props.row.estado_pago ?? 'pendiente' }}
          </span>
        </q-td>
      </template>

      <!-- Total -->
      <template #body-cell-total="props">
        <q-td :props="props">
          <span class="k-total">
            <span class="k-total-cur">{{ props.row.moneda === 'USD' ? 'US$' : 'S/' }}</span>{{ miles(props.row.total) }}
          </span>
        </q-td>
      </template>

      <!-- Acciones -->
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
            @click.stop
          >
            <q-tooltip>Acciones</q-tooltip>
            <q-menu
              anchor="bottom right"
              self="top right"
            >
              <q-list style="min-width: 210px">
                <q-item
                  v-close-popup
                  clickable
                  @click="openDetail($event, props.row)"
                >
                  <q-item-section avatar>
                    <q-icon name="visibility" />
                  </q-item-section>
                  <q-item-section>Ver detalle</q-item-section>
                </q-item>
                <q-item
                  v-close-popup
                  clickable
                  @click="descargar(props.row, 'pdf', 'PDF')"
                >
                  <q-item-section avatar>
                    <q-icon name="picture_as_pdf" />
                  </q-item-section>
                  <q-item-section>Descargar PDF</q-item-section>
                </q-item>
                <q-item
                  v-close-popup
                  clickable
                  @click="descargar(props.row, 'signed_xml', 'XML')"
                >
                  <q-item-section avatar>
                    <q-icon name="code" />
                  </q-item-section>
                  <q-item-section>Descargar XML</q-item-section>
                </q-item>
                <q-item
                  v-close-popup
                  clickable
                  @click="verCDR(props.row)"
                >
                  <q-item-section avatar>
                    <q-icon name="verified" />
                  </q-item-section>
                  <q-item-section>Ver CDR</q-item-section>
                </q-item>
                <q-item
                  v-close-popup
                  clickable
                  @click="enviar(props.row)"
                >
                  <q-item-section avatar>
                    <q-icon name="send" />
                  </q-item-section>
                  <q-item-section>Enviar por email</q-item-section>
                </q-item>
                <q-separator class="q-my-xs" />
                <q-item
                  v-if="props.row.estado_sunat === 'rechazado'"
                  v-close-popup
                  clickable
                  @click="verMotivo(props.row)"
                >
                  <q-item-section avatar>
                    <q-icon
                      name="error_outline"
                      color="negative"
                    />
                  </q-item-section>
                  <q-item-section>Ver motivo de rechazo</q-item-section>
                </q-item>
                <q-item
                  v-if="props.row.estado_sunat === 'pendiente' || props.row.estado_sunat === 'rechazado'"
                  v-close-popup
                  clickable
                  @click="reintentar(props.row)"
                >
                  <q-item-section avatar>
                    <q-icon name="sync" />
                  </q-item-section>
                  <q-item-section>Consultar / reintentar SUNAT</q-item-section>
                </q-item>
                <q-item
                  v-if="props.row.estado_sunat === 'aceptado' && !esNota(props.row.tipo_doc)"
                  v-close-popup
                  clickable
                  @click="emitirNota(props.row, '07')"
                >
                  <q-item-section avatar>
                    <q-icon name="undo" />
                  </q-item-section>
                  <q-item-section>Generar nota de crédito</q-item-section>
                </q-item>
                <q-item
                  v-if="props.row.estado_sunat === 'aceptado' && !esNota(props.row.tipo_doc)"
                  v-close-popup
                  clickable
                  @click="emitirNota(props.row, '08')"
                >
                  <q-item-section avatar>
                    <q-icon name="north_east" />
                  </q-item-section>
                  <q-item-section>Generar nota de débito</q-item-section>
                </q-item>
                <q-item
                  v-if="props.row.estado_sunat !== 'anulado'"
                  v-close-popup
                  clickable
                  class="text-negative"
                  @click="anular(props.row)"
                >
                  <q-item-section avatar>
                    <q-icon
                      name="block"
                      color="negative"
                    />
                  </q-item-section>
                  <q-item-section>Comunicación de baja</q-item-section>
                </q-item>
              </q-list>
            </q-menu>
          </q-btn>
        </q-td>
      </template>

      <!-- Vacío -->
      <template #no-data>
        <div class="k-empty">
          <q-icon
            name="receipt_long"
            size="42px"
            class="k-state-icon"
          />
          <div class="text-subtitle1 q-mt-sm">
            {{ rows.length ? 'Sin coincidencias' : 'Aún no hay comprobantes' }}
          </div>
          <div class="text-caption text-muted">
            {{ rows.length ? 'Ajusta la búsqueda o los filtros.' : 'Emite tu primera venta desde Venta rápida.' }}
          </div>
          <q-btn
            v-if="!rows.length"
            class="q-mt-md"
            color="primary"
            unelevated
            icon="point_of_sale"
            label="Ir a Venta rápida"
            :to="{ name: 'pos' }"
          />
        </div>
      </template>

      <template #loading>
        <KTableSkeleton />
      </template>
    </q-table>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useQuasar, type QTableColumn } from 'quasar'
import { useCompanyStore } from '@/stores/company'
import { useRealtime } from '@/lib/realtime'
import { uid } from '@/lib/uid'
import {
  listDocuments,
  reintentarEmision,
  anularComprobante,
  comunicarBajaSunat,
  descargarArtefactoFiscal,
  type FiscalArtifactKind,
} from '@/modules/documents/documents.api'
import { issueNote } from '@/modules/creditnotes/creditnotes.api'
import { notify } from '@/lib/toast'
import KDate from '@/components/KDate.vue'
import KTableSkeleton from '@/components/KTableSkeleton.vue'
import type { DocumentRow } from '@/types'

const company = useCompanyStore()
// Realtime: refresca la lista al emitir/anular/crear notas (incl. otras pestañas/usuarios).
useRealtime('documents', () => company.current?.id, () => { void load() })
const router = useRouter()
const $q = useQuasar()

const rows = ref<DocumentRow[]>([])
const selected = ref<DocumentRow[]>([])
const loading = ref(false)
const search = ref('')
const tipoFilter = ref<'all' | '03' | '01' | 'nota'>('all')
const estadoFilter = ref<string | null>(null)
const serieFilter = ref<string | null>(null)
const pagoFilter = ref<string | null>(null)
const monedaFilter = ref<string | null>(null)
const desde = ref('')
const hasta = ref('')
const busy = ref(false)
const pagination = ref({ rowsPerPage: 12 })

const hayFiltros = computed(
  () =>
    !!search.value ||
    tipoFilter.value !== 'all' ||
    !!estadoFilter.value ||
    !!serieFilter.value ||
    !!pagoFilter.value ||
    !!monedaFilter.value ||
    !!desde.value ||
    !!hasta.value,
)
function limpiarFiltros() {
  search.value = ''
  tipoFilter.value = 'all'
  estadoFilter.value = null
  serieFilter.value = null
  pagoFilter.value = null
  monedaFilter.value = null
  desde.value = ''
  hasta.value = ''
}

// Recarga desde la BD cuando cambia el rango de fechas (filtrado server-side).
watch([desde, hasta], () => load())

// Motivos de nota de crédito (catálogo 09) y débito (catálogo 10).
const MOTIVOS_NC = [
  { value: '01', desc: 'Anulación de la operación' },
  { value: '02', desc: 'Anulación por error en el RUC' },
  { value: '03', desc: 'Corrección por error en la descripción' },
  { value: '06', desc: 'Devolución total' },
  { value: '07', desc: 'Devolución por ítem' },
]
const MOTIVOS_ND = [
  { value: '01', desc: 'Intereses por mora' },
  { value: '02', desc: 'Aumento en el valor' },
  { value: '03', desc: 'Penalidad / otros conceptos' },
]

const tipoFilters = [
  { label: 'Todos', value: 'all' as const },
  { label: 'Boletas', value: '03' as const },
  { label: 'Facturas', value: '01' as const },
  { label: 'Notas', value: 'nota' as const },
]
const estadoFilters = [
  { label: 'Todos los estados', value: null },
  { label: 'Aceptado', value: 'aceptado' },
  { label: 'Pendiente', value: 'pendiente' },
  { label: 'Rechazado', value: 'rechazado' },
  { label: 'Anulado', value: 'anulado' },
]

/* ---------------- Formato ---------------- */
function numero(r: DocumentRow): string {
  return `${r.serie}-${String(r.correlativo).padStart(8, '0')}`
}
function tipoLabel(t: string): string {
  return t === '01' ? 'Factura' : t === '03' ? 'Boleta' : t === '07' ? 'N. Crédito' : t === '08' ? 'N. Débito' : t
}
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
function miles(n: number | string | null): string {
  return Number(n ?? 0).toLocaleString('es-PE', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}
function fmtFecha(v: string): string {
  // 'YYYY-MM-DD' se parsea como fecha LOCAL para evitar el desfase de un día (UTC).
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v)
  const d = m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : new Date(v)
  return d.toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' })
}
function fmtHora(v: string): string {
  return new Date(v).toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit' })
}
function estadoTone(e: string): 'ok' | 'warn' | 'bad' | 'muted' {
  if (e === 'aceptado') return 'ok'
  if (e === 'rechazado') return 'bad'
  if (e === 'anulado') return 'muted'
  return 'warn'
}
// Etiqueta legible del estado (baja_pendiente → "En baja").
function estadoLabel(e: string): string {
  return e === 'baja_pendiente' ? 'En baja' : e
}
function pagoTone(p?: string | null): 'ok' | 'info' | 'warn' {
  if (p === 'pagado') return 'ok'
  if (p === 'parcial') return 'info'
  return 'warn'
}

/* ---------------- KPIs (sobre el filtro activo) ---------------- */
const kpis = computed(() => {
  const base = filteredRows.value
  const valid = base.filter((r) => r.estado_sunat !== 'anulado')
  // Convierte USD → soles con el tipo de cambio del propio comprobante, para no sumar
  // monedas distintas como si fueran S/.
  const enSoles = (r: DocumentRow, amount: number) =>
    r.moneda === 'USD' ? amount * Number(r.tipo_cambio || 1) : amount
  // Las notas de crédito (07) RESTAN de lo facturado; el resto (01/03/08) suma.
  const facturado = valid.reduce((s, r) => s + (r.tipo_doc === '07' ? -1 : 1) * enSoles(r, Number(r.total || 0)), 0)
  const aceptados = base.filter((r) => r.estado_sunat === 'aceptado').length
  const porCobrar = base
    .filter((r) => r.estado_sunat !== 'anulado' && r.estado_pago && r.estado_pago !== 'pagado')
    .reduce((s, r) => s + enSoles(r, Number(r.saldo ?? r.total ?? 0)), 0)
  return [
    { label: 'Facturado', value: `S/ ${miles(facturado)}`, icon: 'payments', color: 'var(--q-primary)' },
    { label: 'Comprobantes', value: String(base.length), icon: 'description', color: 'var(--k-muted)' },
    {
      label: 'Aceptados',
      value: String(aceptados),
      icon: 'check_circle',
      color: 'var(--q-positive)',
      valueColor: 'var(--q-positive)',
    },
    {
      label: 'Por cobrar',
      value: `S/ ${miles(porCobrar)}`,
      icon: 'schedule',
      color: 'var(--q-warning)',
      valueColor: porCobrar > 0 ? 'var(--q-warning)' : undefined,
    },
  ]
})

/* ---------------- Filtro ---------------- */
function fechaDoc(r: DocumentRow): string {
  return (r.fecha_emision ?? r.created_at ?? '').slice(0, 10)
}
function opt(values: (string | null | undefined)[], todos: string) {
  const uniq = [...new Set(values.filter((v): v is string => !!v))].sort()
  return [{ label: todos, value: null }, ...uniq.map((v) => ({ label: v, value: v }))]
}
const serieOptions = computed(() => opt(rows.value.map((r) => r.serie), 'Todas las series'))
const pagoOptions = computed(() => opt(rows.value.map((r) => r.forma_pago), 'Toda forma de pago'))
const monedaOptions = computed(() => opt(rows.value.map((r) => r.moneda), 'Toda moneda'))

const filteredRows = computed(() => {
  const q = (search.value || '').trim().toLowerCase()
  return rows.value.filter((r) => {
    if (tipoFilter.value === 'nota') {
      if (r.tipo_doc !== '07' && r.tipo_doc !== '08') return false
    } else if (tipoFilter.value !== 'all' && r.tipo_doc !== tipoFilter.value) {
      return false
    }
    if (estadoFilter.value && r.estado_sunat !== estadoFilter.value) return false
    if (serieFilter.value && r.serie !== serieFilter.value) return false
    if (pagoFilter.value && r.forma_pago !== pagoFilter.value) return false
    if (monedaFilter.value && r.moneda !== monedaFilter.value) return false
    const f = fechaDoc(r)
    if (desde.value && f < desde.value) return false
    if (hasta.value && f > hasta.value) return false
    if (!q) return true
    return (
      numero(r).toLowerCase().includes(q) ||
      (r.receptor_denominacion || '').toLowerCase().includes(q) ||
      (r.receptor_num_doc || '').toLowerCase().includes(q)
    )
  })
})

/* ---------------- Acciones por comprobante ---------------- */
const esNota = (t: string) => t === '07' || t === '08'
async function descargar(r: DocumentRow, kind: FiscalArtifactKind, tipo: string) {
  if (!r.fiscal_document_id) {
    notify({ type: 'warning', message: `El ${tipo} todavía no está disponible en Fiscal API.` })
    return
  }
  try {
    await descargarArtefactoFiscal(r, kind)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  }
}
function verCDR(r: DocumentRow) {
  if (!r.cdr || r.cdr.startsWith('SIMULADO')) {
    notify({ type: 'warning', message: 'El CDR estará disponible al emitir con SUNAT real.' })
    return
  }
  notify({ type: 'info', message: `CDR: ${r.cdr}` })
}
async function reintentar(r: DocumentRow) {
  if (!company.current) return
  busy.value = true
  try {
    const { result } = await reintentarEmision(r.id)
    notify({ type: result.estado === 'aceptado' ? 'positive' : 'warning', message: result.mensaje ?? 'Estado actualizado' })
    await load()
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    busy.value = false
  }
}
function anular(r: DocumentRow) {
  if (!company.current) return
  $q.dialog({
    title: 'Comunicación de baja / anulación',
    message: `¿Anular ${numero(r)}? Se revierte el stock y se marca como anulado.`,
    prompt: { model: 'Anulación de la operación', type: 'text' },
    cancel: true,
    persistent: true,
  }).onOk(async (motivo: string) => {
    const wasAccepted = r.estado_sunat === 'aceptado'
    busy.value = true
    try {
      // 1) Anulación local (revierte stock/caja/CxC, marca 'anulado').
      await anularComprobante(company.current!.id, r.id, motivo || 'Anulación')
      // 2) Si estaba ACEPTADO por SUNAT, comunica la baja formal (RA factura/nota · RC boleta).
      if (wasAccepted) {
        const com = await comunicarBajaSunat(company.current!.id, r.id, motivo || 'Anulación de la operación')
        const via = com.tipo === 'RC' ? 'Resumen de baja' : 'Comunicación de baja'
        notify({
          type: com.estado === 'rechazado' ? 'warning' : 'positive',
          message: com.enviada
            ? `${via} ${com.identificador} enviada a SUNAT (${com.estado})`
            : `Anulado. ${via} ${com.identificador} quedó pendiente de envío (despliega la función 'resumen')`,
        })
      } else {
        notify({ type: 'positive', message: 'Comprobante anulado' })
      }
      await load()
    } catch (e) {
      notify({ type: 'negative', message: (e as Error).message })
    } finally {
      busy.value = false
    }
  })
}
function emitirNota(r: DocumentRow, tipo: '07' | '08') {
  if (!company.current) return
  const motivos = tipo === '07' ? MOTIVOS_NC : MOTIVOS_ND
  $q.dialog({
    title: tipo === '07' ? 'Nota de crédito' : 'Nota de débito',
    message: `Sobre ${numero(r)} · elige el motivo`,
    options: {
      type: 'radio',
      model: motivos[0].value,
      items: motivos.map((m) => ({ label: `${m.value} · ${m.desc}`, value: m.value })),
    },
    cancel: true,
    persistent: true,
  }).onOk(async (codigo: string) => {
    const desc = motivos.find((m) => m.value === codigo)?.desc ?? ''
    busy.value = true
    // Llave estable por intento → el RPC deduplica y no emite una segunda nota.
    const notaKey = uid()
    try {
      await issueNote(company.current!.id, r.id, tipo, codigo, desc, undefined, notaKey)
      notify({ type: 'positive', message: `${tipo === '07' ? 'Nota de crédito' : 'Nota de débito'} emitida` })
      await load()
    } catch (e) {
      notify({ type: 'negative', message: (e as Error).message })
    } finally {
      busy.value = false
    }
  })
}
function verMotivo(r: DocumentRow) {
  $q.dialog({
    title: `Motivo de rechazo · ${numero(r)}`,
    message: r.sunat_error || 'SUNAT no devolvió un detalle. Reintenta la consulta de estado.',
  })
}
function enviar(r: DocumentRow) {
  if (!r.receptor_denominacion) return
  notify({ type: 'info', message: 'Envío por email/WhatsApp: disponible al desplegar la Edge Function de notificaciones.' })
}

/* ---------------- Acciones masivas (selección múltiple) ---------------- */
async function bulkDescargar(kind: FiscalArtifactKind, tipo: string) {
  const con = selected.value.filter((r) => Boolean(r.fiscal_document_id))
  if (!con.length) {
    notify({ type: 'warning', message: `Ninguno de los seleccionados tiene ${tipo} en Fiscal API.` })
    return
  }
  for (const document of con) await descargar(document, kind, tipo)
}
function bulkEnviar() {
  notify({ type: 'info', message: `Envío masivo de ${selected.value.length} comprobante(s): al desplegar la función de notificaciones.` })
}
function bulkAnular() {
  // Solo sobre filas VISIBLES (si se cambió el filtro tras seleccionar, no anular
  // comprobantes ocultos/no revisados).
  const visibles = new Set(filteredRows.value.map((r) => r.id))
  const items = selected.value.filter((r) => r.estado_sunat !== 'anulado' && visibles.has(r.id))
  if (!items.length) {
    notify({ type: 'warning', message: 'No hay comprobantes visibles anulables en la selección.' })
    return
  }
  $q.dialog({
    title: 'Anulación masiva',
    message: `¿Anular ${items.length} comprobante(s)? Se revierte el stock de cada uno.`,
    cancel: true,
    persistent: true,
  }).onOk(async () => {
    busy.value = true
    let ok = 0
    let comunicadas = 0
    let fallas = 0
    let primerError = ''
    for (const r of items) {
      const wasAccepted = r.estado_sunat === 'aceptado'
      try {
        await anularComprobante(company.current!.id, r.id, 'Anulación masiva')
        ok++
        if (wasAccepted) {
          try {
            await comunicarBajaSunat(company.current!.id, r.id, 'Anulación de la operación')
            comunicadas++
          } catch {
            /* la anulación local sí quedó; la baja se puede reintentar */
          }
        }
      } catch (e) {
        fallas++
        if (!primerError) primerError = (e as Error).message
      }
    }
    // No enmascarar fallos: si algo falló (RLS/permiso/lock), el toast NO es positivo.
    notify({
      type: fallas === 0 ? 'positive' : ok === 0 ? 'negative' : 'warning',
      message:
        `${ok}/${items.length} anulado(s)` +
        (comunicadas ? ` · ${comunicadas} comunicada(s) a SUNAT` : '') +
        (fallas ? ` · ${fallas} con error${primerError ? ': ' + primerError : ''}` : ''),
    })
    selected.value = []
    await load()
    busy.value = false
  })
}

/* ---------------- Exportar (registro de ventas · Excel) ---------------- */
function exportXls() {
  const head = ['Tipo', 'Numero', 'Fecha', 'Cliente', 'Documento', 'Moneda', 'Gravado', 'IGV', 'Total', 'Estado SUNAT', 'Estado pago']
  const cell = (v: unknown) => {
    let s = String(v ?? '')
    // Neutraliza inyección de fórmulas: un valor de texto que empieza con = + - @
    // podría ejecutarse como fórmula al abrir el archivo. Se antepone un apóstrofo
    // (Excel lo trata como texto). No aplica a números (totales).
    if (/^[=+\-@\t\r]/.test(s) && isNaN(Number(s))) s = "'" + s
    return `<td>${s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c] as string)}</td>`
  }
  const trs = filteredRows.value
    .map((r) =>
      `<tr>${[
        tipoLabel(r.tipo_doc),
        numero(r),
        fechaDoc(r),
        r.receptor_denominacion ?? '',
        r.receptor_num_doc ?? '',
        r.moneda ?? 'PEN',
        Number(r.total_gravado ?? 0).toFixed(2),
        Number(r.total_igv ?? 0).toFixed(2),
        Number(r.total ?? 0).toFixed(2),
        r.estado_sunat ?? '',
        r.estado_pago ?? '',
      ].map(cell).join('')}</tr>`,
    )
    .join('')
  const html =
    `<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel">` +
    `<head><meta charset="utf-8"></head><body><table border="1"><thead><tr>` +
    head.map((h) => `<th>${h}</th>`).join('') +
    `</tr></thead><tbody>${trs}</tbody></table></body></html>`
  const blob = new Blob(['﻿' + html], { type: 'application/vnd.ms-excel' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `comprobantes-${new Date().toISOString().slice(0, 10)}.xls`
  a.click()
  URL.revokeObjectURL(url)
}

const columns: QTableColumn<DocumentRow>[] = [
  { name: 'numero', label: 'Comprobante', field: 'correlativo', align: 'left', sortable: true },
  { name: 'cliente', label: 'Cliente', field: (r) => r.receptor_denominacion ?? '', align: 'left' },
  { name: 'fecha', label: 'Fecha', field: (r) => r.fecha_emision ?? r.created_at, align: 'left', sortable: true },
  { name: 'estado', label: 'Estado', field: 'estado_sunat', align: 'left' },
  { name: 'pago', label: 'Pago', field: (r) => r.estado_pago ?? 'pendiente', align: 'left' },
  { name: 'total', label: 'Total', field: 'total', align: 'right', sortable: true },
  { name: 'acciones', label: '', field: 'id', align: 'right' },
]

/* ---------------- Datos ---------------- */
function openDetail(_evt: Event, row: DocumentRow) {
  router.push({ name: 'document-detail', params: { id: row.id } })
}

async function load() {
  if (!company.current) return
  loading.value = !rows.value.length
  selected.value = []
  try {
    rows.value = await listDocuments(company.current.id, {
      desde: desde.value || undefined,
      hasta: hasta.value || undefined,
      limit: 1000,
    })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<style scoped>
/* ---------- Contenedor de filtros ---------- */
.k-filters-card {
  padding: 14px 16px;
}
/* Los filtros fluyen y se envuelven; cada uno tan ancho como su contenido. */
.k-filter-flow {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  align-items: center;
}
/* Solo el buscador tiene ancho grande y crece para llenar el espacio libre. */
.k-ff-search {
  flex: 1 1 340px;
  min-width: 280px;
}
/* El resto: el ancho depende del texto/valor que muestran. */
.k-ff-item {
  width: max-content;
  max-width: 100%;
  min-width: 5rem; /* piso mínimo para que no se corte la etiqueta flotante */
}

/* ---------- KPIs (stat tiles) ---------- */
.k-stat {
  padding: 16px 18px;
}
/* Neutraliza el margin-bottom global de 30px (esa card no lleva sección) */
.k-stat > :last-child {
  margin-bottom: 0 !important;
}
.k-stat-label {
  display: flex;
  align-items: center;
  gap: 6px;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.4px;
  color: var(--k-muted);
  margin-bottom: 10px;
}
.k-stat-value {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 22px;
  font-weight: 800;
  letter-spacing: -0.5px;
  color: var(--k-text);
  line-height: 1.1;
}

/* ---------- Control segmentado (filtro de tipo) ---------- */
.k-seg {
  display: inline-flex;
  gap: 3px;
  padding: 3px;
  border-radius: var(--k-radius-sm);
  background: var(--k-surface-2);
}
.k-seg-btn {
  border: none;
  background: transparent;
  color: var(--k-muted);
  font-family: inherit;
  font-weight: 600;
  font-size: 13px;
  padding: 6px 14px;
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
.body--dark .k-seg-btn--on {
  background: var(--k-active-bg);
  color: var(--k-active-text);
  box-shadow: 0 0 0 1px color-mix(in srgb, var(--q-primary) 45%, transparent);
}

/* ---------- Tabla ---------- */
.k-doc-table :deep(tbody tr) {
  transition: background 0.12s ease;
}
.k-doc-table :deep(tbody td) {
  padding-top: 10px;
  padding-bottom: 10px;
}

/* Celda comprobante */
.k-doc {
  display: flex;
  align-items: center;
  gap: 11px;
}
.k-doc-ic {
  width: 34px;
  height: 34px;
  border-radius: 9px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.k-doc-num {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-weight: 700;
  font-size: 13px;
}
.k-doc-tipo {
  font-size: 11px;
  color: var(--k-muted);
}

/* Celda cliente */
.k-cli-name {
  font-weight: 600;
  font-size: 13px;
  max-width: 230px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.k-cli-doc {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  color: var(--k-muted);
}

/* Celda fecha */
.k-fecha-d {
  font-size: 13px;
}
.k-fecha-h {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  color: var(--k-muted);
}

/* Píldoras de estado (tinte + hairline del color + punto con halo · Linear/Stripe) */
.k-pill {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  padding: 4px 12px 4px 10px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 700;
  line-height: 1;
  letter-spacing: 0.2px;
  text-transform: capitalize;
  box-shadow: inset 0 0 0 1px color-mix(in srgb, currentColor 22%, transparent);
}
.k-pill .k-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: currentColor;
  flex-shrink: 0;
  box-shadow: 0 0 0 3px color-mix(in srgb, currentColor 16%, transparent);
}
.k-pill--ok {
  color: var(--q-positive);
  background: color-mix(in srgb, var(--q-positive) 15%, transparent);
}
.k-pill--warn {
  color: #b7791f;
  background: color-mix(in srgb, var(--q-warning) 18%, transparent);
}
.body--dark .k-pill--warn {
  color: #fbbf24;
}
.k-pill--bad {
  color: var(--q-negative);
  background: color-mix(in srgb, var(--q-negative) 15%, transparent);
}
.k-pill--info {
  color: var(--q-info);
  background: color-mix(in srgb, var(--q-info) 16%, transparent);
}
.k-pill--muted {
  color: var(--k-muted);
  background: color-mix(in srgb, var(--k-muted) 18%, transparent);
}

/* Celda total */
.k-total {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-weight: 700;
  font-size: 14px;
}
.k-total-cur {
  color: var(--k-muted);
  font-size: 11px;
  font-weight: 600;
  margin-right: 3px;
}

/* Botón de acciones (⋮): más área de toque + despegado del borde */
.k-act-td {
  padding-right: 14px !important;
}
.k-act-btn {
  color: var(--k-muted);
  width: 40px;
  height: 40px;
}
.k-act-btn:hover {
  color: var(--k-text);
  background: var(--k-active-bg);
}

/* Barra de acciones masivas */
.k-bulk {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 14px;
  margin-bottom: 12px;
  border-radius: var(--k-radius-sm);
  background: var(--k-active-bg);
  color: var(--k-text);
}
.k-bulk-count {
  font-weight: 700;
  font-size: 13px;
}

/* Estado vacío */
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
</style>
  color: var(--k-muted);
  opacity: 0.6;
}
</style>
