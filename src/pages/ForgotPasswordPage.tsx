import { useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { AuthShell } from '../components/StatusScreens'
import { useI18n } from '../i18n/context'
import type { MessageKey } from '../i18n/types'
import { errorKey } from '../lib/errors'
import { supabase } from '../lib/supabase'
import { isValidEmail, normalizeEmail } from '../lib/validation'

export function ForgotPasswordPage() {
  const { t } = useI18n()
  const [email, setEmail] = useState('')
  const [error, setError] = useState<MessageKey | null>(null)
  const [sent, setSent] = useState(false)
  const [busy, setBusy] = useState(false)

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    if (!isValidEmail(email)) {
      setError('validation.email')
      return
    }
    setBusy(true)
    const { error: resetError } = await supabase.auth.resetPasswordForEmail(normalizeEmail(email), {
      redirectTo: `${window.location.origin}/definir-contrasena`,
    })
    setBusy(false)
    // Mostramos el mismo mensaje exista o no la cuenta, para no revelar quién está registrado.
    if (resetError && resetError.status === 429) {
      setError(errorKey(resetError))
      return
    }
    setSent(true)
  }

  return (
    <AuthShell>
      <h1 className="h-lg">{t('auth.forgot.title')}</h1>
      {sent ? (
        <>
          <p className="form-note" role="status">
            {t('auth.forgot.sent')}
          </p>
          <Link to="/ingresar" className="btn btn-outline">
            {t('auth.forgot.backToLogin')}
          </Link>
        </>
      ) : (
        <form className="stack-sm" onSubmit={handleSubmit} noValidate>
          <p className="text-muted">{t('auth.forgot.intro')}</p>
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
          {error && (
            <p className="form-note form-note-error" role="alert">
              {t(error)}
            </p>
          )}
          <div className="form-actions">
            <button type="submit" className="btn btn-solid" disabled={busy} aria-busy={busy}>
              {busy ? t('auth.forgot.busy') : t('auth.forgot.submit')}
            </button>
            <Link to="/ingresar" className="btn btn-ghost">
              {t('app.back')}
            </Link>
          </div>
        </form>
      )}
    </AuthShell>
  )
}
