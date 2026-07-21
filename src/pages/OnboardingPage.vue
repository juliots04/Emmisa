<template>
  <q-layout view="lHh Lpr lFf">
    <q-page-container>
      <q-page class="flex flex-center q-pa-md">
        <div class="k-onboarding column items-center">
          <div class="text-center q-mb-lg">
            <img class="k-logo q-mx-auto q-mb-md" src="/brand/badge.svg" alt="Emmisa" />
            <div class="text-h4 text-weight-bold">Crea tu negocio</div>
            <div class="text-caption text-muted q-mt-xs">
              Configura tu empresa para empezar a facturar
            </div>
          </div>

          <q-card class="k-onboarding__card">
            <q-stepper
              v-model="step"
              flat
              animated
              header-nav
              color="primary"
              active-color="primary"
              done-color="positive"
              class="k-stepper"
            >
              <!-- Paso 1: datos del negocio -->
              <q-step :name="1" title="Negocio" icon="business" :done="step > 1">
                <div class="q-gutter-md">
                  <q-input
                    v-model="ruc"
                    outlined
                    label="RUC *"
                    inputmode="numeric"
                    maxlength="11"
                    mask="###########"
                    unmasked-value
                    hint="11 dígitos"
                    :rules="rucRules"
                  />
                  <q-input
                    v-model="razonSocial"
                    outlined
                    label="Razón social *"
                    :rules="nameRules"
                  />
                  <q-select
                    v-model="regimen"
                    outlined
                    label="Régimen *"
                    :options="regimenOptions"
                    :rules="[required()]"
                  />
                </div>
              </q-step>

              <!-- Paso 2: ubicación -->
              <q-step :name="2" title="Ubicación" icon="place" :done="step > 2">
                <div class="q-gutter-md">
                  <q-input
                    v-model="direccion"
                    outlined
                    label="Dirección"
                    :rules="[maxLen(200)]"
                  />
                  <q-input
                    v-model="ubigeo"
                    outlined
                    label="Ubigeo"
                    inputmode="numeric"
                    maxlength="6"
                    mask="######"
                    unmasked-value
                    hint="código de 6 dígitos (opcional)"
                    :rules="ubigeo ? [onlyDigits(), exactLen(6, 'Ubigeo: 6 dígitos')] : []"
                  />
                </div>
              </q-step>

              <!-- Paso 3: confirmar -->
              <q-step :name="3" title="Confirmar" icon="check_circle">
                <div class="k-review">
                  <div class="k-review__row">
                    <span class="text-muted">RUC</span><span>{{ ruc || '—' }}</span>
                  </div>
                  <div class="k-review__row">
                    <span class="text-muted">Razón social</span><span>{{ razonSocial || '—' }}</span>
                  </div>
                  <div class="k-review__row">
                    <span class="text-muted">Régimen</span><span>{{ regimen }}</span>
                  </div>
                  <div class="k-review__row">
                    <span class="text-muted">Dirección</span><span>{{ direccion || '—' }}</span>
                  </div>
                  <div class="k-review__row">
                    <span class="text-muted">Ubigeo</span><span>{{ ubigeo || '—' }}</span>
                  </div>
                </div>
              </q-step>

              <template #navigation>
                <q-stepper-navigation class="row items-center">
                  <q-btn v-if="step > 1" flat color="primary" label="Atrás" @click="step--" />
                  <q-space />
                  <q-btn
                    v-if="step < 3"
                    unelevated
                    color="primary"
                    label="Siguiente"
                    @click="next"
                  />
                  <q-btn
                    v-else
                    unelevated
                    color="primary"
                    label="Crear y continuar"
                    :loading="loading"
                    @click="submit"
                  />
                </q-stepper-navigation>
              </template>
            </q-stepper>
          </q-card>

          <div class="column items-center q-gutter-xs q-mt-md">
            <q-btn
              flat
              dense
              no-caps
              color="primary"
              icon="science"
              label="Usar datos de demo"
              @click="fillDemo"
            />
            <q-btn
              flat
              dense
              no-caps
              color="grey"
              icon="arrow_back"
              label="Volver al login"
              @click="backToLogin"
            />
          </div>
        </div>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { notify } from '@/lib/toast'
import { useAuthStore } from '@/stores/auth'
import { useCompanyStore } from '@/stores/company'
import type { Regimen } from '@/types'
import { validate, rucRules, nameRules, required, maxLen, onlyDigits, exactLen } from '@/lib/validation'

const company = useCompanyStore()
const auth = useAuthStore()
const router = useRouter()

const step = ref(1)
const ruc = ref('')
const razonSocial = ref('')
const regimen = ref<Regimen>('RER')
const direccion = ref('')
const ubigeo = ref('')
const loading = ref(false)

const regimenOptions: Regimen[] = ['RER', 'RMT', 'GENERAL', 'NRUS']

function next() {
  if (step.value === 1) {
    const err = validate([
      [ruc.value, rucRules],
      [razonSocial.value, nameRules],
      [regimen.value, [required()]],
    ])
    if (err) {
      notify({ type: 'warning', message: err })
      return
    }
  }
  step.value++
}

function fillDemo() {
  ruc.value = '20000000001'
  razonSocial.value = 'EMPRESA DEMO S.A.C.'
  regimen.value = 'GENERAL'
  direccion.value = 'Av. Demo 123, Lima'
  ubigeo.value = '150101'
  notify({ type: 'info', message: 'Datos de demo cargados' })
}

async function backToLogin() {
  await auth.signOut()
  company.reset()
  router.push({ name: 'login' })
}

async function submit() {
  const step1Err = validate([
    [ruc.value, rucRules],
    [razonSocial.value, nameRules],
    [regimen.value, [required()]],
  ])
  if (step1Err) {
    step.value = 1
    notify({ type: 'warning', message: step1Err })
    return
  }
  const err = validate([
    [direccion.value, [maxLen(200)]],
    [ubigeo.value, ubigeo.value ? [onlyDigits(), exactLen(6, 'Ubigeo: 6 dígitos')] : []],
  ])
  if (err) {
    step.value = 2
    notify({ type: 'warning', message: err })
    return
  }
  loading.value = true
  try {
    await company.create({
      ruc: ruc.value,
      razon_social: razonSocial.value,
      regimen: regimen.value,
      direccion: direccion.value || undefined,
      ubigeo: ubigeo.value || undefined,
    })
    notify({ type: 'positive', message: 'Empresa creada' })
    router.push({ name: 'dashboard' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.k-onboarding {
  width: 100%;
  max-width: 520px;
}
.k-onboarding__card {
  width: 100%;
}
.k-review__row {
  display: flex;
  justify-content: space-between;
  padding: 10px 0;
  border-bottom: 1px solid var(--k-border);
}
.k-review__row:last-child {
  border-bottom: none;
}
</style>
