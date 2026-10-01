import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../auth/context'
import { PasswordForm } from '../components/PasswordForm'
import { AuthShell, LoadingScreen } from '../components/StatusScreens'
import { useToast } from '../components/Toast'
import { useI18n } from '../i18n/context'
import type { MessageKey } from '../i18n/types'

// Error que Supabase deja en la URL cuando el link de la invitación o de recuperación venció.
export function linkErrorFromHash(hash: string): MessageKey | null {
  const params = new URLSearchParams(hash.replace(/^#/, ''))
  if (!params.get('error') && !params.get('error_code')) return null
  if (params.get('error_code') === 'otp_expired') return 'auth.link.expired'
  return 'auth.link.invalid'
}

export function SetPasswordPage() {
  const { state } = useAuth()
  const { t } = useI18n()
  const navigate = useNavigate()
  const toast = useToast()
  const [linkError] = useState(() => linkErrorFromHash(window.location.hash))

  if (state.status === 'loading') return <LoadingScreen />

  if (state.status !== 'ready') {
    return (
      <AuthShell>
        <h1 className="h-lg">{t(linkError ?? 'auth.link.needNew')}</h1>
        <p className="text-muted">{t('auth.link.help')}</p>
        <div className="form-actions">
          <Link to="/recuperar" className="btn btn-solid">
            {t('auth.link.request')}
          </Link>
          <Link to="/ingresar" className="btn btn-ghost">
            {t('auth.link.goLogin')}
          </Link>
        </div>
      </AuthShell>
    )
  }

  return (
    <AuthShell>
      <div className="stack-sm">
        <h1 className="h-lg">{t('auth.set.title')}</h1>
        <p className="text-muted">{t('auth.set.account', { email: state.session.user.email ?? '' })}</p>
      </div>
      <PasswordForm
        submitLabel={t('auth.set.submit')}
        onSaved={() => {
          toast.show(t('auth.set.saved'))
          navigate('/', { replace: true })
        }}
      />
    </AuthShell>
  )
}
