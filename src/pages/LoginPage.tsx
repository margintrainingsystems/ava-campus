import { useState, type FormEvent } from 'react'
import { Link, Navigate, useLocation } from 'react-router-dom'
import { useAuth } from '../auth/context'
import { AuthShell, LoadingScreen } from '../components/StatusScreens'
import { useI18n } from '../i18n/context'
import type { MessageKey } from '../i18n/types'
import { errorKey } from '../lib/errors'
import { supabase } from '../lib/supabase'
import { isValidEmail, normalizeEmail } from '../lib/validation'

export function LoginPage() {
  const { state } = useAuth()
  const { t } = useI18n()
  const location = useLocation()
  const from = (location.state as { from?: string } | null)?.from ?? '/'
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError] = useState<MessageKey | null>(null)
  const [busy, setBusy] = useState(false)

  if (state.status === 'loading') return <LoadingScreen />
  if (state.status === 'ready') return <Navigate to={from} replace />

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    if (!isValidEmail(email)) {
      setError('validation.email')
      return
    }
    if (!password) {
      setError('validation.passwordMissing')
      return
    }
    setBusy(true)
    const { error: signInError } = await supabase.auth.signInWithPassword({ email: normalizeEmail(email), password })
    setBusy(false)
    if (signInError) setError(errorKey(signInError))
  }

  return (
    <AuthShell>
      <div className="stack-sm">
        <h1 className="h-lg">{t('auth.login.title')}</h1>
        <p className="text-muted">{t('auth.login.intro')}</p>
      </div>

      <form className="stack-sm" onSubmit={handleSubmit} noValidate>
        <div className="field">
          <label htmlFor="email">{t('auth.email')}</label>
          <input
            id="email"
            type="email"
            autoComplete="username"
            inputMode="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
          />
        </div>
        <div className="field">
          <label htmlFor="password">{t('auth.password')}</label>
          <div className="input-with-action">
            <input
              id="password"
              type={showPassword ? 'text' : 'password'}
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
            />
            <button
              type="button"
              className="input-action"
              aria-pressed={showPassword}
              onClick={() => setShowPassword((v) => !v)}
            >
              {showPassword ? t('auth.hide') : t('auth.show')}
            </button>
          </div>
        </div>

        {error && (
          <p className="form-note form-note-error" role="alert">
            {t(error)}
          </p>
        )}

        <div className="form-actions">
          <button type="submit" className="btn btn-solid" disabled={busy} aria-busy={busy}>
            {busy ? t('auth.login.busy') : t('auth.login.submit')}
          </button>
          <Link to="/recuperar" className="btn btn-ghost">
            {t('auth.login.forgot')}
          </Link>
        </div>
      </form>
      <p className="field-help">{t('auth.login.noAccount')}</p>
    </AuthShell>
  )
}
