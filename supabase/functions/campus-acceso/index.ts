// Edge Function campus-acceso: invita al Campus a la persona de una suscripción.
// La llama el CRM después de registrar un alta. El permiso lo revisa la base
// (campus_invite_target exige "Gestionar suscripciones"); esta función solo crea la cuenta
// y manda el email, porque eso necesita la service_role, que nunca sale de Supabase.
//
// El acceso a los cursos no depende de la invitación: lo da la suscripción. Invitar solo
// crea la cuenta para que la persona pueda entrar.

import { createClient, type SupabaseClient } from '@supabase/supabase-js'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const CAMPUS_URL = (Deno.env.get('CAMPUS_URL') ?? 'https://ava-campus.netlify.app').replace(/\/+$/, '')
const ALLOWED_ORIGINS = (
  Deno.env.get('CAMPUS_ALLOWED_ORIGINS') ??
    'https://ava-crm.netlify.app,https://ava-nucleo.netlify.app,http://localhost:5173'
)
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean)

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const LOCALES = new Set(['es', 'en', 'pt'])

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
    headers: { ...corsHeaders(origin), 'Content-Type': 'application/json; charset=utf-8' },
  })
}

function fail(origin: string | null, status: number, error: string, mensaje: string): Response {
  return reply(origin, status, { error, mensaje })
}

async function audit(
  admin: SupabaseClient,
  actor: { id: string; email: string | null },
  action: string,
  subscriptionId: string,
  detail: Json,
): Promise<void> {
  const { error } = await admin.from('crm_audit_log').insert({
    actor_id: actor.id,
    actor_email: actor.email,
    action,
    entity: 'crm_subscriptions',
    entity_id: subscriptionId,
    detail,
  })
  if (error) console.error('No se pudo registrar en la auditoría', error.message)
}

function inviteError(origin: string | null, status: number | undefined): Response {
  const limit = status === 429
  return fail(
    origin,
    limit ? 429 : 502,
    limit ? 'limite' : 'invitacion',
    limit
      ? 'Se enviaron muchos emails seguidos. Esperá unos minutos y probá de nuevo.'
      : 'No pudimos enviar la invitación al Campus. Revisá que el email de Supabase esté configurado.',
  )
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

  let body: Json
  try {
    body = (await req.json()) as Json
  } catch {
    return fail(origin, 400, 'formato', 'La solicitud no tiene el formato esperado.')
  }
  if (body.action !== 'invitar') return fail(origin, 400, 'accion', 'Acción desconocida.')

  const subscriptionId = String(body.subscription_id ?? '')
  if (!UUID_RE.test(subscriptionId)) return fail(origin, 400, 'formato', 'Falta la suscripción.')
  const locale = LOCALES.has(String(body.locale)) ? String(body.locale) : 'es'

  // 1. Permiso y datos de la persona, con la sesión de quien llama: decide la base.
  const asCaller = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  })
  const { data: userData, error: userError } = await asCaller.auth.getUser(token)
  if (userError || !userData.user) return fail(origin, 401, 'sin_sesion', 'Tu sesión venció. Volvé a entrar.')
  const actor = { id: userData.user.id, email: userData.user.email ?? null }

  const { data: targets, error: targetError } = await asCaller.rpc('campus_invite_target', {
    p_subscription: subscriptionId,
  })
  if (targetError) {
    if (targetError.code === '42501') {
      return fail(origin, 403, 'sin_permiso', 'Necesitás el permiso "Gestionar suscripciones" para invitar al Campus.')
    }
    return fail(origin, 500, 'base', 'No pudimos leer la suscripción. Probá de nuevo.')
  }
  const target = (targets as { email: string | null; first_name: string | null; status: string }[] | null)?.[0]
  if (!target) return fail(origin, 404, 'no_existe', 'No encontramos esa suscripción.')
  if (!target.email) return fail(origin, 409, 'sin_email', 'La persona de esta suscripción no tiene email.')
  if (target.status !== 'activa' && target.status !== 'cancelada') {
    return fail(origin, 409, 'sin_acceso', 'Esta suscripción no da acceso al Campus.')
  }

  // 2. Cuenta: si ya existe y está activa, no hace falta invitar.
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: found, error: findError } = await admin.rpc('crm_admin_find_user', { p_email: target.email })
  if (findError) return fail(origin, 500, 'base', 'No pudimos buscar la cuenta. Probá de nuevo.')
  const existing = (
    found as { id: string; email_confirmed_at: string | null; last_sign_in_at: string | null }[] | null
  )?.[0]

  if (existing && (existing.email_confirmed_at || existing.last_sign_in_at)) {
    await audit(admin, actor, 'campus_cuenta_existente', subscriptionId, {})
    return reply(origin, 200, { estado: 'ya_tiene_cuenta' })
  }

  const { error } = await admin.auth.admin.inviteUserByEmail(target.email, {
    redirectTo: `${CAMPUS_URL}/definir-contrasena`,
    data: { locale, ...(target.first_name ? { first_name: target.first_name } : {}) },
  })
  if (error) return inviteError(origin, error.status)

  await audit(admin, actor, existing ? 'campus_reenviar_invitacion' : 'campus_invitar', subscriptionId, { locale })
  return reply(origin, 200, { estado: 'invitada' })
})
