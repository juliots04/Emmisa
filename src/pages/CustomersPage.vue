<template>
  <q-page class="q-pa-md">
    <KModuleHeader
      title="Clientes"
      subtitle="Administra los clientes de tu empresa y sus documentos"
      :refresh-fn="load"
      new-label="Nuevo"
      show-import
      show-export
      @new="openNew"
      @export="onExport"
    />

    <q-table
      :rows="rows"
      :columns="columns"
      row-key="id"
      :loading="loading"
      flat
      bordered
    >
      <template #body-cell-acciones="props">
        <q-td
          :props="props"
          class="text-right"
        >
          <q-btn
            flat
            round
            dense
            icon="edit"
            size="sm"
            @click="openEdit(props.row)"
          />
          <q-btn
            flat
            round
            dense
            icon="delete"
            size="sm"
            color="negative"
            @click="remove(props.row)"
          />
        </q-td>
      </template>
      <template #loading>
        <KTableSkeleton />
      </template>
    </q-table>

    <q-dialog v-model="show">
      <q-card class="k-dialog-md">
        <q-card-section class="k-modal-head">
          <div class="text-h6">
            {{ editingId ? 'Editar cliente' : 'Nuevo cliente' }}
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
            v-model="form.denominacion"
            label="Nombre / Razón social"
            :rules="nameRules"
            lazy-rules="ondemand"
            autofocus
          />
          <q-select
            v-model="form.tipo_doc"
            :options="docOptions"
            emit-value
            map-options
            label="Tipo de documento"
          />
          <q-input
            v-model="form.num_doc"
            :label="form.tipo_doc === '6' ? 'RUC' : 'DNI'"
            :rules="[docByTipo(form.tipo_doc, form.tipo_doc === '6')]"
            lazy-rules="ondemand"
          />
          <q-input
            v-model="form.email"
            label="Email (opcional)"
            type="email"
            :rules="[email()]"
            lazy-rules="ondemand"
          />
          <q-input
            v-model="form.direccion"
            label="Dirección (opcional)"
          />
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
import { onMounted, ref } from 'vue'
import { useQuasar, type QTableColumn } from 'quasar'
import KTableSkeleton from '@/components/KTableSkeleton.vue'
import KModuleHeader from '@/components/KModuleHeader.vue'
import { exportTableXls } from '@/lib/exportTable'
import { useCompanyStore } from '@/stores/company'
import { useRealtime } from '@/lib/realtime'
import { listCustomers, createCustomer, updateCustomer, deleteCustomer } from '@/modules/customers/customers.api'
import { validate, nameRules, docByTipo, email } from '@/lib/validation'
import { notify } from '@/lib/toast'
import type { Customer } from '@/types'

const $q = useQuasar()
const company = useCompanyStore()
// Realtime: refresca al crear/editar/eliminar clientes (incl. otras pestañas/usuarios).
useRealtime('customers', () => company.current?.id, () => { void load() })
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

function onExport() {
  exportTableXls('clientes', columns, rows.value)
}

async function load() {
  if (!company.current) return
  loading.value = !rows.value.length
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
