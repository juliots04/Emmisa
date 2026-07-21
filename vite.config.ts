import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { quasar, transformAssetUrls } from '@quasar/vite-plugin'
import { fileURLToPath, URL } from 'node:url'

export default defineConfig({
  plugins: [vue({ template: { transformAssetUrls } }), quasar({})],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  server: {
    host: true,
    port: 5173,
    allowedHosts: ['.trycloudflare.com', '.loca.lt', '.ngrok-free.app'],
  },
  build: {
    rollupOptions: {
      output: {
        // Separar librerías grandes en chunks cacheables (mejor caché entre releases
        // y silencia el aviso de chunk > 500 kB). No reduce el total, mejora el reparto.
        manualChunks: {
          vue: ['vue', 'vue-router', 'pinia'],
          quasar: ['quasar'],
          supabase: ['@supabase/supabase-js'],
          gsap: ['gsap'],
        },
      },
    },
  },
})
