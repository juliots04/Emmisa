import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { Session, User } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'

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

  async function signInWithGoogle() {
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.origin },
    })
    if (error) throw error
    // El navegador se redirige a Google; al volver, la sesión se detecta sola.
  }

  async function signOut() {
    await supabase.auth.signOut()
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
    signOut,
  }
})
