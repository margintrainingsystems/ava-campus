import { useId, useState, type FormEvent } from 'react'
import { useI18n } from '../i18n/context'
import type { MessageKey } from '../i18n/types'
import { errorKey } from '../lib/errors'
import { supabase } from '../lib/supabase'
import { PASSWORD_MIN_LENGTH, passwordProblem } from '../lib/validation'

// Formulario de contraseña nueva: lo usan "Creá tu contraseña" y "Mi cuenta".
export function PasswordForm({ submitLabel, onSaved }: { submitLabel: string; onSaved: () => void }) {
  const { t } = useI18n()
  const id = useId()
  const [password, setPassword] = useState('')
  const [confirmation, setConfirmation] = useState('')
  const [error, setError] = useState<MessageKey | null>(null)
  const [busy, setBusy] = useState(false)

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    const problem = passwordProblem(password, confirmation)
    setError(problem)
    if (problem) return
    setBusy(true)
    const { error: updateError } = await supabase.auth.updateUser({ password })
    setBusy(false)
    if (updateError) {
      setError(errorKey(updateError))
      return
    }
    setPassword('')
    setConfirmation('')
    onSaved()
  }

  return (
    <form className="stack-sm" onSubmit={handleSubmit} noValidate>
      <div className="field">
        <label htmlFor={`${id}-new`}>{t('auth.set.new')}</label>
        <input
          id={`${id}-new`}
          type="password"
          autoComplete="new-password"
          aria-describedby={`${id}-help`}
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
        />
        <p id={`${id}-help`} className="field-help">
          {t('auth.set.help', { min: PASSWORD_MIN_LENGTH })}
        </p>
      </div>
      <div className="field">
        <label htmlFor={`${id}-repeat`}>{t('auth.set.repeat')}</label>
        <input
          id={`${id}-repeat`}
          type="password"
          autoComplete="new-password"
          value={confirmation}
          onChange={(e) => setConfirmation(e.target.value)}
          required
        />
      </div>
      {error && (
        <p className="form-note form-note-error" role="alert">
          {t(error, { min: PASSWORD_MIN_LENGTH })}
        </p>
      )}
      <div className="form-actions">
        <button type="submit" className="btn btn-solid" disabled={busy} aria-busy={busy}>
          {busy ? t('auth.set.busy') : submitLabel}
        </button>
      </div>
    </form>
  )
}
