// Traduce los mensajes crudos (en inglés) de Supabase Auth a español, y neutraliza
// los que permitirían ENUMERAR cuentas (p. ej. "User already registered").

export function authErrorMessage(e: unknown): string {
  const raw = (e as Error)?.message ?? String(e ?? '')
  const m = raw.toLowerCase()
  if (m.includes('invalid login credentials')) return 'Correo o contraseña incorrectos.'
  if (m.includes('email not confirmed')) return 'Tu correo aún no está verificado. Revisa tu bandeja.'
  // No confirmar si la cuenta existe (anti-enumeración).
  if (m.includes('already registered') || m.includes('already been registered')) {
    return 'No se pudo completar el registro. Si ya tienes cuenta, inicia sesión o recupera tu contraseña.'
  }
  if (m.includes('rate limit') || m.includes('too many requests')) {
    return 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.'
  }
  if (m.includes('password should be at least') || m.includes('password is too short')) {
    return 'La contraseña debe tener al menos 6 caracteres.'
  }
  if (m.includes('invalid email') || m.includes('unable to validate email')) return 'Correo electrónico inválido.'
  if (m.includes('token has expired') || m.includes('expired') || m.includes('otp') || m.includes('invalid token')) {
    return 'El código expiró o es inválido. Solicita uno nuevo.'
  }
  if (m.includes('network') || m.includes('failed to fetch') || m.includes('load failed')) {
    return 'Problema de conexión. Revisa tu internet e inténtalo de nuevo.'
  }
  // Fallback: no filtrar el mensaje interno crudo.
  return 'No se pudo completar la operación. Inténtalo de nuevo.'
}
