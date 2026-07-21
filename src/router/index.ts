import { createRouter, createWebHistory, type RouteRecordRaw } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useCompanyStore } from '@/stores/company'

const routes: RouteRecordRaw[] = [
  {
    path: '/login',
    name: 'login',
    component: () => import('@/pages/LoginPage.vue'),
    meta: { public: true },
  },
  {
    path: '/register',
    name: 'register',
    component: () => import('@/pages/RegisterPage.vue'),
    meta: { public: true },
  },
  {
    path: '/verificar',
    name: 'verify',
    component: () => import('@/pages/VerifyPage.vue'),
    meta: { public: true },
  },
  {
    path: '/onboarding',
    name: 'onboarding',
    component: () => import('@/pages/OnboardingPage.vue'),
  },
  {
    path: '/',
    component: () => import('@/layouts/AppLayout.vue'),
    children: [
      { path: '', name: 'dashboard', component: () => import('@/pages/DashboardPage.vue') },
      { path: 'productos', name: 'products', component: () => import('@/pages/ProductsPage.vue') },
      { path: 'clientes', name: 'customers', component: () => import('@/pages/CustomersPage.vue') },
      { path: 'emitir', name: 'emit', component: () => import('@/pages/EmitPage.vue') },
      { path: 'comprobantes', name: 'documents', component: () => import('@/pages/DocumentsPage.vue') },
      { path: 'inventario', name: 'inventory', component: () => import('@/pages/InventoryPage.vue') },
      { path: 'proveedores', name: 'suppliers', component: () => import('@/pages/SuppliersPage.vue') },
      { path: 'compras', name: 'purchases', component: () => import('@/pages/PurchasesPage.vue') },
      { path: 'caja', name: 'cash', component: () => import('@/pages/CashPage.vue') },
      { path: 'reportes', name: 'reports', component: () => import('@/pages/ReportsPage.vue') },
      { path: 'configuracion', name: 'settings', component: () => import('@/pages/SettingsPage.vue') },
      { path: 'revendedor', name: 'reseller', component: () => import('@/pages/ResellerPage.vue') },
      { path: 'cuentas-por-cobrar', name: 'receivables', component: () => import('@/pages/ReceivablesPage.vue') },
      { path: 'pos', name: 'pos', component: () => import('@/pages/PosPage.vue') },
      { path: 'cotizaciones', name: 'quotes', component: () => import('@/pages/QuotesPage.vue') },
      { path: 'notas-credito', name: 'creditnotes', component: () => import('@/pages/CreditNotesPage.vue') },
      {
        path: 'comprobantes/:id',
        name: 'document-detail',
        component: () => import('@/pages/DocumentDetailPage.vue'),
      },
    ],
  },
  { path: '/:pathMatch(.*)*', redirect: '/' },
]

const router = createRouter({ history: createWebHistory(), routes })

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  if (!to.meta.public && !auth.user) return { name: 'login' }
  if ((to.name === 'login' || to.name === 'register') && auth.user) return { name: 'dashboard' }

  if (auth.user) {
    const company = useCompanyStore()
    if (!company.loaded) {
      try {
        await company.load()
      } catch {
        /* si las tablas aún no existen, deja pasar y que la UI muestre el error */
      }
    }
    const hasCompany = company.companies.length > 0
    if (!hasCompany && to.name !== 'onboarding') return { name: 'onboarding' }
    if (hasCompany && to.name === 'onboarding') return { name: 'dashboard' }
  }
  return true
})

export default router
