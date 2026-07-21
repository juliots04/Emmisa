<template>
  <q-layout view="lHh Lpr lFf">
    <q-page-container>
      <q-page class="row no-wrap">
        <AuthHero
          title="Bienvenido de nuevo."
          subtitle="Inicia sesión y sigue facturando sin complicaciones."
        />

        <div class="k-login-side col column flex-center">
          <div class="k-login-inner">
            <div class="lt-md q-mb-lg">
              <img class="k-logo" src="/brand/badge.svg" alt="Emmisa" />
            </div>

            <div class="text-h4 text-weight-bold">Inicia sesión</div>
            <div class="text-body2 text-muted q-mb-xl">Bienvenido de nuevo a Emmisa</div>

            <q-form @submit.prevent="submit">
              <q-input
                v-model="email"
                class="q-mb-md"
                outlined
                type="email"
                label="Email"
                :rules="emailFieldRules"
              />
              <q-input
                v-model="password"
                class="q-mb-md"
                outlined
                type="password"
                label="Contraseña"
                :rules="passwordRules"
              />
              <q-btn
                type="submit"
                unelevated
                color="primary"
                size="lg"
                class="full-width"
                :loading="loading"
                label="Entrar"
              />
            </q-form>

            <div class="row items-center q-my-lg">
              <q-separator class="col" />
              <span class="q-mx-md text-caption text-muted">o</span>
              <q-separator class="col" />
            </div>

            <q-btn
              outline
              color="grey-8"
              size="lg"
              class="full-width"
              icon="img:https://www.google.com/favicon.ico"
              label="Continuar con Google"
              :loading="googleLoading"
              @click="loginGoogle"
            />

            <div class="text-center q-mt-lg text-caption text-muted">
              ¿No tienes cuenta?
              <q-btn flat dense no-caps color="primary" label="Regístrate" :to="{ name: 'register' }" />
            </div>
          </div>
        </div>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import AuthHero from '@/components/AuthHero.vue'
import { required, emailRules, validate } from '@/lib/validation'
import { notify } from '@/lib/toast'

const auth = useAuthStore()
const router = useRouter()

const email = ref('')
const password = ref('')
const loading = ref(false)
const googleLoading = ref(false)

const emailFieldRules = [required('Email obligatorio'), ...emailRules]
const passwordRules = [required('Contraseña obligatoria')]

async function loginGoogle() {
  googleLoading.value = true
  try {
    await auth.signInWithGoogle()
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
    googleLoading.value = false
  }
}

async function submit() {
  const err = validate([
    [email.value, emailFieldRules],
    [password.value, passwordRules],
  ])
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  loading.value = true
  try {
    await auth.signIn(email.value, password.value)
    if (auth.user) router.push({ name: 'dashboard' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.k-login-side {
  min-height: 100vh;
  padding: 24px 48px;
}
.k-login-inner {
  width: 100%;
  max-width: 400px;
}
</style>
