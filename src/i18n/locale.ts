import { en } from './en'
import { es } from './es'
import { pt } from './pt'
import { LOCALES, type I18nText, type Locale, type MessageKey, type Messages } from './types'

export const MESSAGES: Record<Locale, Messages> = { es, en, pt }

// Nombre de cada idioma en su propio idioma, para el selector.
export const LOCALE_NAMES: Record<Locale, string> = { es: 'Español', en: 'English', pt: 'Português' }

// Para fechas y números (Intl) y para el atributo lang del documento.
export const LOCALE_TAGS: Record<Locale, string> = { es: 'es-AR', en: 'en', pt: 'pt-BR' }

export const STORAGE_KEY = 'ava-campus-locale'

export function isLocale(value: unknown): value is Locale {
  return typeof value === 'string' && (LOCALES as readonly string[]).includes(value)
}

// Primer idioma soportado de una lista como navigator.languages ("pt-BR" → "pt").
export function localeFromLanguages(languages: readonly string[]): Locale | null {
  for (const tag of languages) {
    const base = tag.toLowerCase().split('-')[0]
    if (isLocale(base)) return base
  }
  return null
}

// Orden: lo que eligió la persona en este navegador, lo guardado en su cuenta, el idioma
// del navegador y, si nada coincide, español.
export function detectLocale(stored: string | null, account: unknown, languages: readonly string[]): Locale {
  if (isLocale(stored)) return stored
  if (isLocale(account)) return account
  return localeFromLanguages(languages) ?? 'es'
}

export function translate(locale: Locale, key: MessageKey, params?: Record<string, string | number>): string {
  const template = MESSAGES[locale][key] ?? MESSAGES.es[key]
  if (!params) return template
  return template.replace(/\{(\w+)\}/g, (match, name: string) => (name in params ? String(params[name]) : match))
}

// Texto de la base en el idioma pedido; si falta o está vacío, en español.
export function pickText(value: I18nText | null | undefined, locale: Locale): string {
  if (!value) return ''
  const own = value[locale]?.trim()
  if (own) return own
  return value.es?.trim() ?? ''
}
