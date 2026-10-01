import { en } from './en'
import { es } from './es'
import { detectLocale, localeFromLanguages, pickText, translate } from './locale'
import { pt } from './pt'

describe('textos de la interfaz', () => {
  it('inglés y portugués tienen las mismas claves que el español', () => {
    const base = Object.keys(es).sort()
    expect(Object.keys(en).sort()).toEqual(base)
    expect(Object.keys(pt).sort()).toEqual(base)
  })

  it('ningún texto queda vacío', () => {
    for (const messages of [es, en, pt]) {
      for (const [key, value] of Object.entries(messages)) expect(value.trim(), key).not.toBe('')
    }
  })

  it('las traducciones usan los mismos marcadores que el español', () => {
    const markers = (s: string) => (s.match(/\{\w+\}/g) ?? []).sort()
    for (const key of Object.keys(es) as (keyof typeof es)[]) {
      expect(markers(en[key]), key).toEqual(markers(es[key]))
      expect(markers(pt[key]), key).toEqual(markers(es[key]))
    }
  })

  it('reemplaza los marcadores y deja los que no recibe', () => {
    expect(translate('es', 'home.progress', { done: 2, total: 5 })).toBe('2 de 5 clases terminadas')
    expect(translate('pt', 'home.hello', { name: 'Ana' })).toBe('Olá, Ana')
    expect(translate('en', 'home.hello')).toBe('Hi, {name}')
  })
})

describe('detectLocale', () => {
  it('prioriza lo elegido en el navegador, después la cuenta y después el idioma del navegador', () => {
    expect(detectLocale('pt', 'en', ['es-AR'])).toBe('pt')
    expect(detectLocale(null, 'en', ['pt-BR'])).toBe('en')
    expect(detectLocale(null, undefined, ['fr-FR', 'pt-BR'])).toBe('pt')
    expect(detectLocale('xx', 'yy', ['fr'])).toBe('es')
  })

  it('reconoce variantes regionales', () => {
    expect(localeFromLanguages(['EN-us'])).toBe('en')
    expect(localeFromLanguages([])).toBeNull()
  })
})

describe('pickText', () => {
  it('usa el idioma pedido y, si falta o está vacío, el español', () => {
    const value = { es: 'Hola', en: 'Hello', pt: '  ' }
    expect(pickText(value, 'en')).toBe('Hello')
    expect(pickText(value, 'pt')).toBe('Hola')
    expect(pickText({ es: 'Solo español' }, 'en')).toBe('Solo español')
    expect(pickText(null, 'es')).toBe('')
  })
})
