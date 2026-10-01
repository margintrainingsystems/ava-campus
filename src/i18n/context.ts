import { createContext, useContext } from 'react'
import type { I18nText, Locale, MessageKey } from './types'

export type I18nContextValue = {
  locale: Locale
  setLocale: (locale: Locale) => void
  t: (key: MessageKey, params?: Record<string, string | number>) => string
  text: (value: I18nText | null | undefined) => string
  formatDate: (iso: string) => string
}

export const I18nContext = createContext<I18nContextValue | null>(null)

export function useI18n(): I18nContextValue {
  const value = useContext(I18nContext)
  if (!value) throw new Error('useI18n tiene que usarse dentro de I18nProvider')
  return value
}
