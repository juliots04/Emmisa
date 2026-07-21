<template>
  <q-page class="q-pa-md">
    <div class="row items-center q-mb-md">
      <div class="text-h5">Clientes</div>
      <q-space />
      <q-btn color="primary" icon="add" label="Nuevo" @click="openNew" />
    </div>

    <q-table :rows="rows" :columns="columns" row-key="id" :loading="loading" flat bordered>
      <template #body-cell-acciones="props">
        <q-td :props="props" class="text-right">
          <q-btn flat round dense icon="edit" size="sm" @click="openEdit(props.row)" />
          <q-btn flat round dense icon="delete" size="sm" color="negative" @click="remove(props.row)" />
        </q-td>
      </template>
    </q-table>

    <q-dialog v-model="show">
      <q-card style="min-width: 360px">
        <q-card-section class="text-h6">{{ editingId ? 'Editar cliente' : 'Nuevo cliente' }}</q-card-section>
        <q-card-section class="q-gutter-sm">
          <q-input v-model="form.denominacion" label="Nombre / Razón social" :rules="nameRules" lazy-rules autofocus />
          <q-select v-model="form.tipo_doc" :options="docOptions" emit-value map-options label="Tipo de documento" />
          <q-input
            v-model="form.num_doc"
            :label="form.tipo_doc === '6' ? 'RUC' : 'DNI'"
            :rules="[docByTipo(form.tipo_doc, false)]"
            lazy-rules
          />
          <q-input v-model="form.email" label="Email (opcional)" type="email" />
          <q-input v-model="form.direccion" label="Dirección (opcional)" />
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
import { useQuasar, type QTableColumn } from 'quasar'
import { useCompanyStore } from '@/stores/company'
import { listCustomers, createCustomer, updateCustomer, deleteCustomer } from '@/modules/customers/customers.api'
import { validate, nameRules, docByTipo } from '@/lib/validation'
import { notify } from '@/lib/toast'
import type { Customer } from '@/types'

const $q = useQuasar()
const company = useCompanyStore()
const rows = ref<Customer[]>([])
const loading = ref(false)
const show = ref(false)
const saving = ref(false)
const editingId = ref<string | null>(null)
const form = ref({ denominacion: '', tipo_doc: '1', num_doc: '', email: '', direccion: '' })

const docOptions = [
  { label: 'DNI', value: '1' },
  { label: 'RUC', value: '6' },
]

const columns: QTableColumn<Customer>[] = [
  { name: 'denominacion', label: 'Nombre', field: 'denominacion', align: 'left', sortable: true },
  { name: 'tipo', label: 'Tipo', field: (r) => (r.tipo_doc === '6' ? 'RUC' : 'DNI'), align: 'left' },
  { name: 'num_doc', label: 'Documento', field: 'num_doc', align: 'left' },
  { name: 'email', label: 'Email', field: (r) => r.email ?? '—', align: 'left' },
  { name: 'acciones', label: '', field: 'id', align: 'right' },
]

function openNew() {
  editingId.value = null
  form.value = { denominacion: '', tipo_doc: '1', num_doc: '', email: '', direccion: '' }
  show.value = true
}

function openEdit(row: Customer) {
  editingId.value = row.id
  form.value = {
    denominacion: row.denominacion,
    tipo_doc: row.tipo_doc,
    num_doc: row.num_doc ?? '',
    email: row.email ?? '',
    direccion: row.direccion ?? '',
  }
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
    const payload = {
      denominacion: form.value.denominacion,
      tipo_doc: form.value.tipo_doc,
      num_doc: form.value.num_doc || null,
      email: form.value.email || null,
      direccion: form.value.direccion || null,
    }
    if (editingId.value) await updateCustomer(editingId.value, payload)
    else await createCustomer(company.current.id, payload)
    show.value = false
    await load()
    notify({ type: 'positive', message: editingId.value ? 'Cliente actualizado' : 'Cliente creado' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    saving.value = false
  }
}

function remove(row: Customer) {
  $q.dialog({
    title: 'Eliminar cliente',
    message: `¿Eliminar a "${row.denominacion}"?`,
    cancel: true,
    persistent: true,
  }).onOk(async () => {
    try {
      await deleteCustomer(row.id)
      await load()
      notify({ type: 'positive', message: 'Cliente eliminado' })
    } catch (e) {
      notify({ type: 'negative', message: (e as Error).message })
    }
  })
}

onMounted(load)
</script>
