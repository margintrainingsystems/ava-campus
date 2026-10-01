import { useCallback, useEffect, useRef, useState } from 'react'

type AsyncState<T> = { data: T | null; error: unknown; loading: boolean }

// Carga datos al montar la pantalla y cada vez que cambia `key` (por ejemplo, el curso de la
// dirección), y permite recargarlos. Ignora respuestas viejas si se pidió otra carga antes.
export function useAsync<T>(load: () => Promise<T>, key = ''): AsyncState<T> & { reload: () => Promise<void> } {
  const [state, setState] = useState<AsyncState<T>>({ data: null, error: null, loading: true })
  const request = useRef(0)
  const loadRef = useRef(load)

  useEffect(() => {
    loadRef.current = load
  }, [load])

  const reload = useCallback(async () => {
    const id = ++request.current
    setState((s) => ({ ...s, loading: true, error: null }))
    try {
      const data = await loadRef.current()
      if (id === request.current) setState({ data, error: null, loading: false })
    } catch (error) {
      if (id === request.current) setState((s) => ({ ...s, error, loading: false }))
    }
  }, [])

  useEffect(() => {
    void reload()
  }, [reload, key])

  return { ...state, reload }
}
