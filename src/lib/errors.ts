import type { MessageKey } from '../i18n/types'

// Traduce los errores de Supabase a la clave del mensaje que ve la persona.
type ErrorLike = { code?: string; message?: string; status?: number } | null | undefined

const BY_CODE: Record<string, MessageKey> = {
  '42501': 'error.permission',
  PGRST116: 'error.notFound',
  invalid_credentials: 'error.credentials',
  email_not_confirmed: 'error.notConfirmed',
  over_request_rate_limit: 'error.rateLimit',
  over_email_send_rate_limit: 'error.emailRateLimit',
  same_password: 'error.samePassword',
  weak_password: 'error.weakPassword',
  session_not_found: 'error.session',
  user_banned: 'error.banned',
}

export function errorKey(error: unknown, fallback: MessageKey = 'error.generic'): MessageKey {
  const e = error as ErrorLike
  if (!e) return fallback
  if (e.code && BY_CODE[e.code]) return BY_CODE[e.code] as MessageKey
  if (e.message && /Failed to fetch|NetworkError|Load failed/i.test(e.message)) return 'error.network'
  if (e.status === 429) return 'error.rateLimit'
  return fallback
}
