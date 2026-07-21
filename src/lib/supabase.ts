import { createClient } from '@supabase/supabase-js'
import { env } from './env'

// Cliente único de Supabase para toda la app.
// El aislamiento por empresa lo garantiza el RLS en la base de datos.
export const supabase = createClient(env.supabaseUrl, env.supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
})
