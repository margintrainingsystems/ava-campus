import type { Locale } from '../i18n/types'

const ID_RE = /^[A-Za-z0-9_-]{11}$/

export function isYoutubeId(value: string | null | undefined): value is string {
  return typeof value === 'string' && ID_RE.test(value)
}

// Link para incrustar un video oculto (no listado) desde el dominio sin cookies de YouTube.
// Pide la interfaz y los subtítulos en el idioma del Campus; fuera del español, los activa.
export function youtubeEmbedUrl(id: string, locale: Locale): string {
  const params = new URLSearchParams({
    rel: '0',
    modestbranding: '1',
    playsinline: '1',
    hl: locale,
    cc_lang_pref: locale,
  })
  if (locale !== 'es') params.set('cc_load_policy', '1')
  return `https://www.youtube-nocookie.com/embed/${encodeURIComponent(id)}?${params.toString()}`
}
