import type { ReactElement } from 'react'
import { render } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import type { Session } from '@supabase/supabase-js'
import { AuthContext, type AuthState } from '../auth/context'
import { ToastProvider } from '../components/Toast'
import { I18nProvider } from '../i18n/I18nProvider'
import type { Locale } from '../i18n/types'
import type { Me } from '../lib/catalog'

export const fakeSession = { user: { id: 'u1', email: 'ana@example.com', user_metadata: {} }, access_token: 't' } as unknown as Session

export function readyState(me: Partial<Me> = {}): AuthState {
  return {
    status: 'ready',
    session: fakeSession,
    me: { firstName: 'Ana', isStaff: false, plan: false, masterIds: [], accessUntil: null, ...me },
  }
}

export function renderApp(ui: ReactElement, state: AuthState, { route = '/', locale = 'es' as Locale } = {}) {
  const value = { state, signOut: async () => undefined, refresh: async () => undefined }
  return render(
    <MemoryRouter initialEntries={[route]}>
      <I18nProvider initialLocale={locale}>
        <ToastProvider>
          <AuthContext.Provider value={value}>{ui}</AuthContext.Provider>
        </ToastProvider>
      </I18nProvider>
    </MemoryRouter>,
  )
}
