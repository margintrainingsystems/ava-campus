import { useEffect, useRef } from 'react'
import { Link, NavLink, Outlet, useLocation } from 'react-router-dom'
import { useAuth } from '../auth/context'
import { useI18n } from '../i18n/context'
import { Brand } from './Brand'
import { LanguageSelect } from './LanguageSelect'

export function AppLayout() {
  const { signOut } = useAuth()
  const { t } = useI18n()
  const location = useLocation()
  const main = useRef<HTMLElement>(null)
  const firstRender = useRef(true)

  // Al cambiar de pantalla, el foco va al título: así los lectores de pantalla anuncian dónde estás.
  useEffect(() => {
    if (firstRender.current) {
      firstRender.current = false
      return
    }
    const title = main.current?.querySelector<HTMLElement>('[data-page-title]')
    title?.focus()
  }, [location.pathname])

  return (
    <>
      <a className="skip-link" href="#contenido">
        {t('app.skip')}
      </a>
      <header className="topbar">
        <div className="topbar-inner">
          <Link to="/" className="topbar-brand">
            <Brand />
          </Link>
          <nav aria-label={t('nav.main')} className="topbar-nav">
            <NavLink to="/" end className="topbar-link">
              {t('nav.courses')}
            </NavLink>
            <NavLink to="/cuenta" className="topbar-link">
              {t('nav.account')}
            </NavLink>
          </nav>
          <div className="topbar-tools">
            <LanguageSelect signedIn compact />
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => void signOut()}>
              {t('app.signOut')}
            </button>
          </div>
        </div>
      </header>
      <main id="contenido" ref={main} className="page">
        <Outlet />
      </main>
    </>
  )
}
