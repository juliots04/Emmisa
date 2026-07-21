<template>
  <div class="k-hero gt-sm column justify-between">
    <div class="row items-center q-gutter-sm">
      <img class="k-logo-sm" src="/brand/badge.svg" alt="" aria-hidden="true" />
      <span class="k-hero-brand">Emmisa</span>
    </div>

    <div>
      <div class="k-hero-title">{{ title }}</div>
      <div class="k-hero-sub">{{ subtitle }}</div>
    </div>

    <div class="column q-gutter-sm">
      <div class="k-hero-point">
        <q-icon name="check_circle" size="20px" /> Emite boletas y facturas ante SUNAT
      </div>
      <div class="k-hero-point">
        <q-icon name="check_circle" size="20px" /> Multiempresa, POS, inventario y caja
      </div>
      <div class="k-hero-point">
        <q-icon name="check_circle" size="20px" /> Reportes y comprobantes en tiempo real
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
  background-color: #1e1b4b;
  background-image:
    linear-gradient(135deg, rgba(23, 21, 59, 0.82), rgba(10, 10, 12, 0.92)),
    url('https://images.unsplash.com/photo-1554224155-6726b3ff858f?auto=format&fit=crop&w=1600&q=80');
  background-size: cover;
  background-position: center;
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
