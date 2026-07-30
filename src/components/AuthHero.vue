<template>
  <div class="k-hero gt-sm column justify-between">
    <div class="row items-center q-gutter-sm">
      <img
        class="k-logo-sm"
        src="/brand/badge.svg"
        alt=""
        aria-hidden="true"
      >
      <span class="k-hero-brand">Emmisa</span>
    </div>

    <div>
      <div class="k-hero-title">
        {{ title }}
      </div>
      <div class="k-hero-sub">
        {{ subtitle }}
      </div>
    </div>

    <div class="column q-gutter-sm">
      <div class="k-hero-point">
        <q-icon
          name="check_circle"
          size="20px"
        /> Emite boletas y facturas ante SUNAT
      </div>
      <div class="k-hero-point">
        <q-icon
          name="check_circle"
          size="20px"
        /> Multiempresa, POS, inventario y caja
      </div>
      <div class="k-hero-point">
        <q-icon
          name="check_circle"
          size="20px"
        /> Reportes y comprobantes en tiempo real
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
defineProps<{ title: string; subtitle: string }>()
</script>

<style scoped>
.k-hero {
  flex: 0 0 62%;
  max-width: 62%;
  min-height: 100vh;
  padding: 56px;
  color: #fff;
  /* Fondo propio (sin hotlink a Unsplash: evita fuga de referrer y funciona offline). */
  background-color: #1e1b4b;
  background-image:
    radial-gradient(900px 500px at 15% 0%, rgba(99, 102, 241, 0.45), transparent 60%),
    radial-gradient(700px 500px at 90% 100%, rgba(59, 130, 246, 0.28), transparent 55%),
    linear-gradient(135deg, #17153b, #0a0a0c);
}
.k-logo-sm {
  width: 40px;
  height: 40px;
  border-radius: 12px;
  background: var(--q-primary);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: 'Hanken Grotesk', sans-serif;
  font-weight: 800;
  font-size: 20px;
}
.k-hero-brand {
  font-family: 'Hanken Grotesk', sans-serif;
  font-weight: 700;
  font-size: 22px;
}
.k-hero-title {
  font-family: 'Hanken Grotesk', sans-serif;
  font-weight: 800;
  font-size: 44px;
  line-height: 1.08;
  letter-spacing: -1.2px;
  margin-bottom: 14px;
  max-width: 500px;
}
.k-hero-sub {
  font-size: 16px;
  color: rgba(255, 255, 255, 0.72);
  max-width: 440px;
  line-height: 1.5;
}
.k-hero-point {
  display: flex;
  align-items: center;
  gap: 10px;
  color: rgba(255, 255, 255, 0.88);
  font-size: 14.5px;
}
.k-hero-point .q-icon {
  color: #a5b4fc;
}
</style>
