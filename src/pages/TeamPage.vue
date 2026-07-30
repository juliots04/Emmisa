<template>
  <q-page class="q-pa-md">
    <div class="text-h5 q-mb-md">
      Equipo
    </div>

    <q-banner
      class="k-banner--info q-mb-md"
      rounded
    >
      <template #avatar>
        <q-icon name="group" />
      </template>
      Invita a tus empleados y asígnales un rol. Primero deben <b>registrarse</b> con su correo;
      luego los agregas aquí. Solo un <b>administrador</b> puede gestionar el equipo.
    </q-banner>

    <!-- Agregar miembro -->
    <q-card class="q-mb-md">
      <q-card-section>
        <div class="text-subtitle1 q-mb-sm">
          Agregar miembro
        </div>
        <div class="row q-col-gutter-md items-end">
          <div class="col-12 col-sm-5">
            <q-input
              v-model="nuevoEmail"
              outlined
              dense
              type="email"
              label="Correo del empleado"
              @keyup.enter="agregar"
            />
          </div>
          <div class="col-12 col-sm-4">
            <q-select
              v-model="nuevoRol"
              outlined
              dense
              emit-value
              map-options
              :options="ROLES"
              label="Rol"
            />
          </div>
          <div class="col-auto">
            <q-btn
              color="primary"
              unelevated
              no-caps
              icon="person_add"
              label="Agregar"
              :loading="agregando"
              @click="agregar"
            />
          </div>
        </div>
      </q-card-section>
    </q-card>

    <!-- Lista -->
    <q-table
      :rows="miembros"
      :columns="columns"
      row-key="user_id"
      :loading="loading"
      flat
      bordered
      :pagination="{ rowsPerPage: 0 }"
      hide-pagination
    >
      <template #body-cell-role="props">
        <q-td :props="props">
          <q-select
            :model-value="props.row.role"
            dense
            outlined
            emit-value
            map-options
            options-dense
            style="min-width: 150px"
            :options="ROLES"
            :disable="cambiandoId === props.row.user_id"
            @update:model-value="(r) => cambiarRol(props.row, r)"
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
            color="negative"
            icon="person_remove"
            :disable="props.row.user_id === miUserId"
            @click="confirmarQuitar(props.row)"
          >
            <q-tooltip>{{ props.row.user_id === miUserId ? 'No puedes quitarte a ti mismo' : 'Quitar del equipo' }}</q-tooltip>
          </q-btn>
        </q-td>
      </template>
    </q-table>

    <!-- Confirmar quitar -->
    <q-dialog v-model="confirmDialog">
      <q-card>
        <q-card-section class="row items-center">
          <q-icon
            name="warning"
            color="negative"
            size="28px"
            class="q-mr-sm"
          />
          <span>¿Quitar a <b>{{ porQuitar?.email }}</b> del equipo?</span>
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
            color="negative"
            label="Quitar"
            :loading="quitando"
            @click="quitar"
          />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import { type QTableColumn } from 'quasar'
import { useCompanyStore } from '@/stores/company'
import { useAuthStore } from '@/stores/auth'
import { notify } from '@/lib/toast'
import {
  listarMiembros,
  agregarMiembro,
  cambiarRolMiembro,
  quitarMiembro,
  rolLabel,
  ROLES,
  type Miembro,
  type Rol,
} from '@/modules/team/team.api'

const company = useCompanyStore()
const auth = useAuthStore()
const miUserId = auth.user?.id ?? ''

const miembros = ref<Miembro[]>([])
const loading = ref(false)
const nuevoEmail = ref('')
const nuevoRol = ref<Rol>('vendedor')
const agregando = ref(false)
const cambiandoId = ref('')
const confirmDialog = ref(false)
const porQuitar = ref<Miembro | null>(null)
const quitando = ref(false)

const columns: QTableColumn<Miembro>[] = [
  { name: 'email', label: 'Correo', field: 'email', align: 'left' },
  { name: 'role', label: 'Rol', field: 'role', align: 'left' },
  {
    name: 'created_at',
    label: 'Desde',
    field: 'created_at',
    align: 'left',
    format: (v) => new Date(v as string).toLocaleDateString('es-PE'),
  },
  { name: 'acciones', label: '', field: 'user_id', align: 'right' },
]

async function cargar() {
  if (!company.current) return
  loading.value = true
  try {
    miembros.value = await listarMiembros(company.current.id)
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
}

async function agregar() {
  if (!company.current) return
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(nuevoEmail.value)) {
    notify({ type: 'warning', message: 'Ingresa un correo válido' })
    return
  }
  agregando.value = true
  try {
    await agregarMiembro(company.current.id, nuevoEmail.value, nuevoRol.value)
    notify({ type: 'positive', message: `${nuevoEmail.value} agregado como ${rolLabel(nuevoRol.value)}` })
    nuevoEmail.value = ''
    await cargar()
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    agregando.value = false
  }
}

async function cambiarRol(m: Miembro, role: Rol) {
  if (!company.current || role === m.role) return
  cambiandoId.value = m.user_id
  try {
    await cambiarRolMiembro(company.current.id, m.user_id, role)
    notify({ type: 'positive', message: `Rol actualizado a ${rolLabel(role)}` })
    await cargar()
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
    await cargar() // revierte el select al valor real
  } finally {
    cambiandoId.value = ''
  }
}

function confirmarQuitar(m: Miembro) {
  porQuitar.value = m
  confirmDialog.value = true
}

async function quitar() {
  if (!company.current || !porQuitar.value) return
  quitando.value = true
  try {
    await quitarMiembro(company.current.id, porQuitar.value.user_id)
    notify({ type: 'positive', message: 'Miembro quitado' })
    confirmDialog.value = false
    await cargar()
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    quitando.value = false
  }
}

onMounted(cargar)
watch(() => company.current?.id, cargar)
</script>
