import type { ReactNode } from 'react'
import { useAuth } from '../auth/context'
import { useI18n } from '../i18n/context'
import { errorKey } from '../lib/errors'
import { Brand } from './Brand'
import { LanguageSelect } from './LanguageSelect'

export function LoadingScreen() {
  const { t } = useI18n()
  return (
    <div className="center-screen" role="status" aria-live="polite">
      <span className="spinner" aria-hidden="true" />
      <span>{t('app.loading')}</span>
    </div>
  )
}

export function Loading() {
  const { t } = useI18n()
  return (
    <p className="loading-inline" role="status">
      <span className="spinner spinner-sm" aria-hidden="true" />
      {t('app.loading')}
    </p>
  )
}

// Error al cargar una sección, con botón para reintentar.
export function LoadError({ error, onRetry, title }: { error: unknown; onRetry: () => void; title?: string }) {
  const { t } = useI18n()
  return (
    <div className="form-note form-note-error" role="alert">
      <span>
        {title ? `${title} ` : ''}
        {t(errorKey(error))}
      </span>
      <button type="button" className="btn btn-outline btn-sm" onClick={onRetry}>
        {t('app.retry')}
      </button>
    </div>
  )
}

// Marco de las pantallas sin sesión (entrar, recuperar, crear contraseña).
export function AuthShell({ children }: { children: ReactNode }) {
  return (
    <main className="auth-page">
      <div className="auth-card stack-md">
        <div className="auth-top">
          <Brand />
          <LanguageSelect compact />
        </div>
        {children}
      </div>
    </main>
  )
}

export function ConnectionErrorScreen() {
  const { refresh, signOut } = useAuth()
  const { t } = useI18n()
  return (
    <AuthShell>
      <h1 className="h-lg">{t('auth.loadError.title')}</h1>
      <p className="text-muted">{t('auth.loadError.body')}</p>
      <div className="form-actions">
        <button type="button" className="btn btn-solid" onClick={() => void refresh()}>
          {t('app.retry')}
        </button>
        <button type="button" className="btn btn-outline" onClick={() => void signOut()}>
          {t('app.signOut')}
        </button>
      </div>
    </AuthShell>
  )
}
