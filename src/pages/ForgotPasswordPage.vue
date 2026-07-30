<template>
  <q-layout view="lHh Lpr lFf">
    <q-page-container>
      <q-page class="flex flex-center q-pa-md">
        <q-card
          flat
          bordered
          class="k-auth-card q-pa-lg"
        >
          <div class="text-h6 text-weight-bold q-mb-xs">
            Recuperar contraseña
          </div>
          <div class="text-caption text-muted q-mb-lg">
            Te enviaremos un enlace para crear una nueva contraseña.
          </div>

          <template v-if="!enviado">
            <q-form @submit.prevent="enviar">
              <q-input
                v-model="email"
                outlined
                type="email"
                label="Email de tu cuenta"
                class="q-mb-md"
                :rules="emailRegRules"
              />
              <q-btn
                type="submit"
                unelevated
                color="primary"
                size="lg"
                class="full-width"
                :loading="loading"
                label="Enviar enlace"
              />
            </q-form>
          </template>

          <q-banner
            v-else
            class="k-banner--info"
            rounded
          >
            <template #avatar>
              <q-icon name="mark_email_read" />
            </template>
            Si el correo existe, te enviamos un enlace para restablecer tu contraseña. Revisa tu
            bandeja (y spam).
          </q-banner>

          <div class="text-center q-mt-lg">
            <q-btn
              flat
              dense
              no-caps
              color="primary"
              icon="arrow_back"
              label="Volver a iniciar sesión"
              :to="{ name: 'login' }"
            />
          </div>
        </q-card>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { required, emailRules, validate, type Rule } from '@/lib/validation'
import { notify } from '@/lib/toast'

const auth = useAuthStore()
const email = ref('')
const loading = ref(false)
const enviado = ref(false)

const emailRegRules: Rule[] = [required('Email obligatorio'), ...emailRules]

async function enviar() {
  const err = validate([[email.value, emailRegRules]])
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  loading.value = true
  try {
    await auth.sendPasswordReset(email.value)
    enviado.value = true
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.k-auth-card {
  width: 100%;
  max-width: 420px;
  border-radius: 16px;
}
</style>
