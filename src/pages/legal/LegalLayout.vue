<template>
  <q-page class="k-legal flex flex-center q-pa-md">
    <q-card class="k-legal-card">
      <q-card-section class="row items-center q-gutter-sm">
        <img
          class="k-legal-logo"
          src="/brand/badge.svg"
          alt=""
          aria-hidden="true"
        >
        <span class="k-legal-brand">Emmisa</span>
        <q-space />
        <q-btn
          flat
          dense
          no-caps
          color="primary"
          icon="arrow_back"
          label="Volver"
          @click="volver"
        />
      </q-card-section>
      <q-separator />
      <q-card-section class="k-legal-body">
        <div class="text-h5 text-weight-bold q-mb-xs">
          {{ titulo }}
        </div>
        <div class="text-caption text-muted q-mb-lg">
          Última actualización: {{ actualizado }}
        </div>
        <slot />
        <q-banner
          class="k-banner--info q-mt-xl"
          rounded
          dense
        >
          <template #avatar>
            <q-icon name="gavel" />
          </template>
          Este es un documento base. Antes de operar comercialmente, hazlo revisar por un abogado
          y regístralo/adecúalo a tu razón social, RUC y a la Autoridad Nacional de Protección de
          Datos Personales (ANPD).
        </q-banner>
      </q-card-section>
    </q-card>
  </q-page>
</template>

<script setup lang="ts">
import { useRouter } from 'vue-router'

defineProps<{ titulo: string; actualizado: string }>()

const router = useRouter()
function volver() {
  if (window.history.length > 1) router.back()
  else router.push({ name: 'login' })
}
</script>

<style scoped>
.k-legal {
  min-height: 100vh;
  background: var(--k-bg, #0b0b14);
}
.k-legal-card {
  width: 100%;
  max-width: 820px;
  border-radius: 18px;
}
.k-legal-logo {
  width: 32px;
  height: 32px;
  border-radius: 9px;
}
.k-legal-brand {
  font-family: 'Hanken Grotesk', sans-serif;
  font-weight: 700;
  font-size: 18px;
}
.k-legal-body {
  line-height: 1.6;
}
.k-legal-body :deep(h2) {
  font-size: 17px;
  font-weight: 700;
  margin: 22px 0 8px;
}
.k-legal-body :deep(p) {
  margin: 8px 0;
}
.k-legal-body :deep(ul) {
  padding-left: 20px;
  margin: 8px 0;
}
</style>
