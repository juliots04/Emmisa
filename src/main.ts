import { createApp } from 'vue'
import { createPinia } from 'pinia'
import { Quasar, Notify, Dialog, QField, QInput, QSelect, QFile } from 'quasar'
import langEs from 'quasar/lang/es'
import 'quasar/dist/quasar.css'
import '@quasar/extras/material-icons/material-icons.css'
import './styles/theme.css'

import App from './App.vue'
import router from './router'
import { useAuthStore } from './stores/auth'
import { useTipoCambioStore } from './stores/tipoCambio'
import { installNumberInputGuards } from './lib/inputGuards'

async function bootstrap() {
  const app = createApp(App)
  // Manejador global: un error de render no capturado no debe dejar pantalla en blanco.
  app.config.errorHandler = (err, _instance, info) => {
    console.error('[vue:errorHandler]', info, err)
  }
  app.use(createPinia())
  const savedTheme = typeof localStorage !== 'undefined' ? localStorage.getItem('emmisa-theme') : null
  const initialDark = savedTheme ? savedTheme === 'dark' : true
  app.use(Quasar, { plugins: { Notify, Dialog }, lang: langEs, config: { dark: initialDark } })

  // Defaults GLOBALES de los campos de formulario de Quasar:
  //  · lazyRules 'ondemand'  → las reglas (:rules) solo se evalúan al enviar (submit),
  //    no al escribir ni al salir del campo.
  //  · hideBottomSpace true  → no reservan el alto del mensaje de error/hint abajo, así
  //    las filas quedan a la misma altura (sin huecos irregulares entre campos).
  // OJO: en Quasar `hideBottomSpace` es un prop Boolean "shorthand" (no un objeto), por
  // eso no basta con tocar `.default`: hay que reemplazar la definición por un objeto.
  for (const C of [QField, QInput, QSelect, QFile]) {
    const p = (C as unknown as { props?: Record<string, { type?: unknown; default?: unknown }> }).props
    if (!p) continue
    if (p.lazyRules) p.lazyRules.default = 'ondemand'
    if ('hideBottomSpace' in p) p.hideBottomSpace = { type: Boolean, default: true }
  }

  // Restaura la sesión antes de montar para que el guard del router funcione bien.
  // Si falla (red/timeout/error), se monta IGUAL en estado degradado y el guard del
  // router redirige a login — nunca una pantalla en blanco sin feedback.
  try {
    await useAuthStore().init()
  } catch (e) {
    console.error('[bootstrap] init() falló; se monta en estado degradado:', e)
  }

  app.use(router)
  app.mount('#app')

  // Bloquea la entrada de negativos en todos los campos numéricos (global).
  installNumberInputGuards()

  // Tipo de cambio global (SUNAT → mercado). No bloquea el arranque.
  void useTipoCambioStore().refresh()
}

void bootstrap()
