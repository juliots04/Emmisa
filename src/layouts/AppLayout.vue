<template>
  <q-layout view="hHh Lpr lFf">
    <q-header class="k-header">
      <q-toolbar class="k-toolbar">
        <!-- Izquierda: marca + switcher de empresa -->
        <router-link
          to="/"
          class="k-brand"
          aria-label="Ir a Inicio"
        >
          <img
            class="k-logo-sm"
            src="/brand/badge.svg"
            alt=""
            aria-hidden="true"
          >
          <span class="k-wordmark gt-xs">Emmisa</span>
        </router-link>

        <div
          class="k-divider gt-xs"
          aria-hidden="true"
        />

        <q-btn-dropdown
          v-if="company.current"
          flat
          no-caps
          class="k-company"
          content-class="k-company-dropdown"
        >
          <template #label>
            <span class="k-co-avatar q-mr-sm">
              <img
                v-if="company.current.logo_url"
                :src="company.current.logo_url"
                alt=""
              >
              <span
                v-else
                class="k-co-initial"
              >{{ (company.current.razon_social || '?').charAt(0) }}</span>
            </span>
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
              <q-item-section avatar>
                <span class="k-co-avatar">
                  <img
                    v-if="c.logo_url"
                    :src="c.logo_url"
                    alt=""
                  >
                  <span
                    v-else
                    class="k-co-initial"
                  >{{ (c.razon_social || '?').charAt(0) }}</span>
                </span>
              </q-item-section>
              <q-item-section>
                <q-item-label class="k-company-item-name">
                  {{ c.razon_social }}
                </q-item-label>
                <q-item-label
                  caption
                  class="k-company-item-ruc"
                >
                  {{ c.ruc }}
                </q-item-label>
              </q-item-section>
              <q-item-section
                v-if="c.id === company.current?.id"
                side
              >
                <q-icon
                  name="check"
                  color="primary"
                  size="18px"
                />
              </q-item-section>
            </q-item>

            <q-separator
              class="k-sep"
              spaced
            />

            <q-item
              v-close-popup
              clickable
              class="k-company-new"
              @click="goOnboarding"
            >
              <q-item-section avatar>
                <q-icon
                  name="add"
                  size="20px"
                />
              </q-item-section>
              <q-item-section>Nueva empresa</q-item-section>
            </q-item>
          </q-list>
        </q-btn-dropdown>

        <div
          class="k-divider gt-sm"
          aria-hidden="true"
        />

        <!-- Accesos directos (izquierda) -->
        <div class="k-shortcuts gt-sm">
          <q-btn
            flat
            dense
            type="a"
            href="https://www.sunat.gob.pe/"
            target="_blank"
            rel="noopener"
            aria-label="Ir a SUNAT"
            class="k-svc-btn"
          >
            <img
              src="/brand/sunat.png"
              alt="SUNAT"
              class="k-svc-logo"
            >
            <q-tooltip>Ir a SUNAT</q-tooltip>
          </q-btn>

          <q-btn
            flat
            dense
            type="a"
            href="https://e-consultaruc.sunat.gob.pe/cl-ti-itmrconsruc/FrameCriterioBusquedaWeb.jsp"
            target="_blank"
            rel="noopener"
            aria-label="Consultar RUC"
            class="k-svc-btn"
          >
            <img
              src="/brand/ruc.svg"
              alt="RUC"
              class="k-svc-logo"
            >
            <q-tooltip>Consultar RUC (SUNAT)</q-tooltip>
          </q-btn>

          <q-btn
            flat
            dense
            type="a"
            href="https://www.reniec.gob.pe/"
            target="_blank"
            rel="noopener"
            aria-label="Consultar DNI"
            class="k-svc-btn"
          >
            <img
              src="/brand/reniec.png"
              alt="RENIEC"
              class="k-svc-logo"
            >
            <q-tooltip>Consultar DNI (RENIEC)</q-tooltip>
          </q-btn>

          <q-btn
            flat
            dense
            type="a"
            href="https://www.google.com/"
            target="_blank"
            rel="noopener"
            aria-label="Ir a Google"
            class="k-svc-btn"
          >
            <img
              src="/brand/google.png"
              alt="Google"
              class="k-svc-logo k-svc-logo--google"
              @error="onGoogleImgError"
            >
            <q-tooltip>Ir a Google</q-tooltip>
          </q-btn>

          <!-- Accesos personalizados (módulos elegidos por el usuario) -->
          <template v-if="shortcutModules.length">
            <div
              class="k-divider"
              aria-hidden="true"
            />
            <q-btn
              v-for="m in shortcutModules"
              :key="m.to"
              flat
              dense
              :to="m.to"
              :aria-label="m.label"
              class="k-svc-btn k-svc-btn--mod"
            >
              <q-icon
                :name="m.icon"
                size="21px"
              />
              <q-tooltip>{{ m.label }}</q-tooltip>
            </q-btn>
          </template>

          <!-- Botón "+": abre el modal para personalizar los accesos -->
          <q-btn
            flat
            dense
            round
            icon="add"
            aria-label="Personalizar accesos directos"
            class="k-svc-btn k-add-btn"
            @click="showModules = true"
          >
            <q-tooltip>Accesos directos</q-tooltip>
          </q-btn>
        </div>

        <q-space />

        <!-- Derecha: tema + cuenta -->
        <div class="k-header-right">
          <GlobalSearch
            :items="allModules"
            class="gt-xs q-mr-sm"
          />
          <ThemeToggle />

          <q-btn
            flat
            round
            dense
            icon="account_circle"
            aria-label="Cuenta"
            class="k-icon-btn"
          >
            <q-menu
              anchor="bottom right"
              self="top right"
            >
              <div class="k-account-menu">
                <div class="k-account-head">
                  <q-icon
                    name="account_circle"
                    size="30px"
                    class="k-account-avatar"
                  />
                  <div class="k-account-email">
                    {{ auth.user?.email }}
                  </div>
                </div>
                <q-separator class="k-sep" />
                <q-list>
                  <q-item
                    v-close-popup
                    clickable
                    @click="logout"
                  >
                    <q-item-section avatar>
                      <q-icon
                        name="logout"
                        size="20px"
                      />
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

    <q-drawer
      v-model="drawer"
      show-if-above
      :breakpoint="0"
      bordered
      :width="264"
      :mini="miniState"
      :mini-width="72"
      mini-to-overlay
      class="k-drawer"
      @mouseenter="onDrawerEnter"
      @mouseleave="onDrawerLeave"
    >
      <div class="k-nav-wrap">
        <q-list
          padding
          class="k-nav"
        >
          <template
            v-for="item in nav"
            :key="item.section ?? item.to"
          >
            <!-- Ítem suelto (sin hijos) -->
            <q-item
              v-if="!item.children"
              v-ripple
              clickable
              :to="item.to"
              exact
              class="k-nav-item"
            >
              <q-item-section avatar>
                <q-icon :name="item.icon" />
              </q-item-section>
              <q-item-section>{{ item.label }}</q-item-section>
              <q-tooltip
                v-if="miniState"
                anchor="center right"
                self="center left"
                :offset="[8, 0]"
                class="k-nav-tip"
              >
                {{ item.label }}
              </q-tooltip>
            </q-item>

            <!-- Sección desplegable (el modo mini/hover lo maneja Quasar) -->
            <q-expansion-item
              v-else
              v-model="openSections[item.section!]"
              :icon="item.icon"
              :label="item.section"
              expand-icon="expand_more"
              dense-toggle
              header-class="k-nav-group"
              class="k-nav-exp"
            >
              <div class="k-nav-rail">
                <q-item
                  v-for="child in item.children"
                  :key="child.to"
                  v-ripple
                  clickable
                  :to="child.to"
                  exact
                  class="k-nav-child"
                >
                  <q-item-section>{{ child.label }}</q-item-section>
                </q-item>
              </div>
            </q-expansion-item>
          </template>
        </q-list>

        <!-- Configuración: fijo (sticky) al fondo del sidebar -->
        <div class="k-nav-footer">
          <q-item
            v-ripple
            clickable
            to="/configuracion"
            exact
            class="k-nav-item"
          >
            <q-item-section avatar>
              <q-icon name="settings" />
            </q-item-section>
            <q-item-section>Configuración</q-item-section>
            <q-tooltip
              v-if="miniState"
              anchor="center right"
              self="center left"
              :offset="[8, 0]"
              class="k-nav-tip"
            >
              Configuración
            </q-tooltip>
          </q-item>
        </div>
      </div>
    </q-drawer>

    <q-page-container>
      <!-- key por empresa: al cambiar de empresa, la página se re-monta y recarga sus datos -->
      <router-view :key="company.current?.id ?? 'none'" />
    </q-page-container>

    <!-- Modal: elegir módulos como accesos directos del header -->
    <q-dialog v-model="showModules">
      <q-card class="k-dialog-md">
        <q-card-section class="k-modal-head">
          <div class="text-h6">
            Accesos directos
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
        <q-card-section>
          <div class="text-caption text-muted q-mb-md">
            Elige los módulos que quieres tener a un clic en la barra superior.
            <span class="text-weight-medium">(máx {{ MAX_SHORTCUTS }} · {{ shortcuts.length }}/{{ MAX_SHORTCUTS }})</span>
          </div>
          <div class="k-mod-grid">
            <button
              v-for="m in allModules"
              :key="m.to"
              type="button"
              class="k-mod-chip"
              :class="{ 'is-on': shortcuts.includes(m.to) }"
              :disabled="shortcutsFull && !shortcuts.includes(m.to)"
              @click="toggleShortcut(m.to)"
            >
              <q-icon
                :name="m.icon"
                size="24px"
              />
              <span class="k-mod-label">{{ m.label }}</span>
              <q-icon
                v-if="shortcuts.includes(m.to)"
                name="check_circle"
                size="18px"
                class="k-mod-check"
              />
            </button>
          </div>
        </q-card-section>
      </q-card>
    </q-dialog>
  </q-layout>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useCompanyStore } from '@/stores/company'
import ThemeToggle from '@/components/ThemeToggle.vue'
import GlobalSearch from '@/components/GlobalSearch.vue'
import { notify } from '@/lib/toast'
import type { Company } from '@/types'

const auth = useAuthStore()
const company = useCompanyStore()
const router = useRouter()
const route = useRoute()

// Sidebar siempre visible (PC): breakpoint 0 + show-if-above lo mantiene fijo.
const drawer = ref(true)

// El sidebar es un riel de íconos que se expande (overlay) al pasar el mouse.
const hovering = ref(false)
const miniState = computed(() => !hovering.value)
function onDrawerEnter() {
  hovering.value = true
}
function onDrawerLeave() {
  hovering.value = false
}

interface NavChild {
  to: string
  label: string
}
interface NavEntry {
  icon: string
  to?: string
  label?: string
  section?: string
  children?: NavChild[]
}

const nav: NavEntry[] = [
  { to: '/', label: 'Inicio', icon: 'home' },
  {
    section: 'Ventas',
    icon: 'point_of_sale',
    children: [
      { to: '/pos', label: 'Venta rápida' },
      { to: '/emitir', label: 'Emitir' },
      { to: '/comprobantes', label: 'Comprobantes' },
      { to: '/notas-credito', label: 'Notas de crédito' },
      { to: '/cotizaciones', label: 'Cotizaciones' },
    ],
  },
  {
    section: 'Productos/Servicios',
    icon: 'category',
    children: [
      { to: '/productos', label: 'Productos' },
      { to: '/servicios', label: 'Servicios' },
      { to: '/categorias', label: 'Categorías' },
      { to: '/marcas', label: 'Marcas' },
      { to: '/series', label: 'Series' },
    ],
  },
  { to: '/inventario', label: 'Inventario', icon: 'inventory_2' },
  {
    section: 'Clientes y cobranzas',
    icon: 'group',
    children: [
      { to: '/clientes', label: 'Clientes' },
      { to: '/cuentas-por-cobrar', label: 'Cuentas por cobrar' },
    ],
  },
  {
    section: 'Compras y proveedores',
    icon: 'local_shipping',
    children: [
      { to: '/proveedores', label: 'Proveedores' },
      { to: '/compras', label: 'Compras' },
    ],
  },
  { to: '/caja', label: 'Caja', icon: 'payments' },
  { to: '/reportes', label: 'Reportes', icon: 'bar_chart' },
  { to: '/sire', label: 'SIRE (SUNAT)', icon: 'account_balance' },
  {
    section: 'Administración',
    icon: 'admin_panel_settings',
    children: [
      { to: '/equipo', label: 'Equipo' },
      { to: '/revendedor', label: 'Revendedor' },
      { to: '/configuracion', label: 'Configuración' },
    ],
  },
]

/* ---------- Accesos directos personalizables del header ---------- */
// Ícono por ruta (los hijos de sección no tienen ícono propio en el nav).
const MODULE_ICONS: Record<string, string> = {
  '/': 'home',
  '/pos': 'point_of_sale',
  '/emitir': 'receipt_long',
  '/comprobantes': 'description',
  '/notas-credito': 'assignment_return',
  '/cotizaciones': 'request_quote',
  '/productos': 'inventory_2',
  '/servicios': 'room_service',
  '/categorias': 'category',
  '/marcas': 'sell',
  '/series': 'tag',
  '/inventario': 'inventory',
  '/clientes': 'group',
  '/cuentas-por-cobrar': 'account_balance_wallet',
  '/proveedores': 'local_shipping',
  '/compras': 'shopping_cart',
  '/caja': 'payments',
  '/reportes': 'bar_chart',
  '/sire': 'account_balance',
  '/equipo': 'groups',
  '/revendedor': 'storefront',
  '/configuracion': 'settings',
}

interface ModuleItem {
  to: string
  label: string
  icon: string
}
// Aplana el nav (ítems sueltos + hijos de sección) a una lista de módulos.
const allModules = computed<ModuleItem[]>(() => {
  const out: ModuleItem[] = []
  for (const item of nav) {
    if (item.to && item.label) {
      out.push({ to: item.to, label: item.label, icon: MODULE_ICONS[item.to] ?? item.icon })
    }
    for (const c of item.children ?? []) {
      out.push({ to: c.to, label: c.label, icon: MODULE_ICONS[c.to] ?? item.icon })
    }
  }
  return out
})

const SHORTCUTS_KEY = 'emmisa.header_shortcuts'
const shortcuts = ref<string[]>(loadShortcuts())
const showModules = ref(false)

function loadShortcuts(): string[] {
  try {
    const raw = localStorage.getItem(SHORTCUTS_KEY)
    return raw ? (JSON.parse(raw) as string[]) : []
  } catch {
    return []
  }
}
// Tope de accesos directos fijables en el header.
const MAX_SHORTCUTS = 5
// Solo módulos existentes (por si el nav cambió), preservando el orden elegido y
// respetando el tope (por si en localStorage quedaron más de una versión previa).
const shortcutModules = computed<ModuleItem[]>(() =>
  shortcuts.value
    .map((to) => allModules.value.find((m) => m.to === to))
    .filter((m): m is ModuleItem => !!m)
    .slice(0, MAX_SHORTCUTS),
)
const shortcutsFull = computed(() => shortcuts.value.length >= MAX_SHORTCUTS)
function toggleShortcut(to: string) {
  const i = shortcuts.value.indexOf(to)
  if (i >= 0) {
    shortcuts.value.splice(i, 1)
  } else {
    if (shortcuts.value.length >= MAX_SHORTCUTS) {
      notify({ type: 'warning', message: `Máximo ${MAX_SHORTCUTS} accesos directos` })
      return
    }
    shortcuts.value.push(to)
  }
  try {
    localStorage.setItem(SHORTCUTS_KEY, JSON.stringify(shortcuts.value))
  } catch {
    /* almacenamiento no disponible: no es crítico */
  }
}
// Si /brand/google.png no existe aún, cae al logo oficial de Google (PNG en su CDN).
function onGoogleImgError(e: Event) {
  const img = e.target as HTMLImageElement
  const fallback = 'https://www.gstatic.com/images/branding/product/1x/googleg_48dp.png'
  if (img.src !== fallback) img.src = fallback
}

// Estado abierto/cerrado por sección. Se abre automáticamente la que contiene la ruta activa.
const openSections = ref<Record<string, boolean>>({})
watch(
  () => route.path,
  (path) => {
    for (const item of nav) {
      if (item.section && item.children?.some((c) => c.to === path)) {
        openSections.value[item.section] = true
      }
    }
  },
  { immediate: true },
)

function selectCompany(c: Company) {
  company.setCurrent(c)
}

function goOnboarding() {
  // ?nueva=1 → el guard permite el onboarding aunque ya haya empresas (alta de otra).
  router.push({ name: 'onboarding', query: { nueva: '1' } })
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
  padding: 5px; /* círculo de hover ajustado al ícono (no el círculo enorme) */
}
.k-icon-btn:hover {
  color: var(--k-text);
}
/* Ícono de perfil más grande, independiente del tamaño del botón/círculo. */
.k-icon-btn :deep(.q-icon) {
  font-size: 28px;
}

.k-brand {
  display: flex;
  align-items: center;
  gap: 10px;
  margin: 0 4px 0 2px;
  cursor: pointer;
  text-decoration: none;
  color: inherit;
  border-radius: 12px;
  padding: 2px 4px;
  transition: opacity 0.15s ease;
}
.k-brand:hover {
  opacity: 0.82;
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
  box-shadow: none;
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

/* ---------- Avatar / logo de empresa ---------- */
.k-co-avatar {
  width: 28px;
  height: 28px;
  border-radius: 8px;
  background: var(--k-surface-2);
  border: 1px solid var(--k-border);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  flex-shrink: 0;
}
.k-co-avatar img {
  width: 100%;
  height: 100%;
  object-fit: contain;
}
.k-co-initial {
  font-weight: 700;
  font-size: 13px;
  color: var(--k-muted);
  text-transform: uppercase;
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
  gap: 4px;
}

/* ---------- Accesos directos (izquierda) ---------- */
.k-shortcuts {
  display: flex;
  align-items: center;
  gap: 2px;
}

/* ---------- Botones de acceso directo (SUNAT · RUC · RENIEC) ----------
   Cada uno muestra su logo oficial (isotipo) en un tile blanco redondeado,
   uniforme en tamaño para dar coherencia. */
.k-svc-btn {
  width: 38px;
  height: 38px;
  min-width: 0;
  min-height: 0;
  padding: 0;
  border-radius: 10px;
}
.k-svc-btn :deep(.q-btn__content) {
  padding: 0;
}
.k-svc-logo {
  width: 30px;
  height: 30px;
  border-radius: 8px;
  background: #fff;
  object-fit: contain;
  display: block;
  transition: transform 0.12s ease;
}
.k-svc-btn:hover .k-svc-logo {
  transform: scale(1.06);
}
/* El isotipo de Google llena más su lienzo que SUNAT/RUC/RENIEC → se insetea con
   padding para que el glifo se vea más pequeño, manteniendo el mismo tile blanco. */
.k-svc-logo--google {
  padding: 6px;
  box-sizing: border-box;
}
/* Accesos de módulo (ícono en vez de logo) + botón "+" */
.k-svc-btn--mod :deep(.q-icon),
.k-add-btn :deep(.q-icon) {
  color: var(--k-muted);
  transition: color 0.12s ease, transform 0.12s ease;
}
.k-svc-btn--mod:hover :deep(.q-icon),
.k-add-btn:hover :deep(.q-icon) {
  color: var(--k-text);
  transform: scale(1.06);
}
.k-svc-btn--mod.q-router-link--active {
  background: var(--k-active-bg);
}
.k-svc-btn--mod.q-router-link--active :deep(.q-icon) {
  color: var(--k-active-text);
}

/* ---------- Modal "Accesos directos": grid de módulos ---------- */
.k-mod-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(148px, 1fr));
  gap: 10px;
}
.k-mod-chip {
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 16px 10px;
  border-radius: 14px;
  border: 1px solid var(--k-border);
  background: var(--k-surface-2);
  color: var(--k-text);
  cursor: pointer;
  transition: border-color 0.14s ease, background 0.14s ease;
}
.k-mod-chip:hover {
  border-color: var(--k-border-hover);
}
/* Al llegar al tope, los módulos no seleccionados se ven deshabilitados. */
.k-mod-chip:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}
.k-mod-chip.is-on {
  border-color: var(--k-active-text);
  background: var(--k-active-bg);
}
.k-mod-chip .q-icon {
  color: var(--k-muted);
}
.k-mod-chip.is-on .q-icon {
  color: var(--k-active-text);
}
.k-mod-label {
  font-size: 12.5px;
  font-weight: 600;
  text-align: center;
  line-height: 1.2;
}
.k-mod-check {
  position: absolute;
  top: 7px;
  right: 7px;
  color: var(--q-positive) !important;
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

/* ---------- Navegación · riel-guía + píldora flotante (redondeado) ---------- */
.k-nav {
  /* Tono idle uniforme: suave, ni gris apagado ni blanco neto */
  --nav-idle: color-mix(in srgb, var(--k-text) 62%, var(--k-muted));
  padding: 12px 8px 8px;
}

/* Ítem suelto (Inicio, Caja, Reportes) — píldora redondeada, brillo uniforme */
.k-nav-item {
  border-radius: 12px;
  min-height: 44px;
  color: var(--nav-idle);
  font-weight: 500;
  transition: background 0.15s ease, color 0.15s ease;
}
.k-nav-item .q-icon {
  color: var(--nav-idle);
  transition: color 0.15s ease;
}
.k-nav-item:hover {
  background: color-mix(in srgb, var(--k-text) 7%, transparent);
  color: var(--k-text);
}
.k-nav-item:hover .q-icon {
  color: var(--k-text);
}
.k-nav-item.q-router-link--exact-active {
  background: color-mix(in srgb, var(--k-text) 12%, transparent);
  color: var(--k-text);
  font-weight: 600;
}
.k-nav-item.q-router-link--exact-active .q-icon {
  color: var(--k-text);
}

/* Cabecera de grupo — misma píldora; icono al mismo brillo que los ítems */
.k-nav :deep(.k-nav-group) {
  border-radius: 12px;
  min-height: 44px;
  font-weight: 600;
  color: var(--nav-idle);
  transition: background 0.15s ease, color 0.15s ease;
}
.k-nav :deep(.k-nav-group) .q-icon {
  color: var(--nav-idle);
}
.k-nav :deep(.k-nav-group:hover) {
  background: color-mix(in srgb, var(--k-text) 7%, transparent);
  color: var(--k-text);
}
/* Chevron: único elemento en tono muted (es afordancia, no contenido).
   margin-left lo separa del texto (evita solaparse con etiquetas largas). */
.k-nav :deep(.q-expansion-item__toggle-icon) {
  color: var(--k-muted);
  margin-left: 10px;
  margin-right: 2px;
}
/* Etiqueta larga de sección: se recorta antes que invadir el chevron */
.k-nav :deep(.k-nav-group) .q-item__section--main {
  overflow: hidden;
}
.k-nav :deep(.k-nav-group) .q-item__label {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
/* El contenedor que Quasar anima en altura NO lleva margen vertical
   (el margen no se anima y provocaba el "salto" al abrir/cerrar). */
.k-nav :deep(.q-expansion-item__content) {
  margin: 0;
}

/* Riel-guía: contenedor interno estático (usa padding, no margen, para no saltar) */
.k-nav-rail {
  margin-left: 23px;
  padding: 2px 0 4px 13px;
  border-left: 1.5px solid var(--k-border);
  display: flex;
  flex-direction: column;
  gap: 2px;
}

/* Hijo: píldora redondeada flotante (no toca el riel) */
.k-nav-child {
  min-height: 34px;
  padding: 6px 12px;
  border-radius: 11px;
  color: var(--k-muted);
  font-size: 13.5px;
  font-weight: 500;
  transition: background 0.15s ease, color 0.15s ease;
}
.k-nav-child:hover {
  background: color-mix(in srgb, var(--k-text) 7%, transparent);
  color: var(--k-text);
}
.k-nav-child.q-router-link--exact-active {
  background: color-mix(in srgb, var(--k-text) 12%, transparent);
  color: var(--k-text);
  font-weight: 600;
}

/* ---------- Contraer / expandir sidebar ---------- */
/* El aside anima su ancho con easing elástico (efecto "líquido", con rebote suave).
   Se apunta al <aside> real de Quasar vía :deep desde la raíz del layout. */
:deep(.q-drawer) {
  transition: width 0.5s cubic-bezier(0.34, 1.56, 0.64, 1) !important;
  will-change: width;
}
/* El contenido refluye a la par del aside (sin salto brusco) */
:deep(.q-drawer-container),
:deep(.q-page-container) {
  transition: padding-left 0.5s cubic-bezier(0.34, 1.56, 0.64, 1) !important;
}
/* Al encoger, el texto se recorta limpio; y se oculta el scrollbar (scroll sigue activo) */
:deep(.q-drawer__content) {
  overflow-x: hidden;
  scrollbar-width: none; /* Firefox */
  -ms-overflow-style: none; /* Edge antiguo */
}
:deep(.q-drawer__content)::-webkit-scrollbar {
  width: 0;
  height: 0;
  display: none; /* Chromium / WebKit */
}
.k-nav-item :deep(.q-item__section:not(.q-item__section--avatar)) {
  white-space: nowrap;
}

/* Envoltorio a lo alto: toggle arriba, navegación debajo */
.k-nav-wrap {
  display: flex;
  flex-direction: column;
  min-height: 100%;
}
.k-nav {
  flex: 1 1 auto;
}

/* Configuración fijo al fondo del sidebar (sticky). Fondo opaco = el nav pasa por detrás. */
.k-nav-footer {
  position: sticky;
  bottom: 0;
  z-index: 1;
  flex: 0 0 auto;
  padding: 6px 0 8px;
  background: var(--k-bg);
  border-top: 1px solid var(--k-border);
}
/* Modo mini (Quasar añade .q-drawer--mini al <aside> en reposo contraído):
   cada ítem = cuadrado centrado. Incluye sueltos, cabeceras de sección y Configuración.
   Al pasar el mouse Quasar quita .q-drawer--mini → vuelve a íconos + texto (overlay). */
.k-drawer.q-drawer--mini .k-nav-item,
.k-drawer.q-drawer--mini .k-nav-footer .k-nav-item {
  width: 44px;
  min-width: 44px;
  height: 44px;
  min-height: 44px;
  margin: 3px auto;
  padding: 0;
  justify-content: center;
  border-radius: 12px;
}
.k-drawer.q-drawer--mini :deep(.k-nav-group) {
  width: 44px;
  height: 44px;
  min-height: 44px;
  margin: 3px auto;
  padding: 0;
  justify-content: center;
  border-radius: 12px;
}
.k-drawer.q-drawer--mini :deep(.q-item__section--avatar) {
  min-width: 0;
  padding-right: 0;
  justify-content: center;
}

/* Tooltip de ítem contraído */
:deep(.k-nav-tip) {
  background: color-mix(in srgb, var(--k-text) 88%, #000);
  color: var(--k-bg);
  font-size: 12.5px;
  font-weight: 600;
  padding: 5px 10px;
  border-radius: 8px;
}

</style>
