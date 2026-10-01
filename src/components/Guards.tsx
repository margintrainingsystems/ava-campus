import type { ReactNode } from 'react'
import { Navigate, useLocation } from 'react-router-dom'
import { useAuth } from '../auth/context'
import { useI18n } from '../i18n/context'
import { hasAnyAccess } from '../lib/catalog'
import { SITE_URL } from '../lib/config'
import { AuthShell, ConnectionErrorScreen, LoadingScreen } from './StatusScreens'

// Pantallas internas: exigen sesión y una suscripción que dé acceso (o una cuenta de Núcleo).
export function RequireStudent({ children }: { children: ReactNode }) {
  const { state } = useAuth()
  const location = useLocation()
  if (state.status === 'loading') return <LoadingScreen />
  if (state.status === 'error') return <ConnectionErrorScreen />
  if (state.status === 'signed_out') {
    return <Navigate to="/ingresar" replace state={{ from: location.pathname }} />
  }
  if (!hasAnyAccess(state.me)) return <NoAccessScreen />
  return <>{children}</>
}

export function NoAccessScreen() {
  const { signOut } = useAuth()
  const { t } = useI18n()
  return (
    <AuthShell>
      <h1 className="h-lg">{t('noAccess.title')}</h1>
      <p className="text-muted">{t('noAccess.body')}</p>
      <div className="form-actions">
        <a className="btn btn-solid" href={SITE_URL}>
          {t('noAccess.site')}
        </a>
        <button type="button" className="btn btn-outline" onClick={() => void signOut()}>
          {t('app.signOut')}
        </button>
      </div>
    </AuthShell>
  )
}
