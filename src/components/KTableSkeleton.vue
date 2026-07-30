<template>
  <!-- Skeleton de carga para tablas. Va en el slot #loading de q-table (Quasar lo
       renderiza SOLO cuando :loading es true y lo apila justo bajo el header, una
       vez que el texto "Cargando..." se oculta por CSS). Imita filas con columnas. -->
  <div class="k-skel">
    <div
      v-for="n in rows"
      :key="n"
      class="k-skel-row"
    >
      <q-skeleton
        type="rect"
        class="k-skel-a"
        animation="wave"
      />
      <q-skeleton
        type="rect"
        class="k-skel-b"
        animation="wave"
      />
      <q-skeleton
        type="rect"
        class="k-skel-c"
        animation="wave"
      />
    </div>
  </div>
</template>

<script setup lang="ts">
withDefaults(defineProps<{ rows?: number }>(), { rows: 7 })
</script>

<style scoped>
.k-skel {
  width: 100%;
}
.k-skel-row {
  display: flex;
  align-items: center;
  height: 52px;
  padding: 0 16px;
  border-bottom: 1px solid var(--k-border);
}
.k-skel-row:last-child {
  border-bottom: none;
}
/* Columnas: una etiqueta ancha a la izquierda, otra media, y un valor a la derecha. */
.k-skel-a {
  width: 30%;
  height: 13px;
  border-radius: 6px;
}
.k-skel-b {
  width: 18%;
  height: 13px;
  border-radius: 6px;
  margin-left: 32px;
}
.k-skel-c {
  width: 56px;
  height: 13px;
  border-radius: 6px;
  margin-left: auto;
}
/* Tono coherente con el tema (el "wave" de q-skeleton hace el brillo por encima). */
.k-skel :deep(.q-skeleton) {
  background: var(--k-surface-2);
}
</style>
