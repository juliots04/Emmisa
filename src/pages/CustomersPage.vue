<template>
  <q-page class="q-pa-md">
    <div class="row items-center q-mb-md">
      <div class="text-h5">Clientes</div>
      <q-space />
      <q-btn color="primary" icon="add" label="Nuevo" @click="openNew" />
    </div>

    <q-table :rows="rows" :columns="columns" row-key="id" :loading="loading" flat bordered />

    <q-dialog v-model="show">
      <q-card style="min-width: 340px">
        <q-card-section class="text-h6">Nuevo cliente</q-card-section>
        <q-card-section class="q-gutter-sm">
          <q-input
            v-model="form.denominacion"
            label="Nombre / Razón social"
            :rules="nameRules"
            lazy-rules
            autofocus
          />
          <q-select v-model="form.tipo_doc" :options="docOptions" emit-value map-options label="Tipo de documento" />
          <q-input
            v-model="form.num_doc"
            :label="form.tipo_doc === '6' ? 'RUC' : 'DNI'"
            :rules="[docByTipo(form.tipo_doc, false)]"
            lazy-rules
          />
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
import { onMounted, ref } from 'vue'
import { type QTableColumn } from 'quasar'
import { useCompanyStore } from '@/stores/company'
import { listCustomers, createCustomer } from '@/modules/customers/customers.api'
import { validate, nameRules, docByTipo } from '@/lib/validation'
import { notify } from '@/lib/toast'
import type { Customer } from '@/types'

const company = useCompanyStore()
const rows = ref<Customer[]>([])
const loading = ref(false)
const show = ref(false)
const saving = ref(false)
const form = ref({ denominacion: '', tipo_doc: '1', num_doc: '' })

const docOptions = [
  { label: 'DNI', value: '1' },
  { label: 'RUC', value: '6' },
]

const columns: QTableColumn<Customer>[] = [
  { name: 'denominacion', label: 'Nombre', field: 'denominacion', align: 'left', sortable: true },
  {
    name: 'tipo',
    label: 'Tipo',
    field: (r) => (r.tipo_doc === '6' ? 'RUC' : 'DNI'),
    align: 'left',
  },
  { name: 'num_doc', label: 'Documento', field: 'num_doc', align: 'left' },
]

function openNew() {
  form.value = { denominacion: '', tipo_doc: '1', num_doc: '' }
  show.value = true
}

async function load() {
  if (!company.current) return
  loading.value = true
  try {
    rows.value = await listCustomers(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
}

async function save() {
  if (!company.current) return
  const err = validate([
    [form.value.denominacion, nameRules],
    [form.value.num_doc, [docByTipo(form.value.tipo_doc, false)]],
  ])
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  saving.value = true
  try {
    await createCustomer(company.current.id, form.value)
    show.value = false
    await load()
    notify({ type: 'positive', message: 'Cliente creado' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    saving.value = false
  }
}

onMounted(load)
</script>
