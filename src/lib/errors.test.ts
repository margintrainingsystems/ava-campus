import { errorKey } from './errors'
import { passwordProblem } from './validation'

describe('errorKey', () => {
  it('traduce los códigos conocidos', () => {
    expect(errorKey({ code: 'invalid_credentials' })).toBe('error.credentials')
    expect(errorKey({ code: '42501' })).toBe('error.permission')
  })

  it('reconoce la falta de conexión y el límite de intentos', () => {
    expect(errorKey(new TypeError('Failed to fetch'))).toBe('error.network')
    expect(errorKey({ status: 429 })).toBe('error.rateLimit')
  })

  it('usa el mensaje general para lo demás', () => {
    expect(errorKey({ code: 'raro' })).toBe('error.generic')
    expect(errorKey(null, 'error.notFound')).toBe('error.notFound')
  })
})

describe('passwordProblem', () => {
  it('pide largo, letras y números, y que coincidan', () => {
    expect(passwordProblem('corta1', 'corta1')).toBe('validation.passwordShort')
    expect(passwordProblem('soloslasletras', 'soloslasletras')).toBe('validation.passwordMix')
    expect(passwordProblem('clave12345a', 'clave12345b')).toBe('validation.passwordMatch')
    expect(passwordProblem('clave12345a', 'clave12345a')).toBeNull()
  })
})
