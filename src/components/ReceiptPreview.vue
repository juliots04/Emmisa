<template>
  <div
    class="receipt"
    :style="{ width: widthPx + 'px' }"
  >
    <!-- Emisor -->
    <div class="r-center">
      <div class="r-empresa">
        {{ data.empresa.razon_social }}
      </div>
      <div class="r-muted">
        RUC {{ data.empresa.ruc }}
      </div>
      <div
        v-if="data.empresa.direccion"
        class="r-muted"
      >
        {{ data.empresa.direccion }}
      </div>
    </div>

    <div class="r-sep" />

    <!-- Comprobante -->
    <div class="r-center">
      <div class="r-tipo">
        {{ data.tipoLabel }}
      </div>
      <div class="r-num">
        {{ data.numero || 'SERIE-000000' }}
      </div>
      <div class="r-muted">
        {{ data.fecha || 'Pendiente de emisión' }}
      </div>
    </div>

    <div class="r-sep" />

    <!-- Cliente -->
    <div class="r-cli">
      <div><span class="r-k">Cliente</span> {{ data.cliente?.denominacion || 'Cliente varios' }}</div>
      <div v-if="data.cliente?.numDoc">
        <span class="r-k">Doc.</span> {{ data.cliente.numDoc }}
      </div>
      <div v-if="data.cliente?.direccion">
        <span class="r-k">Dir.</span> {{ data.cliente.direccion }}
      </div>
    </div>

    <div class="r-sep" />

    <!-- Ítems -->
    <div class="r-items">
      <div class="r-item r-item--head">
        <span>Cant</span><span>Descripción</span><span class="r-right">Importe</span>
      </div>
      <div
        v-for="(it, i) in data.items"
        :key="i"
        class="r-item"
      >
        <span>{{ it.cantidad }}</span>
        <span class="r-desc">
          {{ it.descripcion }}
          <span class="r-unit">{{ money(it.precioUnitario) }} c/u</span>
        </span>
        <span class="r-right">{{ money(it.cantidad * it.precioUnitario) }}</span>
      </div>
      <div
        v-if="!data.items.length"
        class="r-muted r-center r-empty"
      >
        — sin ítems —
      </div>
    </div>

    <div class="r-sep" />

    <!-- Totales -->
    <div class="r-tot">
      <div
        v-if="data.descuento"
        class="r-row"
      >
        <span>Descuento</span><span>- {{ money(data.descuento) }}</span>
      </div>
      <div
        v-if="Number(data.gravado) > 0"
        class="r-row"
      >
        <span>Op. Gravada</span><span>{{ money(data.gravado) }}</span>
      </div>
      <div
        v-if="Number(data.exonerado) > 0"
        class="r-row"
      >
        <span>Op. Exonerada</span><span>{{ money(data.exonerado) }}</span>
      </div>
      <div
        v-if="Number(data.inafecto) > 0"
        class="r-row"
      >
        <span>Op. Inafecta</span><span>{{ money(data.inafecto) }}</span>
      </div>
      <div
        v-if="Number(data.exportacion) > 0"
        class="r-row"
      >
        <span>Exportación</span><span>{{ money(data.exportacion) }}</span>
      </div>
      <div class="r-row">
        <span>IGV (18%)</span><span>{{ money(data.igv) }}</span>
      </div>
      <div class="r-row r-total">
        <span>TOTAL</span><span>{{ symbol }} {{ money(data.total) }}</span>
      </div>
    </div>

    <!-- Importe en letras (leyenda obligatoria SUNAT) -->
    <div class="r-letras">
      {{ enLetras }}
    </div>

    <!-- Pago -->
    <template v-if="data.formaPago || data.condicionPago">
      <div class="r-sep" />
      <div class="r-tot">
        <div
          v-if="data.condicionPago"
          class="r-row"
        >
          <span>Condición</span><span>{{ data.condicionPago }}</span>
        </div>
        <div
          v-if="data.formaPago"
          class="r-row"
        >
          <span>Forma de pago</span><span>{{ data.formaPago }}</span>
        </div>
        <div
          v-if="data.recibido != null"
          class="r-row"
        >
          <span>Recibido</span><span>{{ money(data.recibido) }}</span>
        </div>
        <div
          v-if="data.vuelto != null"
          class="r-row"
        >
          <span>Vuelto</span><span>{{ money(data.vuelto) }}</span>
        </div>
      </div>
    </template>

    <div class="r-sep" />

    <!-- Pie -->
    <div class="r-center r-foot">
      <img
        v-if="qrImg"
        :src="qrImg"
        alt="Código QR del comprobante"
        class="r-qr-img"
      >
      <div class="r-thanks">
        ¡Gracias por su compra!
      </div>
      <div class="r-muted r-note">
        Representación impresa del comprobante electrónico.
      </div>
      <div
        v-if="data.hash"
        class="r-hash"
      >
        {{ data.hash }}
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { numeroALetras } from '@/lib/numeroALetras'
import { qrDataUrl } from '@/lib/qr'

export interface ReceiptItem {
  descripcion: string
  cantidad: number
  precioUnitario: number
}
export interface ReceiptData {
  empresa: { razon_social: string; ruc: string; direccion?: string | null }
  tipoLabel: string
  numero?: string | null
  fecha?: string | null
  cliente?: { denominacion: string; numDoc?: string | null; direccion?: string | null } | null
  items: ReceiptItem[]
  gravado: number
  igv: number
  exonerado?: number | null
  inafecto?: number | null
  exportacion?: number | null
  descuento?: number | null
  total: number
  moneda?: string
  formaPago?: string | null
  condicionPago?: string | null
  recibido?: number | null
  vuelto?: number | null
  hash?: string | null
  /** Cadena QR fiscal (formato SUNAT) — se renderiza como QR escaneable. */
  codigo_qr?: string | null
  preview?: boolean
  /** Ancho del ticket en mm (58 | 80). La vista previa se angosta para reflejarlo. */
  width?: 58 | 80
}

const props = defineProps<{ data: ReceiptData }>()

const symbol = computed(() => (props.data.moneda === 'USD' ? 'US$' : 'S/'))
const qrImg = computed(() => (props.data.codigo_qr ? qrDataUrl(props.data.codigo_qr, 4, 1) : ''))
// 80mm ≈ 300px; 58mm proporcional ≈ 220px.
const widthPx = computed(() => (props.data.width === 58 ? 220 : 300))
const enLetras = computed(() => numeroALetras(props.data.total, props.data.moneda))
function money(n?: number | null): string {
  return Number(n ?? 0).toFixed(2)
}
</script>

<style scoped>
/* Recibo estilo ticket térmico · siempre papel blanco (como el impreso real) */
.receipt {
  position: relative;
  width: 300px;
  max-width: 100%;
  transition: width 0.28s cubic-bezier(0.22, 1, 0.36, 1);
  background: #ffffff;
  color: #1c1c1e;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  line-height: 1.55;
  padding: 20px 18px 24px;
  border-radius: 8px;
  box-shadow: 0 6px 26px rgba(0, 0, 0, 0.28);
}
/* Borde superior/inferior dentado (papel cortado) */
.receipt::before,
.receipt::after {
  content: '';
  position: absolute;
  left: 0;
  right: 0;
  height: 6px;
  background: repeating-linear-gradient(-45deg, #ffffff 0 6px, transparent 6px 12px),
    repeating-linear-gradient(45deg, #ffffff 0 6px, transparent 6px 12px);
  background-size: 12px 12px;
}
.receipt::before {
  top: -6px;
}
.receipt::after {
  bottom: -6px;
}

.r-flag {
  position: absolute;
  top: 10px;
  right: -6px;
  background: #f59e0b;
  color: #201500;
  font-size: 9px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  padding: 3px 9px;
  border-radius: 4px 0 0 4px;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.25);
}

.r-center {
  text-align: center;
}
.r-empresa {
  font-weight: 700;
  font-size: 13px;
  text-transform: uppercase;
  letter-spacing: 0.3px;
}
.r-muted {
  color: #6b7075;
}
.r-sep {
  border-top: 1px dashed #c4c4c4;
  margin: 11px 0;
}
.r-tipo {
  font-weight: 700;
  letter-spacing: 0.3px;
}
.r-num {
  font-size: 14px;
  font-weight: 800;
  letter-spacing: 0.5px;
}
.r-k {
  color: #6b7075;
  margin-right: 4px;
}

.r-item {
  display: grid;
  grid-template-columns: 26px 1fr auto;
  gap: 8px;
  align-items: start;
}
.r-item--head {
  color: #8a8f94;
  font-size: 9.5px;
  text-transform: uppercase;
  letter-spacing: 0.3px;
  margin-bottom: 5px;
}
.r-desc {
  min-width: 0;
  overflow-wrap: anywhere;
}
.r-right {
  text-align: right;
  font-weight: 600;
}
.r-empty {
  padding: 6px 0;
}

.r-row {
  display: flex;
  justify-content: space-between;
  gap: 12px;
}
.r-total {
  font-weight: 800;
  font-size: 15px;
  margin-top: 6px;
  padding-top: 8px;
  border-top: 1px solid #e2e2e2;
}
.r-unit {
  display: block;
  color: #8a8f94;
  font-size: 9.5px;
}
.r-letras {
  margin-top: 11px;
  font-size: 10px;
  font-weight: 700;
  line-height: 1.45;
}

.r-foot {
  color: #6b7075;
}
.r-qr {
  width: 62px;
  height: 62px;
  margin: 0 auto 10px;
  border: 1px solid #d5d5d5;
  border-radius: 6px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #b0b0b0;
  font-weight: 700;
  letter-spacing: 2px;
}
/* QR real escaneable (pixelado nítido, sin suavizado). */
.r-qr-img {
  width: 104px;
  height: 104px;
  margin: 0 auto 10px;
  display: block;
  image-rendering: pixelated;
}
.r-thanks {
  font-weight: 700;
  color: #1c1c1e;
}
.r-note {
  font-size: 9.5px;
  margin-top: 2px;
}
.r-hash {
  font-size: 8.5px;
  color: #a0a0a0;
  word-break: break-all;
  margin-top: 8px;
}
</style>
