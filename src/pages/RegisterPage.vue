<template>
  <q-layout view="lHh Lpr lFf">
    <q-page-container>
      <q-page class="k-register flex flex-center q-pa-md">
        <q-card class="k-reg-card row no-wrap">
          <!-- Panel de branding + beneficios -->
          <div class="k-reg-aside col-5 gt-sm column justify-between">
            <div class="row items-center q-gutter-sm">
              <img class="k-reg-logo" src="/brand/badge.svg" alt="" aria-hidden="true" />
              <span class="k-reg-brand">Emmisa</span>
            </div>

            <div>
              <div class="k-reg-headline">Empieza a facturar hoy.</div>
              <div class="k-reg-sub">
                Crea tu cuenta gratis y emite tu primer comprobante en minutos.
              </div>
            </div>

            <div class="column q-gutter-md">
              <div class="k-reg-point">
                <q-icon name="check_circle" size="18px" /> Boletas y facturas válidas ante SUNAT
              </div>
              <div class="k-reg-point">
                <q-icon name="check_circle" size="18px" /> POS, inventario, caja y reportes
              </div>
              <div class="k-reg-point">
                <q-icon name="check_circle" size="18px" /> Gratis para empezar · sin tarjeta
              </div>
            </div>
          </div>

          <!-- Panel del formulario -->
          <div class="col column justify-center k-reg-form">
            <div class="text-h5 text-weight-bold">Crea tu cuenta</div>
            <div class="k-reg-muted text-caption q-mb-lg">Regístrate en segundos</div>

            <q-form @submit.prevent="submit">
              <q-input
                v-model="email"
                class="q-mb-md"
                outlined
                type="email"
                label="Email"
                :rules="emailRegRules"
              />
              <q-input
                v-model="password"
                class="q-mb-md"
                outlined
                type="password"
                label="Contraseña"
                hint="Mínimo 6 caracteres"
                :rules="passwordRules"
              />
              <q-btn
                type="submit"
                unelevated
                color="primary"
                size="lg"
                class="full-width"
                :loading="loading"
                label="Registrarme"
              />
            </q-form>

            <div class="row items-center q-my-md">
              <q-separator class="col k-reg-sep" />
              <span class="q-mx-md text-caption k-reg-muted">o</span>
              <q-separator class="col k-reg-sep" />
            </div>

            <q-btn
              outline
              color="white"
              size="lg"
              class="full-width"
              icon="img:https://www.google.com/favicon.ico"
              label="Continuar con Google"
              :loading="googleLoading"
              @click="loginGoogle"
            />

            <div class="text-center q-mt-lg text-caption k-reg-muted">
              ¿Ya tienes cuenta?
              <q-btn flat dense no-caps color="primary" label="Inicia sesión" :to="{ name: 'login' }" />
            </div>
          </div>
        </q-card>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { required, emailRules, validate, type Rule } from '@/lib/validation'
import { notify } from '@/lib/toast'

const auth = useAuthStore()
const router = useRouter()

const email = ref('')
const password = ref('')
const loading = ref(false)
const googleLoading = ref(false)

const emailRegRules: Rule[] = [required('Email obligatorio'), ...emailRules]
const passwordRules: Rule[] = [
  required('Contraseña obligatoria'),
  (v) => String(v ?? '').length >= 6 || 'Mínimo 6 caracteres',
]

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
    [email.value, emailRegRules],
    [password.value, passwordRules],
  ])
  if (err) {
    notify({ type: 'warning', message: err })
    return
  }
  loading.value = true
  try {
    const { needsVerification } = await auth.signUp(email.value, password.value)
    if (needsVerification) {
      router.push({ name: 'verify', query: { email: email.value } })
      return
    }
    if (auth.user) router.push({ name: 'dashboard' })
  } catch (e) {
    notify({ type: 'negative', message: (e as Error).message })
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
/* Fondo: la imagen, con un velo oscuro para que el vidrio se lea */
.k-register {
  min-height: 100vh;
  background-color: #0b0b14;
  background-image:
    linear-gradient(rgba(8, 8, 14, 0.68), rgba(8, 8, 14, 0.82)),
    url('https://images.unsplash.com/photo-1600880292203-757bb62b4baf?auto=format&fit=crop&w=1600&q=80');
  background-size: cover;
  background-position: center;
}

/* Tarjeta de vidrio (glassmorphism): la imagen se ve a través */
.k-reg-card {
  width: 100%;
  max-width: 880px;
  overflow: hidden;
  border-radius: 22px;
  color: #f4f4f6;
  background: rgba(16, 16, 26, 0.86);
  backdrop-filter: blur(28px) saturate(130%);
  -webkit-backdrop-filter: blur(28px) saturate(130%);
  border: 1px solid rgba(255, 255, 255, 0.12);
  box-shadow: 0 30px 80px rgba(0, 0, 0, 0.5);
}

/* Panel izquierdo: índigo translúcido que se funde con el vidrio */
.k-reg-aside {
  padding: 44px;
  color: #fff;
  background: linear-gradient(160deg, rgba(99, 102, 241, 0.16), rgba(99, 102, 241, 0.03));
  border-right: 1px solid rgba(255, 255, 255, 0.1);
}
.k-reg-logo {
  width: 40px;
  height: 40px;
  border-radius: 12px;
  background: #fff;
  color: #4338ca;
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: 'Hanken Grotesk', sans-serif;
  font-weight: 800;
  font-size: 20px;
}
.k-reg-brand {
  font-family: 'Hanken Grotesk', sans-serif;
  font-weight: 700;
  font-size: 20px;
}
.k-reg-headline {
  font-family: 'Hanken Grotesk', sans-serif;
  font-weight: 800;
  font-size: 30px;
  line-height: 1.12;
  letter-spacing: -0.8px;
  margin-bottom: 12px;
}
.k-reg-sub {
  font-size: 15px;
  color: rgba(255, 255, 255, 0.82);
  line-height: 1.5;
}
.k-reg-point {
  display: flex;
  align-items: center;
  gap: 10px;
  color: rgba(255, 255, 255, 0.92);
  font-size: 14px;
}
.k-reg-point .q-icon {
  color: #c7d2fe;
}

/* Panel del formulario (sobre el vidrio) */
.k-reg-form {
  padding: 44px;
}
.k-reg-muted {
  color: rgba(255, 255, 255, 0.6);
}
.k-reg-sep {
  background: rgba(255, 255, 255, 0.14);
}

/* Inputs estilo vidrio (independiente del tema claro/oscuro) */
.k-reg-card :deep(.q-field--outlined .q-field__control) {
  background: rgba(255, 255, 255, 0.06);
  border-radius: 12px;
}
.k-reg-card :deep(.q-field--outlined .q-field__control::before) {
  border-color: rgba(255, 255, 255, 0.18);
}
.k-reg-card :deep(.q-field--outlined .q-field__control:hover::before) {
  border-color: rgba(255, 255, 255, 0.32);
}
.k-reg-card :deep(.q-field__label),
.k-reg-card :deep(.q-field__native) {
  color: rgba(255, 255, 255, 0.9);
}
.k-reg-card :deep(.q-field__messages) {
  color: rgba(255, 255, 255, 0.5);
}
</style>
