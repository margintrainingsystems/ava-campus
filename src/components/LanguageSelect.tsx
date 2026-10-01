import { useId } from 'react'
import { useI18n } from '../i18n/context'
import { isLocale, LOCALE_NAMES } from '../i18n/locale'
import { LOCALES, type Locale } from '../i18n/types'
import { supabase } from '../lib/supabase'

// Selector de idioma. Con sesión, también lo guarda en la cuenta para otros dispositivos.
export function LanguageSelect({ signedIn = false, compact = false }: { signedIn?: boolean; compact?: boolean }) {
  const { locale, setLocale, t } = useI18n()
  const id = useId()

  function handleChange(value: string) {
    if (!isLocale(value)) return
    const next: Locale = value
    setLocale(next)
    // Si falla, el idioma igual queda elegido en este navegador.
    if (signedIn) void supabase.auth.updateUser({ data: { locale: next } })
  }

  return (
    <div className={compact ? 'lang-select lang-select-compact' : 'field lang-select'}>
      <label htmlFor={id} className={compact ? 'visually-hidden' : undefined}>
        {t('app.language')}
      </label>
      <select id={id} value={locale} onChange={(e) => handleChange(e.target.value)}>
        {LOCALES.map((l) => (
          <option key={l} value={l} lang={l}>
            {LOCALE_NAMES[l]}
          </option>
        ))}
      </select>
    </div>
  )
}
