import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import { I18nContext } from './context'
import { detectLocale, LOCALE_TAGS, pickText, STORAGE_KEY, translate } from './locale'
import type { Locale } from './types'

export function readStoredLocale(): string | null {
  try {
    return window.localStorage.getItem(STORAGE_KEY)
  } catch {
    return null
  }
}

function writeStored(locale: Locale): void {
  try {
    window.localStorage.setItem(STORAGE_KEY, locale)
  } catch {
    // Navegación privada o almacenamiento bloqueado: el idioma vale solo para esta visita.
  }
}

type Props = {
  children: ReactNode
  initialLocale?: Locale
}

export function I18nProvider({ children, initialLocale }: Props) {
  const [locale, setLocaleState] = useState<Locale>(
    () => initialLocale ?? detectLocale(readStoredLocale(), null, navigator.languages ?? [navigator.language]),
  )

  useEffect(() => {
    document.documentElement.lang = LOCALE_TAGS[locale]
  }, [locale])

  const setLocale = useCallback((next: Locale) => {
    writeStored(next)
    setLocaleState(next)
  }, [])

  const value = useMemo(() => {
    const dateFormat = new Intl.DateTimeFormat(LOCALE_TAGS[locale], { day: 'numeric', month: 'long', year: 'numeric' })
    return {
      locale,
      setLocale,
      t: (key: Parameters<typeof translate>[1], params?: Record<string, string | number>) =>
        translate(locale, key, params),
      text: (v: Parameters<typeof pickText>[0]) => pickText(v, locale),
      formatDate: (iso: string) => dateFormat.format(new Date(iso)),
    }
  }, [locale, setLocale])

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>
}
