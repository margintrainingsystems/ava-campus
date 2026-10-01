import { isYoutubeId, youtubeEmbedUrl } from './youtube'

describe('youtube', () => {
  it('acepta solo ids de 11 caracteres', () => {
    expect(isYoutubeId('dQw4w9WgXcQ')).toBe(true)
    expect(isYoutubeId('https://youtu.be/dQw4w9WgXcQ')).toBe(false)
    expect(isYoutubeId('corto')).toBe(false)
    expect(isYoutubeId(null)).toBe(false)
  })

  it('usa el dominio sin cookies y pide el idioma del Campus', () => {
    const es = new URL(youtubeEmbedUrl('dQw4w9WgXcQ', 'es'))
    expect(es.origin).toBe('https://www.youtube-nocookie.com')
    expect(es.pathname).toBe('/embed/dQw4w9WgXcQ')
    expect(es.searchParams.get('hl')).toBe('es')
    expect(es.searchParams.get('rel')).toBe('0')
    expect(es.searchParams.has('cc_load_policy')).toBe(false)

    const pt = new URL(youtubeEmbedUrl('dQw4w9WgXcQ', 'pt'))
    expect(pt.searchParams.get('cc_lang_pref')).toBe('pt')
    expect(pt.searchParams.get('cc_load_policy')).toBe('1')
  })
})
