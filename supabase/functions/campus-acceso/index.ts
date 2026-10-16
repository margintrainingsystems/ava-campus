// Edge Function campus-acceso: cuentas del Campus para las personas del CRM.
// La llama el CRM. Quién puede hacer cada cosa lo decide la base, con la sesión de quien llama
// (campus_invite_target y campus_account_target); esta función solo hace lo que necesita la
// service_role, que nunca sale de Supabase: leer el email de la persona, crear, cambiar o borrar la
// cuenta y marcar la contraseña inicial.
//
// Acciones (POST con la sesión de quien usa el CRM):
//   invitar           { subscription_id, locale? }  manda la invitación por email. Queda para cuando
//                                                   haya dominio y SMTP: hoy el email no le llega a
//                                                   ningún alumno.
//   crear_cuenta      { person_id, locale? }        crea la cuenta con una contraseña inicial y la
//                                                   devuelve una sola vez.
//   nueva_contrasena  { person_id }                 genera otra contraseña inicial para una cuenta que
//                                                   ya existe (por ejemplo, si se olvidó la suya).
//   eliminar_cuenta   { person_id, nota? }          quita los accesos manuales y borra la cuenta. La
//                                                   ficha del CRM queda.
// Respuestas: { estado, ... } si salió bien; { error, mensaje } si no. El código (error) es para que
// el CRM decida qué hacer; el mensaje, en español, ya dice qué pasó y cómo seguir.
//
// El acceso a los cursos no depende de la cuenta: lo dan la suscripción paga o el acceso manual.
// La contraseña inicial viaja una sola vez, en la respuesta (Cache-Control: no-store), y nunca se
// guarda: ni en la base, ni en la auditoría, ni en el registro de la función. Mientras el alumno no
// la cambie, la base no le entrega clases (campus_private.must_change_password).
//
// Emails: la función lee el email con campus_admin_person_email (solo service_role) y únicamente
// después de que la base aprobó el permiso con la sesión de quien pide. Si la base se lo ocultó a
// quien pide (sin "Ver email y teléfono"), la respuesta tampoco lo trae.

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
const LOCALES: ReadonlySet<string> = new Set(['es', 'en', 'pt'])
// Mismo tope que la nota de crm_campus_grants_revoke_all.
const NOTE_MAX = 300
const DELETE_NOTE = 'Se eliminó su cuenta del Campus'

// Contraseña inicial: 12 caracteres con mayúsculas, minúsculas y números, sin los que se confunden
// al dictarla o copiarla a mano (0, O, o, 1, l, I). Cumple la regla del Campus (10 o más, con letras
// y números). Son unos 69 bits al azar.
const PASSWORD_LENGTH = 12
const PASSWORD_UPPER = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
const PASSWORD_LOWER = 'abcdefghijkmnpqrstuvwxyz'
const PASSWORD_DIGITS = '23456789'
const PASSWORD_ALPHABET = PASSWORD_UPPER + PASSWORD_LOWER + PASSWORD_DIGITS

type Json = Record<string, unknown>
type Locale = 'es' | 'en' | 'pt'
type Actor = { id: string; email: string | null }
type Ctx = { origin: string | null; asCaller: SupabaseClient; admin: SupabaseClient; actor: Actor }
type Account = { id: string; email_confirmed_at: string | null; last_sign_in_at: string | null }
type InviteTarget = {
  email: string | null
  first_name: string | null
  subscription_code: string | null
  status: string
  person_id: string | null
}
type AccountTarget = {
  email: string | null
  first_name: string | null
  has_access: boolean
  has_paid: boolean
  is_team: boolean
  can_set_password: boolean
}
type AuthErrorLike = { status?: number; code?: unknown; message?: string } | null | undefined

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
      // Las respuestas pueden traer una contraseña inicial: que no quede guardada en ningún caché.
      'Cache-Control': 'no-store',
    },
  })
}

function fail(origin: string | null, status: number, error: string, mensaje: string, extra: Json = {}): Response {
  return reply(origin, status, { ...extra, error, mensaje })
}

// Constancia en la auditoría del CRM (la muestra Núcleo). Se escribe con la service_role, como en las
// otras Edge Functions: crm_private.crm_audit toma el autor de auth.uid(), que acá no existe. Nunca
// lleva la contraseña ni el email.
async function audit(
  admin: SupabaseClient,
  actor: Actor,
  action: string,
  entity: 'crm_subscriptions' | 'crm_people',
  entityId: string,
  detail: Json,
): Promise<void> {
  const { error } = await admin.from('crm_audit_log').insert({
    actor_id: actor.id,
    actor_email: actor.email,
    action,
    entity,
    entity_id: entityId,
    detail,
  })
  if (error) console.error('No se pudo registrar en la auditoría', error.message)
}

function readLocale(value: unknown): Locale {
  return typeof value === 'string' && LOCALES.has(value) ? (value as Locale) : 'es'
}

function readPersonId(body: Json): string | null {
  return typeof body.person_id === 'string' && UUID_RE.test(body.person_id) ? body.person_id : null
}

function authCode(error: AuthErrorLike): string {
  return typeof error?.code === 'string' ? error.code : ''
}

// Generador criptográfico. Solo se usan los bytes menores al mayor múltiplo del tamaño del alfabeto,
// así cada carácter sale con la misma probabilidad. Si al resultado le falta una mayúscula, una
// minúscula o un número, se genera otro.
function generatePassword(): string {
  const size = PASSWORD_ALPHABET.length
  const limit = 256 - (256 % size)
  for (;;) {
    let password = ''
    while (password.length < PASSWORD_LENGTH) {
      for (const byte of crypto.getRandomValues(new Uint8Array(32))) {
        if (byte < limit && password.length < PASSWORD_LENGTH) password += PASSWORD_ALPHABET[byte % size]
      }
    }
    if (/[A-Z]/.test(password) && /[a-z]/.test(password) && /[0-9]/.test(password)) return password
  }
}

// El email de una persona del CRM, con la service_role. Solo se llama después de que la base aprobó
// el permiso con la sesión de quien pide.
async function personEmail(
  admin: SupabaseClient,
  personId: string,
): Promise<{ ok: true; email: string | null } | { ok: false }> {
  const { data, error } = await admin.rpc('campus_admin_person_email', { p_person: personId })
  if (error) {
    console.error('No se pudo leer el email de la persona', error.message)
    return { ok: false }
  }
  return { ok: true, email: typeof data === 'string' && data ? data : null }
}

async function findAccount(
  admin: SupabaseClient,
  email: string,
): Promise<{ ok: true; account: Account | null } | { ok: false }> {
  const { data, error } = await admin.rpc('crm_admin_find_user', { p_email: email })
  if (error) {
    console.error('No se pudo buscar la cuenta', error.message)
    return { ok: false }
  }
  return { ok: true, account: (data as Account[] | null)?.[0] ?? null }
}

// Una cuenta ya se usó si confirmó el email o entró alguna vez. Las que crea esta función nacen
// confirmadas, así que también cuentan como usadas.
function accountInUse(account: Account): boolean {
  return Boolean(account.email_confirmed_at || account.last_sign_in_at)
}

async function markInitialPassword(admin: SupabaseClient, userId: string, actor: Actor): Promise<boolean> {
  const { error } = await admin.rpc('campus_admin_mark_initial_password', { p_user: userId, p_by: actor.email })
  if (error) console.error('No se pudo marcar la contraseña inicial', error.message)
  return !error
}

function authFailure(origin: string | null, error: AuthErrorLike, mensaje: string): Response {
  console.error('Supabase Auth rechazó el pedido', error?.status, authCode(error), error?.message)
  if (authCode(error) === 'weak_password') {
    return fail(
      origin,
      500,
      'regla_contrasena',
      'Supabase no aceptó la contraseña generada. Revisá la regla de contraseñas en el panel de Supabase (Authentication): tiene que aceptar 12 caracteres con mayúsculas, minúsculas y números.',
    )
  }
  return fail(origin, 502, 'cuenta', mensaje)
}

// ---------------------------------------------------------------------------
// invitar
// ---------------------------------------------------------------------------

async function invitar(ctx: Ctx, body: Json): Promise<Response> {
  const { origin, asCaller, admin, actor } = ctx
  const subscriptionId = String(body.subscription_id ?? '')
  if (!UUID_RE.test(subscriptionId)) return fail(origin, 400, 'formato', 'Falta la suscripción.')
  const locale = readLocale(body.locale)

  // 1. Permiso y datos de la suscripción, con la sesión de quien llama: decide la base. El email
  //    llega vacío sin "Ver email y teléfono"; de acá solo sale el id de la persona.
  const { data: targets, error: targetError } = await asCaller.rpc('campus_invite_target', {
    p_subscription: subscriptionId,
  })
  if (targetError) {
    if (targetError.code === '42501') {
      return fail(origin, 403, 'sin_permiso', 'Necesitás el permiso "Gestionar suscripciones" para invitar al Campus.')
    }
    return fail(origin, 500, 'base', 'No pudimos leer la suscripción. Probá de nuevo.')
  }
  const target = (targets as InviteTarget[] | null)?.[0]
  if (!target) return fail(origin, 404, 'no_existe', 'No encontramos esa suscripción.')
  if (target.status !== 'activa' && target.status !== 'cancelada') {
    return fail(origin, 409, 'sin_acceso', 'Esta suscripción no da acceso al Campus.')
  }
  if (!target.person_id) return fail(origin, 500, 'base', 'No pudimos leer la suscripción. Probá de nuevo.')

  // 2. Email, con la service_role: la base ya aprobó el permiso. No vuelve a quien llama.
  const read = await personEmail(admin, target.person_id)
  if (!read.ok) return fail(origin, 500, 'base', 'No pudimos leer la suscripción. Probá de nuevo.')
  if (!read.email) return fail(origin, 409, 'sin_email', 'La persona de esta suscripción no tiene email.')

  // 3. Cuenta: si ya existe y está activa, no hace falta invitar.
  const found = await findAccount(admin, read.email)
  if (!found.ok) return fail(origin, 500, 'base', 'No pudimos buscar la cuenta. Probá de nuevo.')
  const existing = found.account

  if (existing && accountInUse(existing)) {
    await audit(admin, actor, 'campus_cuenta_existente', 'crm_subscriptions', subscriptionId, {})
    return reply(origin, 200, { estado: 'ya_tiene_cuenta' })
  }

  const { error } = await admin.auth.admin.inviteUserByEmail(read.email, {
    redirectTo: `${CAMPUS_URL}/definir-contrasena`,
    data: { locale, ...(target.first_name ? { first_name: target.first_name } : {}) },
  })
  if (error) {
    const limit = error.status === 429
    return fail(
      origin,
      limit ? 429 : 502,
      limit ? 'limite' : 'invitacion',
      limit
        ? 'Se enviaron muchos emails seguidos. Esperá unos minutos y probá de nuevo.'
        : 'No pudimos enviar la invitación al Campus. Revisá que el email de Supabase esté configurado.',
    )
  }

  await audit(
    admin,
    actor,
    existing ? 'campus_reenviar_invitacion' : 'campus_invitar',
    'crm_subscriptions',
    subscriptionId,
    { locale },
  )
  return reply(origin, 200, { estado: 'invitada' })
}

// ---------------------------------------------------------------------------
// Cuentas con contraseña inicial: crear_cuenta, nueva_contrasena y eliminar_cuenta
// ---------------------------------------------------------------------------

// Permiso y datos de la persona, con la sesión de quien llama: decide la base. Sin fila (la persona
// no existe) no se lee nada más. Las tres acciones piden "Dar acceso al Campus sin cobro"
// (can_set_password) y nunca tocan cuentas del equipo ni de Núcleo (is_team).
async function accountTarget(ctx: Ctx, personId: string): Promise<AccountTarget | Response> {
  const { origin, asCaller } = ctx
  const { data, error } = await asCaller.rpc('campus_account_target', { p_person: personId })
  if (error) {
    // 42501: le falta el permiso, o la persona nunca tuvo un acceso ni una suscripción.
    if (error.code === '42501') {
      return fail(
        origin,
        403,
        'sin_permiso',
        'No tenés permiso para manejar la cuenta del Campus de esta persona. Si todavía no tiene ningún acceso, dale uno primero.',
      )
    }
    return fail(origin, 500, 'base', 'No pudimos leer los datos de la persona. Probá de nuevo.')
  }
  const target = (data as AccountTarget[] | null)?.[0]
  if (!target) return fail(origin, 404, 'no_existe', 'No encontramos a esa persona en el CRM. Actualizá la página.')
  if (!target.can_set_password) {
    return fail(
      origin,
      403,
      'sin_permiso_contrasena',
      'Necesitás el permiso "Dar acceso al Campus sin cobro" para crear cuentas, generar contraseñas o eliminar cuentas. Pedíselo a la propietaria del CRM.',
    )
  }
  if (target.is_team) {
    return fail(
      origin,
      409,
      'cuenta_equipo',
      'Es una cuenta del equipo de AVA o de Núcleo: no se crea, no se cambia ni se elimina desde acá. Entra al Campus con su contraseña de siempre.',
    )
  }
  return target
}

// Email (service_role) y cuenta de la persona. Se llama solo después de accountTarget.
async function personAccount(ctx: Ctx, personId: string): Promise<{ email: string; account: Account | null } | Response> {
  const { origin, admin } = ctx
  const read = await personEmail(admin, personId)
  if (!read.ok) return fail(origin, 500, 'base', 'No pudimos leer los datos de la persona. Probá de nuevo.')
  if (!read.email) {
    return fail(
      origin,
      409,
      'sin_email',
      'La persona no tiene email en su ficha. Cargalo antes: es con lo que entra al Campus.',
    )
  }
  const found = await findAccount(admin, read.email)
  if (!found.ok) return fail(origin, 500, 'base', 'No pudimos buscar la cuenta. Probá de nuevo.')
  return { email: read.email, account: found.account }
}

async function crearCuenta(ctx: Ctx, body: Json): Promise<Response> {
  const { origin, admin, actor } = ctx
  const personId = readPersonId(body)
  if (!personId) return fail(origin, 400, 'formato', 'Falta la persona.')
  const locale = readLocale(body.locale)

  const target = await accountTarget(ctx, personId)
  if (target instanceof Response) return target
  if (!target.has_access) {
    return fail(origin, 409, 'sin_acceso', 'Primero dale un acceso al Campus: sin un acceso vigente no se crea la cuenta.')
  }
  const found = await personAccount(ctx, personId)
  if (found instanceof Response) return found
  const { email, account } = found

  // Ya se usó: no se toca. Puede ser una alumna anterior, que entra con su contraseña de siempre.
  // Si la perdió, se usa "Contraseña nueva".
  if (account && accountInUse(account)) {
    await audit(admin, actor, 'campus_cuenta_existente', 'crm_people', personId, {})
    return reply(origin, 200, { estado: 'ya_tiene_cuenta' })
  }

  const password = generatePassword()
  const metadata = { locale, ...(target.first_name ? { first_name: target.first_name } : {}) }
  let userId: string
  if (account) {
    // Existe pero nunca se activó (por ejemplo, una invitación vieja que no le llegó).
    const { error } = await admin.auth.admin.updateUserById(account.id, {
      password,
      email_confirm: true,
      user_metadata: metadata,
    })
    if (error) return authFailure(origin, error, 'No pudimos crear la cuenta. Probá de nuevo.')
    userId = account.id
  } else {
    // createUser no manda ningún email y funciona aunque el registro público esté apagado.
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: metadata,
    })
    if (error || !data.user) {
      if (authCode(error) === 'email_exists') {
        return fail(
          origin,
          409,
          'reintentar',
          'La cuenta se creó desde otro pedido al mismo tiempo. Actualizá la página y, si hace falta, generá una contraseña nueva.',
        )
      }
      return authFailure(origin, error, 'No pudimos crear la cuenta. Probá de nuevo.')
    }
    userId = data.user.id
  }

  // Sin la marca no habría cambio obligatorio en el primer ingreso. Si falla, la cuenta se borra
  // (nunca se usó, así que no se pierde nada) y la contraseña no se entrega.
  if (!(await markInitialPassword(admin, userId, actor))) {
    const { error } = await admin.auth.admin.deleteUser(userId)
    if (error) console.error('No se pudo borrar la cuenta sin marca de contraseña inicial', error.message)
    return fail(origin, 500, 'base', 'No pudimos terminar de crear la cuenta. Probá de nuevo.')
  }

  await audit(admin, actor, 'campus_crear_cuenta', 'crm_people', personId, {
    locale,
    cuenta: account ? 'sin_activar' : 'nueva',
  })
  return reply(origin, 200, {
    estado: 'creada',
    password,
    locale,
    campus_url: CAMPUS_URL,
    ...(target.email ? { email: target.email } : {}),
  })
}

async function nuevaContrasena(ctx: Ctx, body: Json): Promise<Response> {
  const { origin, admin, actor } = ctx
  const personId = readPersonId(body)
  if (!personId) return fail(origin, 400, 'formato', 'Falta la persona.')

  const target = await accountTarget(ctx, personId)
  if (target instanceof Response) return target
  const found = await personAccount(ctx, personId)
  if (found instanceof Response) return found
  const { account } = found
  if (!account) return fail(origin, 404, 'sin_cuenta', 'Todavía no tiene cuenta en el Campus: usá "Crear cuenta".')

  // También confirma el email: una cuenta que nunca se activó queda lista para entrar.
  const password = generatePassword()
  const { data, error } = await admin.auth.admin.updateUserById(account.id, { password, email_confirm: true })
  if (error) return authFailure(origin, error, 'No pudimos generar la contraseña nueva. Probá de nuevo.')

  // La contraseña ya cambió, pero sin la marca no se entrega: nadie la conoce y se puede pedir otra.
  if (!(await markInitialPassword(admin, account.id, actor))) {
    return fail(origin, 500, 'base', 'No pudimos generar la contraseña nueva. Probá de nuevo.')
  }

  await audit(admin, actor, 'campus_nueva_contrasena', 'crm_people', personId, {})
  return reply(origin, 200, {
    estado: 'contrasena_nueva',
    password,
    locale: readLocale((data.user?.user_metadata as Json | undefined)?.locale),
    campus_url: CAMPUS_URL,
    ...(target.email ? { email: target.email } : {}),
  })
}

async function eliminarCuenta(ctx: Ctx, body: Json): Promise<Response> {
  const { origin, asCaller, admin, actor } = ctx
  const personId = readPersonId(body)
  if (!personId) return fail(origin, 400, 'formato', 'Falta la persona.')
  if (body.nota !== undefined && body.nota !== null && typeof body.nota !== 'string') {
    return fail(origin, 400, 'formato', 'La nota no tiene el formato esperado.')
  }
  const note = typeof body.nota === 'string' ? body.nota.trim() : ''
  if (note.length > NOTE_MAX) return fail(origin, 400, 'nota', `La nota puede tener hasta ${NOTE_MAX} caracteres.`)

  const target = await accountTarget(ctx, personId)
  if (target instanceof Response) return target
  if (target.has_paid) {
    return fail(origin, 409, 'suscripcion_paga', 'Tiene una suscripción paga vigente: resolvela primero en Suscripciones.')
  }
  const found = await personAccount(ctx, personId)
  if (found instanceof Response) return found
  const { account } = found
  if (!account) return fail(origin, 404, 'sin_cuenta', 'No tiene cuenta en el Campus: no hay nada para eliminar.')

  // 1. Accesos manuales que siguen vigentes, con la sesión de quien pide: la base vuelve a revisar el
  //    permiso y deja una constancia por cada uno.
  const { data: revoked, error: revokeError } = await asCaller.rpc('crm_campus_grants_revoke_all', {
    p_person: personId,
    p_note: note || DELETE_NOTE,
  })
  if (revokeError) {
    if (revokeError.code === '42501') {
      return fail(origin, 403, 'sin_permiso', 'No tenés permiso para quitarle el acceso a esta persona. No se eliminó nada.')
    }
    if (revokeError.code === 'P0002') {
      return fail(origin, 404, 'no_existe', 'No encontramos a esa persona en el CRM. Actualizá la página.')
    }
    return fail(origin, 500, 'base', 'No pudimos quitarle el acceso. No se eliminó nada: probá de nuevo.')
  }
  const removedGrants = typeof revoked === 'number' ? revoked : 0

  // 2. La cuenta. Su progreso y la marca de contraseña inicial se borran solos con ella.
  const { error } = await admin.auth.admin.deleteUser(account.id)
  if (error) {
    console.error('No se pudo eliminar la cuenta', error.status, authCode(error), error.message)
    return fail(
      origin,
      502,
      'cuenta',
      removedGrants > 0
        ? 'Le quitamos el acceso, pero no pudimos eliminar la cuenta. Probá de nuevo.'
        : 'No pudimos eliminar la cuenta. Probá de nuevo.',
      { accesos_quitados: removedGrants },
    )
  }

  await audit(admin, actor, 'campus_eliminar_cuenta', 'crm_people', personId, { accesos_quitados: removedGrants })
  return reply(origin, 200, { estado: 'eliminada', accesos_quitados: removedGrants })
}

// Un Map y no un objeto: así "constructor" o "toString" no pasan por acciones.
const ACTIONS = new Map<string, (ctx: Ctx, body: Json) => Promise<Response>>([
  ['invitar', invitar],
  ['crear_cuenta', crearCuenta],
  ['nueva_contrasena', nuevaContrasena],
  ['eliminar_cuenta', eliminarCuenta],
])

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
    const parsed: unknown = await req.json()
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('no es un objeto')
    body = parsed as Json
  } catch {
    return fail(origin, 400, 'formato', 'La solicitud no tiene el formato esperado.')
  }
  const handler = typeof body.action === 'string' ? ACTIONS.get(body.action) : undefined
  if (!handler) return fail(origin, 400, 'accion', 'Acción desconocida.')

  // Quién llama: se verifica con su token, porque verify_jwt queda apagado (config.toml).
  const asCaller = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  })
  const { data: userData, error: userError } = await asCaller.auth.getUser(token)
  if (userError || !userData.user) return fail(origin, 401, 'sin_sesion', 'Tu sesión venció. Volvé a entrar.')

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const actor = { id: userData.user.id, email: userData.user.email ?? null }

  try {
    return await handler({ origin, asCaller, admin, actor }, body)
  } catch (e) {
    // Nunca se registra el cuerpo del pedido ni la respuesta: pueden traer una contraseña.
    console.error('Error inesperado en campus-acceso', e instanceof Error ? e.message : String(e))
    return fail(origin, 500, 'base', 'Algo falló de nuestro lado. Probá de nuevo en unos minutos.')
  }
})
