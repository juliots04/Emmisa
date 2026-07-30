<template>
  <q-page class="q-pa-md">
    <div class="row items-center q-mb-md">
      <div class="text-h5">
        Cotizaciones
      </div>
      <q-space />
      <q-btn
        color="primary"
        icon="add"
        label="Nueva cotización"
        @click="openNew"
      />
    </div>

    <q-table
      :rows="rows"
      :columns="columns"
      row-key="id"
      :loading="loading"
      flat
      bordered
    >
      <template #body-cell-estado="props">
        <q-td :props="props">
          <q-badge
            :color="props.value === 'convertida' ? 'positive' : 'grey'"
            :label="props.value"
          />
        </q-td>
      </template>
      <template #body-cell-acciones="props">
        <q-td
          :props="props"
          class="text-right"
        >
          <q-btn
            flat
            dense
            round
            icon="picture_as_pdf"
            @click="printQuote(props.row)"
          >
            <q-tooltip>Imprimir / PDF</q-tooltip>
          </q-btn>
          <q-btn
            flat
            dense
            round
            icon="point_of_sale"
            :disable="props.row.estado === 'convertida'"
            @click="openConvert(props.row)"
          >
            <q-tooltip>{{ props.row.estado === 'convertida' ? 'Ya convertida' : 'Convertir a venta' }}</q-tooltip>
          </q-btn>
        </q-td>
      </template>
      <template #loading>
        <KTableSkeleton />
      </template>
    </q-table>

    <!-- ==================== DIÁLOGO CONVERTIR A VENTA ==================== -->
    <q-dialog v-model="showConvert">
      <q-card class="k-dialog-sm">
        <q-card-section class="k-modal-head">
          <div class="text-h6">
            Convertir a venta
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
        <q-card-section class="q-gutter-sm">
          <q-select
            v-model="convert.tipoDoc"
            outlined
            emit-value
            map-options
            :options="tipoDocOptions"
            label="Tipo de comprobante"
          />
          <q-input
            v-model="convert.denominacion"
            outlined
            :label="convert.tipoDoc === '01' ? 'Razón social' : 'Nombre del cliente'"
            :rules="nameRules"
          />
          <q-input
            v-model="convert.numDoc"
            outlined
            :label="convert.tipoDoc === '01' ? 'RUC (11 dígitos)' : 'DNI (opcional)'"
            :mask="convert.tipoDoc === '01' ? '###########' : '########'"
            :rules="convert.tipoDoc === '01' ? rucRules : []"
          />
          <q-input
            v-model="convert.direccion"
            outlined
            label="Dirección (opcional)"
          />
          <div class="text-caption text-grey">
            Total: S/ {{ Number(convertQuote?.total ?? 0).toFixed(2) }}
          </div>
        </q-card-section>
        <q-card-actions align="right">
          <q-btn
            v-close-popup
            flat
            label="Cancelar"
          />
          <q-btn
            color="primary"
            label="Emitir venta"
            :loading="converting"
            @click="doConvert"
          />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <!-- ==================== DIÁLOGO NUEVA COTIZACIÓN ==================== -->
    <q-dialog v-model="show">
      <q-card class="k-dialog-md">
        <q-card-section class="k-modal-head">
          <div class="text-h6">
            Nueva cotización
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
        <q-card-section class="q-gutter-sm">
          <q-input
            v-model="form.cliente_nombre"
            outlined
            label="Cliente"
            autofocus
            :rules="nameRules"
          />
          <q-input
            v-model="form.fecha"
            outlined
            type="date"
            label="Fecha"
            stack-label
            :rules="fechaRules"
          />

          <div class="text-subtitle2 q-mt-md">
            Ítems
          </div>
          <div
            v-for="(item, i) in form.items"
            :key="i"
            class="row q-col-gutter-sm items-center"
          >
            <div class="col-4">
              <q-select
                v-model="item.product_id"
                :options="productOptions"
                emit-value
                map-options
                options-dense
                clearable
                outlined
                dense
                label="Producto (opcional)"
                hide-bottom-space
                @update:model-value="(v) => onPickQuoteProduct(i, v)"
              />
            </div>
            <div class="col">
              <q-input
                v-model="item.descripcion"
                outlined
                dense
                label="Descripción"
                :rules="nameRules"
                lazy-rules="ondemand"
                hide-bottom-space
              />
            </div>
            <div class="col-2">
              <q-input
                v-model.number="item.cantidad"
                outlined
                dense
                type="number"
                label="Cant."
                :rules="qtyRules"
                lazy-rules="ondemand"
                hide-bottom-space
              />
            </div>
            <div class="col-2">
              <q-input
                v-model.number="item.precio_unitario"
                outlined
                dense
                type="number"
                label="Precio"
                :rules="priceRules"
                lazy-rules="ondemand"
                hide-bottom-space
              />
            </div>
            <div class="col-auto">
              <q-btn
                flat
                round
                dense
                icon="delete"
                :disable="form.items.length === 1"
                @click="removeItem(i)"
              />
            </div>
          </div>
          <q-btn
            flat
            dense
            icon="add"
            label="Agregar ítem"
            @click="addItem"
          />

          <div class="row justify-end q-mt-md text-subtitle1">
            Total: S/ {{ total.toFixed(2) }}
          </div>
        </q-card-section>
        <q-card-actions align="right">
          <q-btn
            v-close-popup
            flat
            label="Cancelar"
          />
          <q-btn
            color="primary"
            label="Guardar"
            :loading="saving"
            @click="save"
          />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { type QTableColumn } from 'quasar'
import KTableSkeleton from '@/components/KTableSkeleton.vue'
import { useCompanyStore } from '@/stores/company'
import { useRealtime } from '@/lib/realtime'
import { notify } from '@/lib/toast'
import {
  listQuotes,
  createQuote,
  convertQuoteToSale,
  getQuoteItems,
  type Quote,
} from '@/modules/quotes/quotes.api'
import type { TipoDoc, Product } from '@/types'
import { listProducts } from '@/modules/products/products.api'
import {
  validate,
  required,
  ruc,
  nameRules,
  qtyRules,
  priceRules,
  type Rule,
} from '@/lib/validation'

const company = useCompanyStore()
// Realtime: refresca la lista al crear/convertir cotizaciones.
useRealtime('quotes', () => company.current?.id, () => { void load() })

const fechaRules: Rule[] = [required('Fecha obligatoria')]

function today(): string {
  // Fecha local (no UTC): de noche en Perú, toISOString ya está en el día siguiente.
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

const rows = ref<Quote[]>([])
const loading = ref(false)
const show = ref(false)
const saving = ref(false)

// ---------- Conversión a venta ----------
const showConvert = ref(false)
const converting = ref(false)
const convertQuote = ref<Quote | null>(null)
const convert = ref<{ tipoDoc: TipoDoc; denominacion: string; numDoc: string; direccion: string }>({
  tipoDoc: '03',
  denominacion: '',
  numDoc: '',
  direccion: '',
})
const tipoDocOptions = [
  { label: 'Boleta', value: '03' },
  { label: 'Factura', value: '01' },
]
// Usa el validador central (dígito verificador módulo-11), no solo 11 dígitos.
const rucRules: Rule[] = [required('Ingresa el RUC'), ruc]

interface QuoteItemForm {
  descripcion: string
  cantidad: number
  precio_unitario: number
  product_id: string | null
  tipo_afectacion: string
  unidad_medida: string
}
const newQuoteItem = (): QuoteItemForm => ({
  descripcion: '', cantidad: 1, precio_unitario: 0, product_id: null, tipo_afectacion: '10', unidad_medida: 'NIU',
})

const form = ref<{
  cliente_nombre: string
  fecha: string
  items: QuoteItemForm[]
}>({
  cliente_nombre: '',
  fecha: today(),
  items: [newQuoteItem()],
})

const total = computed(() =>
  form.value.items.reduce(
    (acc, it) => acc + (Number(it.cantidad) || 0) * (Number(it.precio_unitario) || 0),
    0,
  ),
)

const columns: QTableColumn<Quote>[] = [
  { name: 'fecha', label: 'Fecha', field: 'fecha', align: 'left', sortable: true },
  { name: 'cliente', label: 'Cliente', field: 'cliente_nombre', align: 'left', sortable: true },
  {
    name: 'total',
    label: 'Total',
    field: 'total',
    align: 'right',
    format: (v) => `S/ ${Number(v).toFixed(2)}`,
  },
  { name: 'estado', label: 'Estado', field: 'estado', align: 'left' },
  { name: 'acciones', label: 'Acciones', field: 'id', align: 'right' },
]

function addItem() {
  form.value.items.push(newQuoteItem())
}

function removeItem(i: number) {
  form.value.items.splice(i, 1)
}

const products = ref<Product[]>([])
const productOptions = computed(() =>
  products.value.map((p) => ({ label: `${p.nombre} (S/ ${p.precio})`, value: p.id })),
)
// Al elegir un producto del catálogo: rellena descripción, precio (a bruto), afectación y unidad
// → al convertir la cotización a venta se emite con el IGV correcto (no todo forzado a gravado).
function onPickQuoteProduct(i: number, productId: string | null) {
  const p = products.value.find((x) => x.id === productId)
  if (!p) return
  const it = form.value.items[i]
  it.descripcion = p.nombre
  const bruto = p.incluye_igv === false && (p.tipo_afectacion ?? '10') === '10' ? Number(p.precio) * 1.18 : Number(p.precio)
  it.precio_unitario = Number(bruto.toFixed(2))
  it.tipo_afectacion = p.tipo_afectacion ?? '10'
  it.unidad_medida = p.unidad_medida ?? 'NIU'
}

function openNew() {
  form.value = {
    cliente_nombre: '',
    fecha: today(),
    items: [newQuoteItem()],
  }
  show.value = true
}

async function load() {
  if (!company.current) return
  loading.value = !rows.value.length
  try {
    rows.value = await listQuotes(company.current.id)
    if (!products.value.length) products.value = await listProducts(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
}

async function save() {
  if (!company.current) return

  const fields: Array<[unknown, Rule[]]> = [
    [form.value.cliente_nombre, nameRules],
    [form.value.fecha, fechaRules],
  ]
  for (const it of form.value.items) {
    fields.push([it.descripcion, nameRules])
    fields.push([it.cantidad, qtyRules])
    fields.push([it.precio_unitario, priceRules])
  }
  const err = validate(fields)
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }

  saving.value = true
  try {
    await createQuote(company.current.id, {
      cliente_nombre: form.value.cliente_nombre,
      fecha: form.value.fecha,
      items: form.value.items,
    })
    show.value = false
    await load()
    notify({ type: 'positive', message: 'Cotización creada' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    saving.value = false
  }
}

function openConvert(quote: Quote) {
  convertQuote.value = quote
  convert.value = { tipoDoc: '03', denominacion: quote.cliente_nombre || '', numDoc: '', direccion: '' }
  showConvert.value = true
}

async function doConvert() {
  if (!company.current || !convertQuote.value) return
  const fields: Array<[unknown, Rule[]]> = [[convert.value.denominacion, nameRules]]
  if (convert.value.tipoDoc === '01') fields.push([convert.value.numDoc, rucRules])
  const err = validate(fields)
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  // Tipo de doc del receptor (cat.06): 6 RUC, 1 DNI, 0 sin documento (boleta genérica).
  const clienteTipoDoc = convert.value.tipoDoc === '01' ? '6' : convert.value.numDoc ? '1' : '0'
  converting.value = true
  try {
    const { document, result } = await convertQuoteToSale(
      company.current.id,
      convertQuote.value,
      convert.value.tipoDoc,
      {
        tipoDoc: clienteTipoDoc,
        numDoc: convert.value.numDoc || undefined,
        denominacion: convert.value.denominacion,
        direccion: convert.value.direccion || undefined,
      },
    )
    showConvert.value = false
    await load()
    const numero = `${document.serie}-${String(document.correlativo).padStart(8, '0')}`
    // No reportar "emitida" en verde si SUNAT rechazó o quedó pendiente.
    if (result.estado === 'rechazado') {
      notify({ type: 'negative', message: `SUNAT rechazó ${numero}. Revisa los datos del comprobante.` })
    } else {
      notify({
        type: result.estado === 'aceptado' ? 'positive' : 'warning',
        message: result.estado === 'aceptado' ? `Venta emitida: ${numero}` : `Comprobante ${numero} en proceso en SUNAT`,
      })
    }
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    converting.value = false
  }
}

function escapeHtml(s: string): string {
  const map: Record<string, string> = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }
  return s.replace(/[&<>"']/g, (c) => map[c])
}

/** Abre una vista imprimible (Guardar como PDF desde el diálogo de impresión). */
async function printQuote(quote: Quote) {
  try {
    const items = await getQuoteItems(quote.id)
    const empresa = company.current?.razon_social ?? 'Cotización'
    const filas = items
      .map(
        (it) =>
          `<tr><td>${escapeHtml(it.descripcion)}</td><td class="r">${Number(it.cantidad)}</td>` +
          `<td class="r">${Number(it.precio_unitario).toFixed(2)}</td><td class="r">${Number(it.total).toFixed(2)}</td></tr>`,
      )
      .join('')
    const html = `<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Cotización</title>
      <style>
        body{font-family:Arial,Helvetica,sans-serif;color:#111;padding:32px;max-width:720px;margin:auto}
        h1{font-size:20px;margin:0 0 4px}.muted{color:#666;font-size:13px}
        table{width:100%;border-collapse:collapse;margin-top:20px;font-size:14px}
        th,td{border-bottom:1px solid #ddd;padding:8px;text-align:left}.r{text-align:right}
        tfoot td{font-weight:bold;border-top:2px solid #333}
        .head{display:flex;justify-content:space-between;align-items:flex-start}
      </style></head><body>
      <div class="head">
        <div><h1>${escapeHtml(empresa)}</h1><div class="muted">COTIZACIÓN</div></div>
        <div class="muted">Fecha: ${escapeHtml(quote.fecha)}</div>
      </div>
      <div class="muted" style="margin-top:12px">Cliente: ${escapeHtml(quote.cliente_nombre)}</div>
      <table>
        <thead><tr><th>Descripción</th><th class="r">Cant.</th><th class="r">P. Unit.</th><th class="r">Total</th></tr></thead>
        <tbody>${filas}</tbody>
        <tfoot><tr><td colspan="3" class="r">TOTAL ${escapeHtml(quote.moneda)}</td><td class="r">${Number(quote.total).toFixed(2)}</td></tr></tfoot>
      </table>
      <p class="muted" style="margin-top:24px">Documento informativo. No válido como comprobante de pago.</p>
      </body></html>`
    const w = window.open('', '_blank', 'width=820,height=920')
    if (!w) {
      notify({ type: 'warning', message: 'Permite las ventanas emergentes para imprimir/descargar' })
      return
    }
    w.document.write(html)
    w.document.close()
    w.focus()
    w.print()
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  }
}

onMounted(load)
</script>
