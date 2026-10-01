import { createContext, useContext } from 'react'
import type { Session } from '@supabase/supabase-js'
import type { Me } from '../lib/catalog'

export type AuthState =
  | { status: 'loading' }
  | { status: 'signed_out' }
  | { status: 'error'; session: Session }
  | { status: 'ready'; session: Session; me: Me }

export type AuthContextValue = {
  state: AuthState
  signOut: () => Promise<void>
  refresh: () => Promise<void>
}

export const AuthContext = createContext<AuthContextValue | null>(null)

export function useAuth(): AuthContextValue {
  const value = useContext(AuthContext)
  if (!value) throw new Error('useAuth tiene que usarse dentro de AuthProvider')
  return value
}

// Para las pantallas internas, que solo se muestran con la sesión lista.
export function useStudent(): { me: Me; session: Session } {
  const { state } = useAuth()
  if (state.status !== 'ready') throw new Error('useStudent necesita una sesión activa')
  return { me: state.me, session: state.session }
}
