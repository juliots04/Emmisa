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
            Nueva contraseña
          </div>
          <div class="text-caption text-muted q-mb-lg">
            Elige una contraseña nueva para tu cuenta.
          </div>

          <q-form @submit.prevent="guardar">
            <q-input
              v-model="password"
              outlined
              type="password"
              label="Nueva contraseña"
              hint="Mínimo 6 caracteres"
              class="q-mb-md"
              :rules="passwordRules"
            />
            <q-input
              v-model="password2"
              outlined
              type="password"
              label="Repite la contraseña"
              class="q-mb-md"
              :rules="[(v) => v === password || 'Las contraseñas no coinciden']"
            />
            <q-btn
              type="submit"
              unelevated
              color="primary"
              size="lg"
              class="full-width"
              :loading="loading"
              label="Guardar contraseña"
            />
          </q-form>
        </q-card>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { required, validate, type Rule } from '@/lib/validation'
import { notify } from '@/lib/toast'

const auth = useAuthStore()
const router = useRouter()

const password = ref('')
const password2 = ref('')
const loading = ref(false)

const passwordRules: Rule[] = [
  required('Contraseña obligatoria'),
  (v) => String(v ?? '').length >= 6 || 'Mínimo 6 caracteres',
]

async function guardar() {
  const err = validate([[password.value, passwordRules]])
  if (err || password.value !== password2.value) {
    notify({ type: 'warning', message: err ?? 'Las contraseñas no coinciden' })
    return
  }
  loading.value = true
  try {
    await auth.updatePassword(password.value)
    notify({ type: 'positive', message: 'Contraseña actualizada. Inicia sesión.' })
    await auth.signOut()
    router.push({ name: 'login' })
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
