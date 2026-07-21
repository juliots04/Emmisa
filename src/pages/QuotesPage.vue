<template>
  <q-page class="q-pa-md">
    <div class="row items-center q-mb-md">
      <div class="text-h5">Cotizaciones</div>
      <q-space />
      <q-btn color="primary" icon="add" label="Nueva cotización" @click="openNew" />
    </div>

    <q-table :rows="rows" :columns="columns" row-key="id" :loading="loading" flat bordered />

    <!-- ==================== DIÁLOGO NUEVA COTIZACIÓN ==================== -->
    <q-dialog v-model="show">
      <q-card style="min-width: 480px">
        <q-card-section class="text-h6">Nueva cotización</q-card-section>
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

          <div class="text-subtitle2 q-mt-md">Ítems</div>
          <div v-for="(item, i) in form.items" :key="i" class="row q-col-gutter-sm items-center">
            <div class="col">
              <q-input
                v-model="item.descripcion"
                outlined
                dense
                label="Descripción"
                :rules="nameRules"
                lazy-rules
                hide-bottom-space
              />
            </div>
            <div class="col-3">
              <q-input
                v-model.number="item.cantidad"
                outlined
                dense
                type="number"
                label="Cant."
                :rules="qtyRules"
                lazy-rules
                hide-bottom-space
              />
            </div>
            <div class="col-3">
              <q-input
                v-model.number="item.precio_unitario"
                outlined
                dense
                type="number"
                label="Precio"
                :rules="priceRules"
                lazy-rules
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
          <q-btn flat dense icon="add" label="Agregar ítem" @click="addItem" />

          <div class="row justify-end q-mt-md text-subtitle1">Total: S/ {{ total.toFixed(2) }}</div>
        </q-card-section>
        <q-card-actions align="right">
          <q-btn v-close-popup flat label="Cancelar" />
          <q-btn color="primary" label="Guardar" :loading="saving" @click="save" />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { type QTableColumn } from 'quasar'
import { useCompanyStore } from '@/stores/company'
import { notify } from '@/lib/toast'
import { listQuotes, createQuote, type Quote } from '@/modules/quotes/quotes.api'
import {
  validate,
  required,
  nameRules,
  qtyRules,
  priceRules,
  type Rule,
} from '@/lib/validation'

const company = useCompanyStore()

const fechaRules: Rule[] = [required('Fecha obligatoria')]

function today(): string {
  return new Date().toISOString().slice(0, 10)
}

const rows = ref<Quote[]>([])
const loading = ref(false)
const show = ref(false)
const saving = ref(false)

interface QuoteItemForm {
  descripcion: string
  cantidad: number
  precio_unitario: number
}

const form = ref<{
  cliente_nombre: string
  fecha: string
  items: QuoteItemForm[]
}>({
  cliente_nombre: '',
  fecha: today(),
  items: [{ descripcion: '', cantidad: 1, precio_unitario: 0 }],
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
]

function addItem() {
  form.value.items.push({ descripcion: '', cantidad: 1, precio_unitario: 0 })
}

function removeItem(i: number) {
  form.value.items.splice(i, 1)
}

function openNew() {
  form.value = {
    cliente_nombre: '',
    fecha: today(),
    items: [{ descripcion: '', cantidad: 1, precio_unitario: 0 }],
  }
  show.value = true
}

async function load() {
  if (!company.current) return
  loading.value = true
  try {
    rows.value = await listQuotes(company.current.id)
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

onMounted(load)
</script>
