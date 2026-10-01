import type { es } from './es'

export type MessageKey = keyof typeof es
export type Messages = Record<MessageKey, string>

export const LOCALES = ['es', 'en', 'pt'] as const
export type Locale = (typeof LOCALES)[number]

// Texto traducible que viene de la base: { es, en?, pt? }.
export type I18nText = Partial<Record<Locale, string>>
