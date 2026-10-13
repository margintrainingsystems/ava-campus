-- Campus de AVA: accesos manuales (sin cobro) y contraseña inicial con cambio obligatorio.
--
-- Va después de dos migraciones que se aplican antes, en este orden:
--   1. CRM 20261012212823: crea public.crm_campus_grants (accesos que se dan a mano desde el CRM,
--      con el permiso "Dar acceso al Campus sin cobro") y el permiso campus.accesos.
--   2. Campus 20261012213153: materiales en Storage y borradores de cursos.
-- Esta migración no crea ni modifica tablas del CRM: solo lee crm_campus_grants, crm_people,
-- crm_subscriptions, crm_members y admins. Del Campus redefine funciones de acceso
-- (current_subscriptions, has_course_access y campus_me) con las mismas firmas, así que las
-- políticas RLS siguen igual, y también la regla de los materiales en Storage (can_read_material,
-- que la Edge Function campus-material consulta por campus_material_file). has_lesson_access no
-- cambia: ya llama a has_course_access. Además reemplaza campus_invite_target (fase 1), para que no
-- entregue emails sin "Ver email y teléfono". Las cuatro se reemplazan enteras, así que antes de
-- tocarlas se comprueba que siguen como las dejó la fase 1: si la migración 20261012213153 (o
-- cualquier otra) las hubiera cambiado, esta frena en vez de pisar ese cambio sin aviso.
--
-- Emails: ninguna función que se pueda llamar desde el navegador entrega el email de una persona a
-- quien no tiene "Ver email y teléfono" (personas.ver_contacto), igual que las pantallas del CRM. La
-- Edge Function campus-acceso, que sí lo necesita para crear la cuenta o invitar, lo lee con
-- campus_admin_person_email (solo service_role) después de que la base aprobó el permiso con la
-- sesión de quien pide.
--
-- Accesos manuales:
--   - Un acceso manual vigente da lo mismo que una suscripción del mismo tipo: kind = 'plan' abre
--     todos los cursos publicados (también los de regalo) y kind = 'master', los de ese Máster.
--   - Vigente = no quitado, ya empezó y no terminó (ends_at null = permanente). Sale de las fechas:
--     al vencer o al quitarlo, la persona deja de recibir clases en la consulta siguiente, sin tareas
--     programadas. La cuenta y el progreso quedan.
--   - Si tiene a la vez una suscripción paga y un acceso manual, los accesos se suman.
--
-- Contraseña inicial: sin dominio ni SMTP, la Edge Function campus-acceso crea la cuenta con una
-- contraseña que genera ella y la marca como inicial. Se guarda solo la huella (sha256) del hash de
-- esa contraseña, nunca la contraseña ni el hash. Cuando el alumno la cambia, por cualquier camino,
-- el hash cambia y la huella deja de coincidir sola. Mientras coincida, la base no entrega clases,
-- materiales ni progreso nuevo (has_course_access), y campus_me avisa must_change_password.

-- La tabla del CRM y la migración del Campus 20261012213153 tienen que estar antes: si no, el error
-- dice qué falta. Sin este chequeo, si la 20261012213153 fallara, esta se podría aplicar igual y la
-- base quedaría sin borradores ni materiales en Storage sin que nadie lo note.
do $$
begin
  if to_regclass('public.crm_campus_grants') is null
     or not exists (select 1 from public.crm_permissions where key = 'campus.accesos') then
    raise exception 'Falta la migración del CRM 20261012212823 (crm_campus_grants y el permiso campus.accesos): aplicala antes que esta';
  end if;
  if to_regclass('public.campus_course_drafts') is null
     or to_regprocedure('public.campus_material_file(text)') is null then
    raise exception 'Falta la migración del Campus 20261012213153 (borradores y materiales en Storage): aplicala antes que esta';
  end if;
end;
$$;

-- Las funciones que se reemplazan enteras tienen que ser todavía las de la fase 1 (20261001005016).
-- Se compara el texto de cada una sin espacios ni saltos de línea. Si alguna no coincide, otra
-- migración la cambió y ese cambio se perdería: hay que sumarlo acá antes de aplicar esta.
-- has_lesson_access no se reemplaza, pero tiene que seguir pasando por has_course_access: si no,
-- los accesos manuales y el bloqueo de la contraseña inicial no llegarían a las clases ni a los materiales.
do $$
declare
  v_changed text;
begin
  select string_agg(f.sig, ', ') into v_changed
  from (values
    ('campus_private.current_subscriptions()', '6939d66cfa7af32e01cb70aef07b49ec'),
    ('campus_private.has_course_access(uuid)', 'b12a4efd01ad886c120abaf32a79d675'),
    ('public.campus_me()', '140403799edf81960c2dc85e0e857799'),
    ('public.campus_invite_target(uuid)', '0f8cea9af17fefffa21b56d6eb00f12b')
  ) as f (sig, fase1)
  left join pg_catalog.pg_proc p on p.oid = to_regprocedure(f.sig)
  where md5(regexp_replace(coalesce(p.prosrc, ''), '\s', '', 'g')) <> f.fase1;
  if v_changed is not null then
    raise exception 'Estas funciones ya no son las de la fase 1 del Campus: %. Sumá ese cambio a esta migración antes de aplicarla', v_changed;
  end if;
  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = to_regprocedure('campus_private.has_lesson_access(uuid)')
      and p.prosrc like '%campus_private.has_course_access(%'
  ) then
    raise exception 'campus_private.has_lesson_access ya no pasa por has_course_access: revisá esta migración antes de aplicarla';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Contraseña inicial pendiente de cambio
-- ---------------------------------------------------------------------------

-- Una fila por cuenta con contraseña inicial. Solo la huella del hash: con ella no se puede
-- recuperar la contraseña. Se borra sola con la cuenta.
create table campus_private.initial_passwords (
  user_id uuid primary key references auth.users (id) on delete cascade,
  fingerprint text not null check (fingerprint ~ '^[0-9a-f]{64}$'),
  set_at timestamptz not null default now(),
  set_by_email text check (char_length(coalesce(set_by_email, '')) <= 320)
);

-- Nadie la lee ni la escribe desde la API: solo las funciones de abajo.
alter table campus_private.initial_passwords enable row level security;
revoke all on campus_private.initial_passwords from public, anon, authenticated, service_role;

-- Huella de un hash de contraseña de auth.users.
create function campus_private.password_fingerprint(p_hash text)
returns text
language sql immutable set search_path = ''
as $$
  select encode(extensions.digest(coalesce(p_hash, ''), 'sha256'), 'hex');
$$;

-- Si una cuenta todavía tiene la contraseña inicial. Recibe cualquier cuenta, por eso no se le da
-- a nadie y corre con los permisos de quien la llama (security invoker): solo funciona dentro de
-- las funciones de abajo, que deciden de quién se puede preguntar. Aunque algún día se le diera
-- permiso a authenticated, no podría leer las huellas.
create function campus_private.initial_password_pending(p_user uuid)
returns boolean
language sql stable set search_path = ''
as $$
  select exists (
    select 1
    from campus_private.initial_passwords k
    join auth.users u on u.id = k.user_id
    where k.user_id = p_user
      and k.fingerprint = campus_private.password_fingerprint(u.encrypted_password::text)
  );
$$;

-- La cuenta que llama tiene que cambiar la contraseña inicial antes de ver clases.
create function campus_private.must_change_password()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select auth.uid() is not null and campus_private.initial_password_pending(auth.uid());
$$;

revoke all on function campus_private.password_fingerprint(text),
  campus_private.initial_password_pending(uuid), campus_private.must_change_password()
  from public, anon, authenticated;
grant execute on function campus_private.must_change_password() to authenticated;

-- Solo la Edge Function campus-acceso (service_role): marca la contraseña actual de la cuenta como
-- inicial, después de crearla o de generar una contraseña nueva. Si ya había una marca, la reemplaza.
create function public.campus_admin_mark_initial_password(p_user uuid, p_by text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_hash text;
begin
  select u.encrypted_password into v_hash from auth.users u where u.id = p_user;
  if not found then
    raise exception 'La cuenta no existe' using errcode = 'P0002';
  end if;
  if coalesce(v_hash, '') = '' then
    raise exception 'La cuenta todavía no tiene contraseña' using errcode = '22023';
  end if;
  insert into campus_private.initial_passwords (user_id, fingerprint, set_by_email)
  values (p_user, campus_private.password_fingerprint(v_hash), nullif(btrim(coalesce(p_by, '')), ''))
  on conflict (user_id) do update set
    fingerprint = excluded.fingerprint,
    set_at = now(),
    set_by_email = excluded.set_by_email;
end;
$$;

-- Solo la Edge Function campus-acceso (service_role): borra la marca de contraseña inicial, por
-- ejemplo si la cuenta resultó ser de alguien que ya la usaba o si falló un paso posterior.
-- Devuelve si había una marca.
create function public.campus_admin_clear_initial_password(p_user uuid)
returns boolean
language plpgsql security definer set search_path = ''
as $$
begin
  delete from campus_private.initial_passwords k where k.user_id = p_user;
  return found;
end;
$$;

-- Solo la Edge Function campus-acceso (service_role): el email de una persona del CRM, para buscar o
-- crear su cuenta o mandarle la invitación. La llama después de que campus_account_target o
-- campus_invite_target, con la sesión de quien pide, aprobaron el permiso: esas dos devuelven el email
-- solo a quien tiene "Ver email y teléfono", y esta lo entrega a la función sin pasar por el navegador.
-- La Edge Function no se lo devuelve a quien pide si campus_account_target o campus_invite_target se
-- lo dieron en null. Null si la persona no existe o no tiene email.
create function public.campus_admin_person_email(p_person uuid)
returns text
language sql stable security definer set search_path = ''
as $$
  select p.email_normalized from public.crm_people p where p.id = p_person;
$$;

revoke all on function public.campus_admin_mark_initial_password(uuid, text),
  public.campus_admin_clear_initial_password(uuid), public.campus_admin_person_email(uuid)
  from public, anon, authenticated;
grant execute on function public.campus_admin_mark_initial_password(uuid, text),
  public.campus_admin_clear_initial_password(uuid), public.campus_admin_person_email(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Acceso: suscripciones pagas + accesos manuales
-- ---------------------------------------------------------------------------

-- Lo que hoy da acceso a la cuenta que llama. Los accesos manuales llegan con status 'manual' y
-- period_end = ends_at (null = permanente).
create or replace function campus_private.current_subscriptions()
returns table (kind text, master_id uuid, period_end timestamptz, status text)
language sql stable security definer set search_path = ''
as $$
  select s.kind, s.master_id, s.current_period_end, s.status
  from public.crm_subscriptions s
  join public.crm_people p on p.id = s.person_id
  where p.email_normalized = campus_private.current_email()
    and (s.status = 'activa' or (s.status = 'cancelada' and now() < s.current_period_end))
  union all
  select g.kind, g.master_id, g.ends_at, 'manual'
  from public.crm_campus_grants g
  join public.crm_people p on p.id = g.person_id
  where p.email_normalized = campus_private.current_email()
    and g.revoked_at is null
    and g.starts_at <= now()
    and (g.ends_at is null or g.ends_at > now());
$$;

-- Igual que antes, más el bloqueo: sin cambiar la contraseña inicial no hay clases. Las cuentas
-- de Núcleo siguen viendo todo.
create or replace function campus_private.has_course_access(p_course uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select campus_private.is_staff() or (
    not campus_private.must_change_password()
    and exists (
      select 1
      from public.campus_courses c
      join campus_private.current_subscriptions() s
        on s.kind = 'plan' or (s.kind = 'master' and s.master_id = c.master_id)
      where c.id = p_course and c.published
    )
  );
$$;

revoke all on function campus_private.current_subscriptions(), campus_private.has_course_access(uuid)
  from public, anon;
grant execute on function campus_private.current_subscriptions(), campus_private.has_course_access(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Funciones para el Campus
-- ---------------------------------------------------------------------------

-- Quién entra y qué incluye su acceso. Solo devuelve datos de la propia cuenta.
-- Suma must_change_password y accesses, una entrada por acceso: {kind, master_id, until, last_day, manual}.
--   until:    el instante en que termina (ends_at del acceso manual o current_period_end de la
--             suscripción; null = permanente). Es el fin exclusivo, el que compara la base: un acceso
--             de 30 días dado el 07/10 termina el 07/11 a las 00:00 de Buenos Aires (2026-11-07T03:00Z),
--             o sea que puede entrar hasta el 06/11 a las 23:59.
--   last_day: el último día con acceso, en fecha de Buenos Aires (en el ejemplo, 2026-11-06). Es el
--             mismo criterio que muestra el CRM ("hasta el 06/11/2026 a las 23:59"). Null = permanente.
--             Para mostrar el vencimiento, el Campus usa last_day (o until menos 1 ms, formateado con
--             timeZone America/Argentina/Buenos_Aires), nunca until en la zona del navegador.
-- access_until sigue, para la pantalla "Mi cuenta" ya publicada, que muestra una sola fecha formateada
-- en la zona del navegador:
--   - Es el último instante con acceso (until menos 1 microsegundo): en Argentina y Brasil esa pantalla
--     muestra el último día con acceso y no el día siguiente. En otras zonas muestra el día local en
--     que termina, que también es cierto para quien lo lee.
--   - Describe lo que esa pantalla anuncia: con la suscripción anual (paga o manual) muestra solo "la
--     anual", así que la fecha es la de la anual; sin anual, la de los Másteres. Null si alguno de esos
--     accesos es permanente (nunca anuncia un fin que no existe) o si no hay ninguno. Ejemplo: anual
--     paga hasta 2027 + Máster permanente → la fecha de la anual; anual manual permanente + Máster
--     pago → null. Para un detalle por acceso, el Campus lee accesses.
create or replace function public.campus_me()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  with s as (select * from campus_private.current_subscriptions()),
  -- Lo que "Mi cuenta" resume en una sola fecha: la anual si la hay; si no, los Másteres.
  shown as (
    select * from s
    where s.kind = 'plan' or not exists (select 1 from s s2 where s2.kind = 'plan')
  )
  select jsonb_build_object(
    'first_name', (
      select p.first_name from public.crm_people p
      where p.email_normalized = campus_private.current_email()
    ),
    'is_staff', campus_private.is_staff(),
    'must_change_password', campus_private.must_change_password(),
    'plan', exists (select 1 from s where s.kind = 'plan'),
    'master_ids', coalesce(
      (select jsonb_agg(distinct s.master_id) from s where s.kind = 'master'),
      '[]'::jsonb
    ),
    'access_until', case
      when exists (select 1 from shown where shown.period_end is null) then null
      else (select max(shown.period_end) from shown) - interval '1 microsecond'
    end,
    'accesses', coalesce(
      (select jsonb_agg(
         jsonb_build_object('kind', s.kind, 'master_id', s.master_id, 'until', s.period_end,
           'last_day', ((s.period_end - interval '1 microsecond') at time zone 'America/Argentina/Buenos_Aires')::date,
           'manual', s.status = 'manual')
         order by s.kind desc, s.period_end desc nulls first)
       from s),
      '[]'::jsonb
    )
  )
  where auth.uid() is not null;
$$;

revoke all on function public.campus_me() from public, anon;
grant execute on function public.campus_me() to authenticated;

-- ---------------------------------------------------------------------------
-- Funciones para el CRM y la Edge Function campus-acceso (con la sesión de quien usa el CRM)
-- ---------------------------------------------------------------------------

-- Si un email es de alguien del equipo del CRM (aunque esté desactivado) o de una cuenta de Núcleo.
-- Recibe el email ya normalizado (crm_people.email_normalized). Con esas cuentas el CRM no ve el
-- estado de la cuenta y la Edge Function no cambia contraseñas ni las elimina. No se le da a nadie y
-- corre con los permisos de quien la llama: solo funciona dentro de las funciones de abajo.
create function campus_private.is_team_email(p_email text)
returns boolean
language sql stable set search_path = ''
as $$
  select p_email is not null and (
    exists (select 1 from public.crm_members m where lower(btrim(m.email)) = p_email)
    or exists (
      select 1 from auth.users u
      where lower(btrim(u.email)) = p_email
        and (
          exists (select 1 from public.crm_members m where m.user_id = u.id)
          or exists (select 1 from public.admins a where a.user_id = u.id)
        )
    )
  );
$$;

revoke all on function campus_private.is_team_email(text) from public, anon, authenticated;

-- Datos de la persona para crear su cuenta, darle una contraseña nueva o eliminar su cuenta.
-- Pide "Dar acceso al Campus sin cobro" o "Gestionar suscripciones", y solo devuelve personas del
-- Campus:
--   - con "Gestionar suscripciones": personas con una suscripción paga que hoy da acceso;
--   - con "Dar acceso al Campus sin cobro": además, personas que tienen o tuvieron un acceso manual
--     o una suscripción, en cualquier estado (por ejemplo, para eliminar la cuenta de alguien cuyo
--     acceso ya venció).
--   email:            solo con "Ver email y teléfono"; si no, null. Esta función se puede llamar desde
--                     el navegador, así que no entrega lo que el CRM oculta en sus pantallas
--                     (crm_campus_access_list). La Edge Function lee el email con
--                     campus_admin_person_email (service_role) después de que esta función aprobó el
--                     permiso, y no se lo devuelve a quien pide si acá llegó null.
--   has_access:       tiene un acceso manual vigente o una suscripción paga que da acceso.
--   has_paid:         tiene una suscripción paga que da acceso (activa, o dada de baja sin terminar).
--   is_team:          el email es de alguien del equipo del CRM (aunque esté desactivado) o de Núcleo.
--                     Con esas cuentas la Edge Function no cambia contraseñas ni las elimina.
--   can_set_password: quien pide tiene "Dar acceso al Campus sin cobro", el permiso sensible que incluye
--                     generar contraseñas iniciales y eliminar cuentas. Sin él, la Edge Function rechaza
--                     crear una cuenta con contraseña inicial, "Contraseña nueva" y "Eliminar cuenta":
--                     con solo "Gestionar suscripciones" queda invitar por email (campus_invite_target).
--                     Así un permiso común no sirve para quedarse con la cuenta de un alumno que ya la usa.
-- Si la persona no existe, no devuelve filas.
create function public.campus_account_target(p_person uuid)
returns table (email text, first_name text, has_access boolean, has_paid boolean, is_team boolean,
  can_set_password boolean)
language plpgsql security definer set search_path = ''
as $$
declare
  v_email text;
  v_first_name text;
  v_paid boolean;
  v_granted boolean;
  v_accesos boolean;
begin
  perform crm_private.crm_require(
    crm_private.crm_is_member() and (
      crm_private.crm_has_permission('campus.accesos') or crm_private.crm_has_permission('suscripciones.gestionar')
    )
  );
  v_accesos := crm_private.crm_has_permission('campus.accesos');

  select p.email_normalized, p.first_name into v_email, v_first_name
  from public.crm_people p where p.id = p_person;
  if not found then
    return;
  end if;

  v_paid := exists (
    select 1 from public.crm_subscriptions s
    where s.person_id = p_person
      and (s.status = 'activa' or (s.status = 'cancelada' and now() < s.current_period_end))
  );
  perform crm_private.crm_require(
    v_paid or (
      v_accesos and (
        exists (select 1 from public.crm_campus_grants g where g.person_id = p_person)
        or exists (select 1 from public.crm_subscriptions s where s.person_id = p_person)
      )
    )
  );

  v_granted := exists (
    select 1 from public.crm_campus_grants g
    where g.person_id = p_person
      and g.revoked_at is null
      and g.starts_at <= now()
      and (g.ends_at is null or g.ends_at > now())
  );

  return query select
    case when crm_private.crm_has_permission('personas.ver_contacto') then v_email end,
    v_first_name,
    v_paid or v_granted,
    v_paid,
    campus_private.is_team_email(v_email),
    v_accesos;
end;
$$;

-- Estado de la cuenta del Campus de varias personas, para las listas del CRM: si tiene cuenta, si
-- la activó, cuándo entró por última vez y si todavía tiene la contraseña inicial. Sin emails.
-- Pide "Dar acceso al Campus sin cobro" o "Ver suscripciones" y, con el mismo criterio que
-- campus_account_target, solo responde por personas del Campus. Los demás ids se ignoran, igual que
-- los que no existen:
--   - con "Dar acceso al Campus sin cobro": personas que tienen o tuvieron un acceso manual o una
--     suscripción, en cualquier estado;
--   - con solo "Ver suscripciones": personas con una suscripción paga que hoy da acceso.
-- is_team: el email es del equipo del CRM (aunque esté desactivado) o de Núcleo. De esas cuentas solo
-- dice si existen: confirmed, last_sign_in_at y must_change_password llegan en null.
create function public.campus_accounts_status(p_person_ids uuid[])
returns table (person_id uuid, has_account boolean, confirmed boolean, last_sign_in_at timestamptz,
  must_change_password boolean, is_team boolean)
language plpgsql security definer set search_path = ''
as $$
declare
  v_accesos boolean;
begin
  perform crm_private.crm_require(
    crm_private.crm_is_member() and (
      crm_private.crm_has_permission('campus.accesos') or crm_private.crm_has_permission('suscripciones.ver')
    )
  );
  if cardinality(coalesce(p_person_ids, '{}')) > 2000 then
    raise exception 'Demasiadas personas en un solo pedido' using errcode = '22023';
  end if;
  v_accesos := crm_private.crm_has_permission('campus.accesos');

  return query
    select p.id,
           a.id is not null,
           case when t.team then null else a.email_confirmed_at is not null end,
           case when t.team then null else a.last_sign_in_at end,
           case when t.team then null else a.id is not null and campus_private.initial_password_pending(a.id) end,
           t.team
    from public.crm_people p
    cross join lateral (select campus_private.is_team_email(p.email_normalized) as team) t
    left join lateral (
      select u.id, u.email_confirmed_at, u.last_sign_in_at
      from auth.users u
      where p.email_normalized is not null and lower(btrim(u.email)) = p.email_normalized
      order by u.created_at
      limit 1
    ) a on true
    where p.id = any (coalesce(p_person_ids, '{}'))
      and (
        exists (
          select 1 from public.crm_subscriptions s
          where s.person_id = p.id
            and (s.status = 'activa' or (s.status = 'cancelada' and now() < s.current_period_end))
        )
        or (v_accesos and (
          exists (select 1 from public.crm_campus_grants g where g.person_id = p.id)
          or exists (select 1 from public.crm_subscriptions s where s.person_id = p.id)
        ))
      );
end;
$$;

-- Para la Edge Function campus-acceso (acción invitar): datos de la persona de una suscripción, solo
-- si quien llama es del equipo del CRM con "Gestionar suscripciones". Reemplaza la de la fase 1, que
-- devolvía el email a cualquiera con ese permiso: se puede llamar desde el navegador y "Gestionar
-- suscripciones" no muestra emails en ningún otro lado. Ahora:
--   email:     solo con "Ver email y teléfono"; si no, null.
--   person_id: nuevo. La Edge Function lee el email con campus_admin_person_email (service_role) para
--              mandar la invitación sin mostrárselo a quien la pide.
-- Las columnas de antes siguen en el mismo orden. Como cambia lo que devuelve, se borra y se vuelve a
-- crear. Hasta que se publique la Edge Function nueva, la que está publicada responde "no tiene email"
-- a quien tenga "Gestionar suscripciones" sin "Ver email y teléfono" (hoy el CRM lo usa solo la
-- propietaria, que tiene todos los permisos).
drop function public.campus_invite_target(uuid);
create function public.campus_invite_target(p_subscription uuid)
returns table (email text, first_name text, subscription_code text, status text, person_id uuid)
language plpgsql security definer set search_path = ''
as $$
begin
  perform crm_private.crm_require(
    crm_private.crm_is_member() and crm_private.crm_has_permission('suscripciones.gestionar')
  );
  return query
    select case when crm_private.crm_has_permission('personas.ver_contacto') then p.email_normalized end,
           p.first_name, s.code, s.status, p.id
    from public.crm_subscriptions s
    join public.crm_people p on p.id = s.person_id
    where s.id = p_subscription;
end;
$$;

revoke all on function public.campus_account_target(uuid), public.campus_accounts_status(uuid[]),
  public.campus_invite_target(uuid) from public, anon;
grant execute on function public.campus_account_target(uuid), public.campus_accounts_status(uuid[]),
  public.campus_invite_target(uuid) to authenticated;
