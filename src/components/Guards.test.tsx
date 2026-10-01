import { screen } from '@testing-library/react'
import { Route, Routes } from 'react-router-dom'
import { readyState, renderApp } from '../test/render'
import { RequireStudent } from './Guards'

function routes() {
  return (
    <Routes>
      <Route path="/ingresar" element={<p>pantalla de ingreso</p>} />
      <Route
        path="/"
        element={
          <RequireStudent>
            <p>contenido del campus</p>
          </RequireStudent>
        }
      />
    </Routes>
  )
}

describe('RequireStudent', () => {
  it('sin sesión lleva a entrar', () => {
    renderApp(routes(), { status: 'signed_out' })
    expect(screen.getByText('pantalla de ingreso')).toBeInTheDocument()
  })

  it('sin suscripción activa muestra el aviso, en el idioma elegido', () => {
    renderApp(routes(), readyState(), { locale: 'pt' })
    expect(screen.getByRole('heading', { name: 'Sua assinatura não está ativa' })).toBeInTheDocument()
    expect(screen.queryByText('contenido del campus')).not.toBeInTheDocument()
  })

  it('con un Máster suelto deja entrar', () => {
    renderApp(routes(), readyState({ masterIds: ['m1'] }))
    expect(screen.getByText('contenido del campus')).toBeInTheDocument()
  })
})
