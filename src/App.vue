<template>
  <router-view />
  <ToastHost />
</template>

<script setup lang="ts">
import { onBeforeUnmount, onMounted } from 'vue'
import ToastHost from '@/components/ToastHost.vue'
import { startTableTopScroll } from '@/lib/tableScroll'
import { supabase } from '@/lib/supabase'
import { invalidateQueryCache } from '@/stores/queryCache'

// Barra de scroll horizontal ARRIBA de cada tabla (global, sin flechas ni padding).
onMounted(startTableTopScroll)

// Un cambio remoto invalida el caché de sesión. La próxima entrada al módulo
// consultará datos frescos; si no hubo cambios, navegar no genera peticiones.
const cacheChannel = supabase
  .channel('global-query-cache')
  .on('postgres_changes', { event: '*', schema: 'public' }, () => invalidateQueryCache())
  .subscribe()

onBeforeUnmount(() => {
  void supabase.removeChannel(cacheChannel)
})
</script>
