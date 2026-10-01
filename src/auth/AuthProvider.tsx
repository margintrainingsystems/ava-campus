import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { useI18n } from '../i18n/context'
import { readStoredLocale } from '../i18n/I18nProvider'
import { isLocale } from '../i18n/locale'
import { loadMe } from '../lib/queries'
import { clearStoredSession, supabase } from '../lib/supabase'
import { AuthContext, type AuthState } from './context'

export function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthState>({ status: 'loading' })
  const currentUser = useRef<string | null>(null)
  const { setLocale } = useI18n()

  const signOut = useCallback(async () => {
    currentUser.current = null
    try {
      await supabase.auth.signOut({ scope: 'local' })
    } finally {
      clearStoredSession()
      setState({ status: 'signed_out' })
    }
  }, [])

  const resolveSession = useCallback(
    async (session: Session | null, force = false) => {
      if (!session) {
        currentUser.current = null
        setState((prev) => (prev.status === 'signed_out' ? prev : { status: 'signed_out' }))
        return
      }
      if (!force && currentUser.current === session.user.id) {
        setState((prev) => (prev.status === 'ready' ? { ...prev, session } : prev))
        return
      }
      currentUser.current = session.user.id
      // En un navegador nuevo, el Campus se abre en el idioma guardado en la cuenta
      // (el de la invitación o el último que eligió la persona).
      const accountLocale = session.user.user_metadata?.locale
      if (!readStoredLocale() && isLocale(accountLocale)) setLocale(accountLocale)
      try {
        const me = await loadMe()
        setState({ status: 'ready', session, me })
      } catch {
        currentUser.current = null
        setState({ status: 'error', session })
      }
    },
    [setLocale],
  )

  useEffect(() => {
    let active = true
    supabase.auth.getSession().then(({ data }) => {
      if (active) void resolveSession(data.session)
    })
    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      // Supabase recomienda no llamar a la base dentro de este callback: lo diferimos.
      setTimeout(() => {
        if (active) void resolveSession(session)
      }, 0)
    })
    return () => {
      active = false
      listener.subscription.unsubscribe()
    }
  }, [resolveSession])

  const refresh = useCallback(async () => {
    const { data } = await supabase.auth.getSession()
    await resolveSession(data.session, true)
  }, [resolveSession])

  const value = useMemo(() => ({ state, signOut, refresh }), [state, signOut, refresh])
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
