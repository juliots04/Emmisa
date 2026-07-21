import { createApp } from 'vue'
import { createPinia } from 'pinia'
import { Quasar, Notify, Dialog } from 'quasar'
import 'quasar/dist/quasar.css'
import '@quasar/extras/material-icons/material-icons.css'
import './styles/theme.css'

import App from './App.vue'
import router from './router'
import { useAuthStore } from './stores/auth'

async function bootstrap() {
  const app = createApp(App)
  app.use(createPinia())
  const savedTheme = typeof localStorage !== 'undefined' ? localStorage.getItem('emmisa-theme') : null
  const initialDark = savedTheme ? savedTheme === 'dark' : true
  app.use(Quasar, { plugins: { Notify, Dialog }, config: { dark: initialDark } })

  // Restaura la sesión antes de montar para que el guard del router funcione bien.
  await useAuthStore().init()

  app.use(router)
  app.mount('#app')
}

void bootstrap()
