// Edge Function campus-material: da el link para bajar un material (archivo) del Campus.
// La llama el Campus al tocar "Descargar". Quién puede bajar cada archivo lo decide la base:
// campus_material_file(ruta), con la sesión del alumno, aplica la misma regla que las clases.
// Si puede, esta función firma con la service_role un link que vence en 60 segundos.
//
// Por qué una función: los alumnos no tienen permiso de lectura sobre el bucket campus-materiales.
// Con ese permiso, Storage les firmaría links de la duración que pidieran (createSignedUrl acepta
// cualquier vencimiento), y un link firmado no se puede anular: seguiría andando después de vencer
// la suscripción o quitarse el acceso. Acá el vencimiento lo fija la función, no el navegador.
//
// Pedido: POST { "path": "<id de la clase>/<uuid>.<extensión>" } con la sesión del alumno.
// Respuesta: { "url": "<link firmado>", "expires_in": 60 }. El Campus navega a ese link
// (window.location.assign) y el archivo baja con su nombre original.
// Los errores traen un código (error) para que el Campus muestre su propio texto en el idioma de
// la persona; el mensaje en español es para el registro.
// Nunca dice si existe un archivo al que la persona no tiene acceso: un archivo de otro curso, uno
// que ya no es material de ninguna clase y uno que no existe responden igual (sin_acceso). Ninguna
// respuesta trae la ruta de otro archivo.

import { createClient } from '@supabase/supabase-js'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const CAMPUS_URL = (Deno.env.get('CAMPUS_URL') ?? 'https://ava-campus.netlify.app').replace(/\/+$/, '')
const ALLOWED_ORIGINS = (Deno.env.get('CAMPUS_MATERIAL_ORIGINS') ?? `${CAMPUS_URL},http://localhost:5174`)
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean)

const BUCKET = 'campus-materiales'
// Vida del link, en segundos. La fija esta función: quien llama no la puede cambiar.
const LINK_SECONDS = 60
// Mismo formato que campus_private.valid_material_path en la base: PDF, Word (.docx), Excel (.xlsx),
// PowerPoint (.pptx), CSV, PNG, JPG (.jpg o .jpeg, el mismo tipo image/jpeg) y texto.
const PATH_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|xlsx|csv|docx|pptx|png|jpg|jpeg|txt)$/

type Json = Record<string, unknown>

function corsHeaders(origin: string | null): HeadersInit {
  const allowed = origin && ALLOWED_ORIGINS.includes(origin) ? origin : (ALLOWED_ORIGINS[0] ?? '')
  return {
    'Access-Control-Allow-Origin': allowed,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    Vary: 'Origin',
  }
}

function reply(origin: string | null, status: number, body: Json): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(origin),
      'Content-Type': 'application/json; charset=utf-8',
      // El link firmado no tiene que quedar guardado en ningún caché.
      'Cache-Control': 'no-store',
    },
  })
}

function fail(origin: string | null, status: number, error: string, mensaje: string): Response {
  return reply(origin, status, { error, mensaje })
}

// Suma al link firmado el nombre con el que baja el archivo. No se usa la opción download de
// createSignedUrl porque supabase-js codifica el nombre dos veces (URLSearchParams y después encodeURI
// sobre el link entero): "Guía.pdf" bajaría como "Gu%C3%ADa.pdf". Acá se codifica una sola vez.
function withDownloadName(signedUrl: string, fileName: string): string {
  return `${signedUrl}${signedUrl.includes('?') ? '&' : '?'}download=${encodeURIComponent(fileName)}`
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin')

  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders(origin) })
  if (req.method !== 'POST') return fail(origin, 405, 'metodo', 'Método no permitido.')
  if (!SUPABASE_URL || !ANON_KEY || !SERVICE_ROLE_KEY) {
    return fail(origin, 500, 'configuracion', 'Falta configurar la función.')
  }

  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '')
  if (!token) return fail(origin, 401, 'sin_sesion', 'Tu sesión venció. Volvé a entrar.')

  let path: string
  try {
    const parsed: unknown = await req.json()
    const value = parsed && typeof parsed === 'object' ? (parsed as Json).path : undefined
    path = typeof value === 'string' ? value : ''
  } catch {
    return fail(origin, 400, 'formato', 'La solicitud no tiene el formato esperado.')
  }
  if (!PATH_RE.test(path)) return fail(origin, 400, 'formato', 'El archivo pedido no es válido.')

  try {
    // 1. Acceso, con la sesión de quien llama: decide la base (campus_material_file).
    const asCaller = createClient(SUPABASE_URL, ANON_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    })
    const { data: userData, error: userError } = await asCaller.auth.getUser(token)
    if (userError || !userData.user) return fail(origin, 401, 'sin_sesion', 'Tu sesión venció. Volvé a entrar.')

    const { data: fileName, error: accessError } = await asCaller.rpc('campus_material_file', { p_path: path })
    if (accessError) {
      console.error('No se pudo revisar el acceso al material', accessError.code, accessError.message)
      return fail(origin, 500, 'base', 'No pudimos revisar el acceso. Probá de nuevo.')
    }
    if (typeof fileName !== 'string' || !fileName) {
      return fail(origin, 403, 'sin_acceso', 'No tenés acceso a este material o ya no está disponible.')
    }

    // 2. Link de 60 segundos, firmado con la service_role (nunca sale de Supabase). Solo se llega acá
    //    con un archivo que la base ya aprobó para esta persona.
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: signed, error: signError } = await admin.storage.from(BUCKET).createSignedUrl(path, LINK_SECONDS)
    if (signError || !signed?.signedUrl) {
      console.error('No se pudo firmar el link', path, signError?.message)
      return fail(origin, 404, 'archivo', 'No encontramos el archivo. Avisale al equipo de AVA.')
    }

    return reply(origin, 200, { url: withDownloadName(signed.signedUrl, fileName), expires_in: LINK_SECONDS })
  } catch (e) {
    console.error('Error inesperado en campus-material', e instanceof Error ? e.message : String(e))
    return fail(origin, 500, 'base', 'Algo falló de nuestro lado. Probá de nuevo en unos minutos.')
  }
})
