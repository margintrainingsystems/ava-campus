import type { MessageKey } from '../i18n/types'

// Mismo criterio que el CRM y Núcleo: un email válido no tiene espacios, saltos de línea,
// comas, punto y coma ni signos que permitan inyectar destinatarios en un mailto:.
const EMAIL_RE = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/

export function normalizeEmail(value: string): string {
  return value.trim().toLowerCase()
}

export function isValidEmail(value: string): boolean {
  const email = value.trim()
  if (email.length < 3 || email.length > 320) return false
  if (email.includes('..')) return false
  return EMAIL_RE.test(email)
}

export const PASSWORD_MIN_LENGTH = 10

// Devuelve la clave del problema de la contraseña, o null si sirve.
export function passwordProblem(password: string, confirmation: string): MessageKey | null {
  if (password.length < PASSWORD_MIN_LENGTH) return 'validation.passwordShort'
  if (!/[A-Za-z]/.test(password) || !/[0-9]/.test(password)) return 'validation.passwordMix'
  if (password !== confirmation) return 'validation.passwordMatch'
  return null
}
