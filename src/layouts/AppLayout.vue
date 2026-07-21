<template>
  <q-layout view="hHh Lpr lFf">
    <q-header class="k-header">
      <q-toolbar class="k-toolbar">
        <!-- Izquierda: menú + marca + switcher de empresa -->
        <q-btn
          flat
          round
          dense
          icon="menu"
          aria-label="Menú"
          class="k-icon-btn"
          @click="drawer = !drawer"
        />

        <div class="k-brand">
          <div class="k-logo-sm" aria-hidden="true">K</div>
          <span class="k-wordmark gt-xs">Konversa</span>
        </div>

        <div class="k-divider gt-xs" aria-hidden="true" />

        <q-btn-dropdown
          v-if="company.current"
          flat
          no-caps
          class="k-company"
          content-class="k-company-dropdown"
        >
          <template #label>
            <div class="k-company-label">
              <span class="k-company-name">{{ company.current.razon_social }}</span>
              <span class="k-company-ruc">{{ company.current.ruc }}</span>
            </div>
          </template>

          <q-list class="k-company-menu">
            <q-item
              v-for="c in company.companies"
              :key="c.id"
              v-close-popup
              clickable
              :active="c.id === company.current?.id"
              active-class="k-company-item--active"
              @click="selectCompany(c)"
            >
              <q-item-section>
                <q-item-label class="k-company-item-name">{{ c.razon_social }}</q-item-label>
                <q-item-label caption class="k-company-item-ruc">{{ c.ruc }}</q-item-label>
              </q-item-section>
              <q-item-section v-if="c.id === company.current?.id" side>
                <q-icon name="check" color="primary" size="18px" />
              </q-item-section>
            </q-item>

            <q-separator class="k-sep" spaced />

            <q-item v-close-popup clickable class="k-company-new" @click="goOnboarding">
              <q-item-section avatar>
                <q-icon name="add" size="20px" />
              </q-item-section>
              <q-item-section>Nueva empresa</q-item-section>
            </q-item>
          </q-list>
        </q-btn-dropdown>

        <q-space />

        <!-- Derecha: tema + cuenta -->
        <div class="k-header-right">
          <ThemeToggle />

          <q-btn
            flat
            round
            dense
            icon="account_circle"
            aria-label="Cuenta"
            class="k-icon-btn"
          >
            <q-menu anchor="bottom right" self="top right">
              <div class="k-account-menu">
                <div class="k-account-head">
                  <q-icon name="account_circle" size="30px" class="k-account-avatar" />
                  <div class="k-account-email">{{ auth.user?.email }}</div>
                </div>
                <q-separator class="k-sep" />
                <q-list>
                  <q-item v-close-popup clickable @click="logout">
                    <q-item-section avatar>
                      <q-icon name="logout" size="20px" />
                    </q-item-section>
                    <q-item-section>Cerrar sesión</q-item-section>
                  </q-item>
                </q-list>
              </div>
            </q-menu>
          </q-btn>
        </div>
      </q-toolbar>
    </q-header>

    <q-drawer v-model="drawer" show-if-above bordered :width="264">
      <div class="k-drawer-brand">
        <div class="k-logo-sm" aria-hidden="true">K</div>
        <span class="k-wordmark">Konversa</span>
      </div>

      <q-list padding>
        <q-item v-for="link in links" :key="link.to" v-ripple clickable :to="link.to" exact>
          <q-item-section avatar>
            <q-icon :name="link.icon" />
          </q-item-section>
          <q-item-section>{{ link.label }}</q-item-section>
        </q-item>
      </q-list>
    </q-drawer>

    <q-page-container>
      <router-view />
    </q-page-container>
  </q-layout>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useCompanyStore } from '@/stores/company'
import ThemeToggle from '@/components/ThemeToggle.vue'
import { notify } from '@/lib/toast'
import type { Company } from '@/types'

const auth = useAuthStore()
const company = useCompanyStore()
const router = useRouter()

const drawer = ref(false)

const links = [
  { to: '/', label: 'Inicio', icon: 'dashboard' },
  { to: '/pos', label: 'Venta rápida', icon: 'sell' },
  { to: '/emitir', label: 'Emitir', icon: 'receipt_long' },
  { to: '/comprobantes', label: 'Comprobantes', icon: 'description' },
  { to: '/notas-credito', label: 'Notas de crédito', icon: 'assignment_return' },
  { to: '/cotizaciones', label: 'Cotizaciones', icon: 'request_quote' },
  { to: '/productos', label: 'Productos', icon: 'inventory_2' },
  { to: '/inventario', label: 'Inventario', icon: 'warehouse' },
  { to: '/clientes', label: 'Clientes', icon: 'people' },
  { to: '/proveedores', label: 'Proveedores', icon: 'local_shipping' },
  { to: '/compras', label: 'Compras', icon: 'shopping_cart' },
  { to: '/caja', label: 'Caja', icon: 'point_of_sale' },
  { to: '/reportes', label: 'Reportes', icon: 'bar_chart' },
  { to: '/configuracion', label: 'Configuración', icon: 'settings' },
]

function selectCompany(c: Company) {
  company.setCurrent(c)
}

function goOnboarding() {
  router.push({ name: 'onboarding' })
}

async function logout() {
  await auth.signOut()
  company.reset()
  router.push({ name: 'login' })
}

onMounted(async () => {
  try {
    await company.load()
  } catch (e) {
    notify({ type: 'negative', message: 'No se pudo cargar empresas: ' + (e as Error).message })
  }
})
</script>

<style scoped>
/* ---------- Header ---------- */
.k-toolbar {
  min-height: 60px;
  padding: 0 10px 0 8px;
  gap: 4px;
}

.k-icon-btn {
  color: var(--k-muted);
}
.k-icon-btn:hover {
  color: var(--k-text);
}

.k-brand {
  display: flex;
  align-items: center;
  gap: 10px;
  margin: 0 4px 0 2px;
}

.k-logo-sm {
  width: 34px;
  height: 34px;
  border-radius: 10px;
  background: var(--q-primary);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: 'Hanken Grotesk', sans-serif;
  font-weight: 800;
  font-size: 18px;
  flex-shrink: 0;
  box-shadow: 0 4px 12px rgba(99, 102, 241, 0.22);
}

.k-wordmark {
  font-family: 'Hanken Grotesk', sans-serif;
  font-weight: 700;
  font-size: 18px;
  letter-spacing: -0.3px;
  color: var(--k-text);
}

.k-divider {
  width: 1px;
  height: 26px;
  background: var(--k-border);
  margin: 0 6px;
}

/* ---------- Switcher de empresa ---------- */
.k-company {
  border-radius: 12px;
  padding: 4px 6px;
}
.k-company:hover {
  background: var(--k-surface-2);
}

.k-company-label {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  justify-content: center;
  line-height: 1.2;
  text-align: left;
  padding: 0 2px;
}
.k-company-name {
  font-weight: 600;
  font-size: 13.5px;
  color: var(--k-text);
  max-width: 40vw;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.k-company-ruc {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  color: var(--k-muted);
}

.k-company-menu {
  min-width: 264px;
  padding: 6px;
}
.k-company-menu .q-item {
  border-radius: 10px;
  min-height: 48px;
}
.k-company-item-name {
  font-weight: 600;
  color: var(--k-text);
}
.k-company-item-ruc {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  color: var(--k-muted);
}
.k-company-item--active {
  background: rgba(99, 102, 241, 0.12);
}
.k-company-new {
  color: var(--q-primary);
  font-weight: 600;
}

/* ---------- Menú de cuenta ---------- */
.k-header-right {
  display: flex;
  align-items: center;
  gap: 2px;
}
.k-account-menu {
  min-width: 244px;
  padding: 6px;
}
.k-account-head {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 12px 12px;
}
.k-account-avatar {
  color: var(--k-muted);
}
.k-account-email {
  font-size: 13px;
  color: var(--k-text);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.k-account-menu .q-item {
  border-radius: 10px;
}

.k-sep {
  background: var(--k-border);
}

/* ---------- Drawer ---------- */
.k-drawer-brand {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 16px 18px 8px;
}
</style>
