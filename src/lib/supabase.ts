import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

if (!url || !key) {
  throw new Error('Faltan VITE_SUPABASE_URL o VITE_SUPABASE_PUBLISHABLE_KEY. Revisá el archivo .env.')
}

// Mismo proyecto que el sitio, Núcleo y el CRM. La seguridad depende de las políticas RLS.
export const supabase = createClient(url, key, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
})

// Borra del navegador las claves de sesión de Supabase (empiezan con "sb-"), igual que el CRM.
export function clearStoredSession(storage: Storage = window.localStorage): void {
  const keys: string[] = []
  for (let i = 0; i < storage.length; i++) {
    const k = storage.key(i)
    if (k?.startsWith('sb-')) keys.push(k)
  }
  keys.forEach((k) => storage.removeItem(k))
}
