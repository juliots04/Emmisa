import { createRouter, createWebHistory, type RouteRecordRaw } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useCompanyStore } from '@/stores/company'
import { getMyReseller } from '@/modules/reseller/reseller.api'

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
    path: '/recuperar',
    name: 'forgot-password',
    component: () => import('@/pages/ForgotPasswordPage.vue'),
    meta: { public: true },
  },
  {
    path: '/nueva-contrasena',
    name: 'reset-password',
    component: () => import('@/pages/ResetPasswordPage.vue'),
    meta: { public: true },
  },
  {
    path: '/terminos',
    name: 'terminos',
    component: () => import('@/pages/legal/TerminosPage.vue'),
    meta: { public: true },
  },
  {
    path: '/privacidad',
    name: 'privacidad',
    component: () => import('@/pages/legal/PrivacidadPage.vue'),
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
      { path: 'servicios', name: 'services', component: () => import('@/pages/ServicesPage.vue') },
      { path: 'categorias', name: 'categories', component: () => import('@/pages/CategoriesPage.vue') },
      { path: 'marcas', name: 'brands', component: () => import('@/pages/BrandsPage.vue') },
      { path: 'series', name: 'product-serials', component: () => import('@/pages/SeriesPage.vue') },
      { path: 'clientes', name: 'customers', component: () => import('@/pages/CustomersPage.vue') },
      { path: 'emitir', name: 'emit', component: () => import('@/pages/EmitPage.vue') },
      { path: 'comprobantes', name: 'documents', component: () => import('@/pages/DocumentsPage.vue') },
      { path: 'inventario', name: 'inventory', component: () => import('@/pages/InventoryPage.vue') },
      { path: 'proveedores', name: 'suppliers', component: () => import('@/pages/SuppliersPage.vue') },
      { path: 'compras', name: 'purchases', component: () => import('@/pages/PurchasesPage.vue') },
      { path: 'caja', name: 'cash', component: () => import('@/pages/CashPage.vue') },
      { path: 'reportes', name: 'reports', component: () => import('@/pages/ReportsPage.vue') },
      { path: 'configuracion', name: 'settings', component: () => import('@/pages/SettingsPage.vue') },
      { path: 'equipo', name: 'team', component: () => import('@/pages/TeamPage.vue') },
      { path: 'revendedor', name: 'reseller', component: () => import('@/pages/ResellerPage.vue'), meta: { reseller: true } },
      { path: 'cuentas-por-cobrar', name: 'receivables', component: () => import('@/pages/ReceivablesPage.vue') },
      { path: 'pos', name: 'pos', component: () => import('@/pages/PosPage.vue') },
      { path: 'cotizaciones', name: 'quotes', component: () => import('@/pages/QuotesPage.vue') },
      { path: 'notas-credito', name: 'creditnotes', component: () => import('@/pages/CreditNotesPage.vue') },
      { path: 'sire', name: 'sire', component: () => import('@/pages/SirePage.vue') },
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
    let loadFailed = false
    if (!company.loaded) {
      try {
        await company.load()
      } catch {
        // Error transitorio (red/RLS): NO empujar a onboarding a un usuario que quizá
        // sí tiene empresas (crearía una duplicada). Deja pasar; la UI mostrará el error.
        loadFailed = true
      }
    }
    const hasCompany = company.companies.length > 0
    if (!loadFailed && !hasCompany && to.name !== 'onboarding') return { name: 'onboarding' }
    // Permite abrir el onboarding para AGREGAR otra empresa (multiempresa) con ?nueva=1;
    // solo redirige a dashboard el caso "primer alta ya completada".
    if (hasCompany && to.name === 'onboarding' && to.query.nueva !== '1') return { name: 'dashboard' }
    // El panel de revendedor exige ser dueño de un reseller (no basta estar logueado).
    if (to.meta.reseller) {
      try {
        const reseller = await getMyReseller()
        if (!reseller) return { name: 'dashboard' }
      } catch {
        return { name: 'dashboard' }
      }
    }
  }
  return true
})

export default router
