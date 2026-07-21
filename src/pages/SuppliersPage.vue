<template>
  <q-page class="q-pa-md">
    <div class="row items-center q-mb-md">
      <div class="text-h5">Proveedores</div>
      <q-space />
      <q-btn color="primary" icon="add" label="Nuevo" @click="openNew" />
    </div>

    <q-table :rows="rows" :columns="columns" row-key="id" :loading="loading" flat bordered />

    <q-dialog v-model="show">
      <q-card style="min-width: 340px">
        <q-card-section class="text-h6">Nuevo proveedor</q-card-section>
        <q-card-section class="q-gutter-sm">
          <q-input v-model="form.razon_social" outlined label="Razón social" autofocus :rules="nameRules" lazy-rules hide-bottom-space />
          <q-input v-model="form.ruc" outlined label="RUC" :rules="rucRules" lazy-rules hide-bottom-space />
          <q-input v-model="form.contacto" outlined label="Contacto" :rules="[maxLen(120)]" lazy-rules hide-bottom-space />
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
import { listSuppliers, createSupplier, type Supplier } from '@/modules/purchases/purchases.api'
import { validate, nameRules, rucRules, maxLen } from '@/lib/validation'
import { notify } from '@/lib/toast'

const company = useCompanyStore()
const rows = ref<Supplier[]>([])
const loading = ref(false)
const show = ref(false)
const saving = ref(false)
const form = ref({ razon_social: '', ruc: '', contacto: '' })

const columns: QTableColumn<Supplier>[] = [
  { name: 'razon_social', label: 'Razón social', field: 'razon_social', align: 'left', sortable: true },
  { name: 'ruc', label: 'RUC', field: 'ruc', align: 'left' },
  { name: 'contacto', label: 'Contacto', field: 'contacto', align: 'left' },
]

function openNew() {
  form.value = { razon_social: '', ruc: '', contacto: '' }
  show.value = true
}

async function load() {
  if (!company.current) return
  loading.value = true
  try {
    rows.value = await listSuppliers(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
}

async function save() {
  if (!company.current) return
  const err = validate([
    [form.value.razon_social, nameRules],
    [form.value.ruc, rucRules],
    [form.value.contacto, [maxLen(120)]],
  ])
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  saving.value = true
  try {
    await createSupplier(company.current.id, form.value)
    show.value = false
    await load()
    notify({ type: 'positive', message: 'Proveedor creado' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    saving.value = false
  }
}

onMounted(load)
</script>
