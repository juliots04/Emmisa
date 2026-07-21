<template>
  <q-layout view="lHh Lpr lFf">
    <q-page-container>
      <q-page class="flex flex-center q-pa-md">
        <q-card style="width: 380px" class="q-pa-lg">
          <q-card-section class="text-center q-pb-md">
            <img class="k-logo q-mx-auto q-mb-md" src="/brand/badge.svg" alt="Emmisa" />
            <div class="text-h5 text-weight-bold">Verifica tu correo</div>
            <div class="text-caption text-muted q-mt-xs">
              Ingresa el código que enviamos a
              <div class="text-weight-medium q-mt-xs">{{ email || 'tu correo' }}</div>
            </div>
          </q-card-section>

          <q-form class="q-gutter-md" @submit.prevent="verify">
            <q-input
              v-model="code"
              outlined
              label="Código de 6 dígitos"
              inputmode="numeric"
              maxlength="6"
              mask="######"
              unmasked-value
              autofocus
              :rules="codeRules"
            />
            <q-btn
              type="submit"
              unelevated
              color="primary"
              size="lg"
              class="full-width"
              :loading="loading"
              label="Verificar"
            />
          </q-form>

          <q-card-section class="text-center q-pt-sm">
            <q-btn
              flat
              dense
              no-caps
              color="primary"
              :loading="resending"
              label="Reenviar código"
              @click="resend"
            />
            <div>
              <q-btn flat dense no-caps color="grey" label="Volver" :to="{ name: 'login' }" />
            </div>
          </q-card-section>
        </q-card>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { validate, required, onlyDigits, exactLen } from '@/lib/validation'
import { notify } from '@/lib/toast'

const auth = useAuthStore()
const route = useRoute()
const router = useRouter()

const email = ref(String(route.query.email ?? ''))
const code = ref('')
const loading = ref(false)
const resending = ref(false)

const codeRules = [required('Código obligatorio'), onlyDigits(), exactLen(6, 'El código tiene 6 dígitos')]

async function verify() {
  const err = validate([[code.value, codeRules]])
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  if (!email.value) {
    notify({ type: 'negative', message: 'Falta el correo. Vuelve a registrarte.' })
    return
  }
  loading.value = true
  try {
    await auth.verifyEmailOtp(email.value, code.value)
    notify({ type: 'positive', message: 'Correo verificado' })
    router.push({ name: 'dashboard' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
}

async function resend() {
  if (!email.value) return
  resending.value = true
  try {
    await auth.resendSignupCode(email.value)
    notify({ type: 'info', message: 'Código reenviado a tu correo' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    resending.value = false
  }
}
</script>
