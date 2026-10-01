import { screen } from '@testing-library/react'
import { vi } from 'vitest'
import type { CourseSummary, MasterInfo } from '../lib/catalog'
import { readyState, renderApp } from '../test/render'
import { HomePage } from './HomePage'

const masters: MasterInfo[] = [
  {
    id: 'datos',
    name: 'Datos y Análisis',
    title: { es: 'Datos y Análisis', en: 'Data & Analytics' },
    summary: {},
    colorToken: 'accent-1',
    order: 1,
  },
  { id: 'ia', name: 'Inteligencia Artificial', title: { es: 'Inteligencia Artificial' }, summary: {}, colorToken: 'accent-2', order: 2 },
]

const courses: CourseSummary[] = [
  {
    id: 'c1',
    masterId: 'datos',
    slug: 'excel',
    title: { es: 'Excel desde cero', en: 'Excel from scratch' },
    summary: {},
    position: 1,
    published: true,
    lessonCount: 4,
    doneCount: 1,
  },
  {
    id: 'c2',
    masterId: 'ia',
    slug: 'prompting',
    title: { es: 'Prompting' },
    summary: {},
    position: 1,
    published: true,
    lessonCount: 3,
    doneCount: 0,
  },
]

vi.mock('../lib/queries', () => ({
  loadMasters: vi.fn(async () => masters),
  loadCourses: vi.fn(async () => courses),
}))

describe('HomePage', () => {
  it('agrupa por Máster, muestra el progreso y marca lo que no incluye el plan', async () => {
    renderApp(<HomePage />, readyState({ masterIds: ['datos'] }))
    expect(screen.getByRole('heading', { name: 'Hola, Ana' })).toBeInTheDocument()
    expect(await screen.findByRole('heading', { name: 'Datos y Análisis' })).toBeInTheDocument()
    expect(screen.getByText('Seguir con')).toBeInTheDocument()
    expect(screen.getAllByText('1 de 4 clases terminadas').length).toBeGreaterThan(0)
    const locked = screen.getByRole('link', { name: /Prompting/ })
    expect(locked).toHaveTextContent('No incluido en tu plan')
  })

  it('muestra los textos traducidos y usa el español cuando falta la traducción', async () => {
    renderApp(<HomePage />, readyState({ plan: true }), { locale: 'en' })
    expect(await screen.findByRole('heading', { name: 'Data & Analytics' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Inteligencia Artificial' })).toBeInTheDocument()
    expect(screen.getAllByText('Excel from scratch').length).toBeGreaterThan(0)
  })
})
