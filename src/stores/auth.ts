import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { Session, User } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'
import { useCompanyStore } from '@/stores/company'
import { useQueryCacheStore } from '@/stores/queryCache'

export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(null)
  const session = ref<Session | null>(null)
  let initialized = false

  async function init() {
    if (initialized) return
    initialized = true
    const { data } = await supabase.auth.getSession()
    session.value = data.session
    user.value = data.session?.user ?? null
    supabase.auth.onAuthStateChange((_event, newSession) => {
      session.value = newSession
      user.value = newSession?.user ?? null
      // Sesión cerrada por CUALQUIER vía (logout, expiración, otra pestaña): limpia el
      // estado dependiente para no dejar la empresa del usuario anterior visible al
      // siguiente (dispositivo compartido). Antes el reset solo estaba en los botones.
      if (!newSession) {
        useCompanyStore().reset()
        useQueryCacheStore().clear()
      }
    })
  }

  async function signIn(email: string, password: string) {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) throw error
    session.value = data.session
    user.value = data.user
  }

  async function signUp(email: string, password: string): Promise<{ needsVerification: boolean }> {
    const { data, error } = await supabase.auth.signUp({ email, password })
    if (error) throw error
    if (data.session) {
      // "Confirm email" desactivado: entra directo.
      session.value = data.session
      user.value = data.user
      return { needsVerification: false }
    }
    // "Confirm email" activado: falta verificar el correo con un código.
    return { needsVerification: true }
  }

  async function verifyEmailOtp(email: string, token: string) {
    const { data, error } = await supabase.auth.verifyOtp({ email, token, type: 'signup' })
    if (error) throw error
    session.value = data.session
    user.value = data.user
  }

  async function resendSignupCode(email: string) {
    const { error } = await supabase.auth.resend({ type: 'signup', email })
    if (error) throw error
  }

  async function sendPasswordReset(email: string) {
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/nueva-contrasena`,
    })
    if (error) throw error
  }

  async function updatePassword(newPassword: string) {
    const { error } = await supabase.auth.updateUser({ password: newPassword })
    if (error) throw error
  }

  async function signInWithGoogle() {
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.origin },
    })
    if (error) throw error
    // El navegador se redirige a Google; al volver, la sesión se detecta sola.
  }

  async function signOut() {
    try {
      await supabase.auth.signOut()
    } finally {
      // Garantiza la limpieza local aunque la llamada de red falle (offline):
      // el listener onAuthStateChange también resetea, esto es cinturón-y-tirantes.
      useCompanyStore().reset()
      useQueryCacheStore().clear()
    }
  }

  return {
    user,
    session,
    init,
    signIn,
    signUp,
    signInWithGoogle,
    verifyEmailOtp,
    resendSignupCode,
    sendPasswordReset,
    updatePassword,
    signOut,
  }
})
