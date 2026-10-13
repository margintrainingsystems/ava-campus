-- Prueba de los accesos manuales al Campus y de la contraseña inicial.
-- Necesita aplicadas la migración del CRM 20261010120000 (crm_campus_grants y el permiso
-- campus.accesos) y las del Campus 20261010120100 y 20261010120200.
-- Correla en el SQL Editor de Supabase o con la herramienta execute_sql.
-- Crea cuentas, personas, equipo, accesos manuales, suscripciones, cursos y un material como archivo
-- (solo la fila: no sube nada a Storage), simula cada tipo de cuenta y termina con un error a
-- propósito: así Postgres revierte todo y la base queda igual que antes. Leé el mensaje del error:
-- cada chequeo dice "ok" o "MAL", y al final "FALLAS: n".

do $$
declare
  v_owner uuid := (select user_id from public.crm_members where is_owner);
  v_admin uuid := (select user_id from public.admins order by created_at limit 1);
  v_admin_email text;
  -- Alumnos
  v_tmp uuid := gen_random_uuid();      -- acceso manual anual por 30 días, ya cambió la contraseña
  v_perm uuid := gen_random_uuid();     -- acceso manual permanente a un Máster
  v_mix uuid := gen_random_uuid();      -- Máster pago + acceso manual permanente a otro Máster
  v_old uuid := gen_random_uuid();      -- acceso manual vencido, con progreso guardado
  v_edge uuid := gen_random_uuid();     -- acceso manual que termina justo ahora
  v_rev uuid := gen_random_uuid();      -- acceso manual quitado
  v_fut uuid := gen_random_uuid();      -- acceso manual que todavía no empezó
  v_ini uuid := gen_random_uuid();      -- acceso manual permanente, con la contraseña inicial sin cambiar
  v_none uuid := gen_random_uuid();     -- cuenta sin ningún acceso
  v_nopass uuid := gen_random_uuid();   -- cuenta sin contraseña
  v_combo uuid := gen_random_uuid();    -- anual paga con fecha + acceso manual permanente a un Máster
  v_combo2 uuid := gen_random_uuid();   -- anual manual permanente + Máster pago con fecha
  -- Equipo del CRM
  v_acc uuid := gen_random_uuid();      -- "Dar acceso al Campus sin cobro"
  v_ges uuid := gen_random_uuid();      -- "Gestionar suscripciones"
  v_ver uuid := gen_random_uuid();      -- "Ver suscripciones"
  v_otro uuid := gen_random_uuid();     -- sin permisos del Campus
  v_baja uuid := gen_random_uuid();     -- "Dar acceso al Campus sin cobro", pero desactivado
  v_acc2 uuid := gen_random_uuid();     -- "Dar acceso al Campus sin cobro" + "Ver email y teléfono"
  v_ges2 uuid := gen_random_uuid();     -- "Gestionar suscripciones" + "Ver email y teléfono"
  v_roles uuid[] := '{}';
  v_role uuid;
  -- Personas del CRM
  v_p_tmp uuid; v_p_perm uuid; v_p_mix uuid; v_p_old uuid; v_p_edge uuid; v_p_rev uuid;
  v_p_fut uuid; v_p_ini uuid; v_p_none uuid; v_p_sin_cuenta uuid; v_p_admin uuid; v_p_equipo uuid;
  v_p_equipo_baja uuid; v_p_ex_pago uuid; v_p_combo uuid; v_p_combo2 uuid;
  v_sub_mix uuid;                       -- suscripción paga del Máster de v_p_mix
  -- Fechas: el acceso de 30 días se calcula como lo guarda el CRM (crm_grant_end): termina a la
  -- medianoche de Buenos Aires al terminar el día hoy + 30, y ese es el último día con acceso.
  v_tmp_end timestamptz;
  v_tmp_last_day date;
  v_combo_end timestamptz := now() + interval '300 days';
  -- Contenido
  v_m1 uuid; v_m2 uuid;
  v_c1 uuid; v_c2 uuid; v_gift uuid; v_draft uuid;
  v_l1 uuid; v_l2 uuid; v_lg uuid; v_l1_draft uuid; v_ld uuid;
  v_path text;                          -- archivo (Storage) de un material de la clase v_l1
  v_rec record;
  v_ok boolean;
  v_ok2 boolean;
  v_n int;
  v_n2 int;
  v_j jsonb;
  r text := '';
  fallas int := 0;
  i int;
begin
  if to_regclass('public.crm_campus_grants') is null
     or not exists (select 1 from public.crm_permissions where key = 'campus.accesos')
     or to_regprocedure('campus_private.can_read_material(text)') is null
     or to_regprocedure('public.campus_accounts_status(uuid[])') is null
     or to_regprocedure('public.campus_admin_person_email(uuid)') is null then
    raise exception 'La prueba necesita aplicadas la migración del CRM 20261010120000 y las del Campus 20261010120100 y 20261010120200';
  end if;
  select id into v_m1 from public.masters order by order_index limit 1;
  select id into v_m2 from public.masters order by order_index offset 1 limit 1;
  select lower(btrim(email)) into v_admin_email from auth.users where id = v_admin;
  if v_owner is null or v_admin_email is null or v_m1 is null or v_m2 is null then
    raise exception 'La prueba necesita la propietaria del CRM, una cuenta en admins y al menos dos Másteres';
  end if;
  v_tmp_end := crm_private.crm_grant_end(crm_private.crm_today_ar(), 30);
  v_tmp_last_day := crm_private.crm_today_ar() + 30;
  perform set_config('request.jwt.claims', '', true);

  -- Cuentas. Las contraseñas son hashes de mentira: la base solo compara su huella.
  insert into auth.users (id, email, aud, role, encrypted_password, email_confirmed_at, last_sign_in_at) values
    (v_tmp, 'prueba-acc-temporal@example.com', 'authenticated', 'authenticated', 'hash-propio-temporal', now() - interval '2 days', now() - interval '1 day'),
    (v_perm, 'prueba-acc-permanente@example.com', 'authenticated', 'authenticated', 'hash-propio-permanente', now(), null),
    (v_mix, 'prueba-acc-mixto@example.com', 'authenticated', 'authenticated', 'hash-propio-mixto', now(), null),
    (v_old, 'prueba-acc-vencido@example.com', 'authenticated', 'authenticated', 'hash-propio-vencido', now(), null),
    (v_edge, 'prueba-acc-vence-ahora@example.com', 'authenticated', 'authenticated', 'hash-propio-vence', now(), null),
    (v_rev, 'prueba-acc-quitado@example.com', 'authenticated', 'authenticated', 'hash-propio-quitado', now(), null),
    (v_fut, 'prueba-acc-futuro@example.com', 'authenticated', 'authenticated', 'hash-propio-futuro', now(), null),
    (v_ini, 'prueba-acc-inicial@example.com', 'authenticated', 'authenticated', 'hash-inicial', now(), null),
    (v_none, 'prueba-acc-sin-acceso@example.com', 'authenticated', 'authenticated', 'hash-propio-sin-acceso', now(), null),
    (v_nopass, 'prueba-acc-sin-clave@example.com', 'authenticated', 'authenticated', null, null, null),
    (v_combo, 'prueba-acc-combo@example.com', 'authenticated', 'authenticated', 'hash-propio-combo', now(), null),
    (v_combo2, 'prueba-acc-combo2@example.com', 'authenticated', 'authenticated', 'hash-propio-combo2', now(), null),
    (v_acc, 'prueba-acc-equipo-accesos@example.com', 'authenticated', 'authenticated', 'hash-equipo-1', now(), null),
    (v_ges, 'prueba-acc-equipo-gestiona@example.com', 'authenticated', 'authenticated', 'hash-equipo-2', now(), now() - interval '1 day'),
    (v_ver, 'prueba-acc-equipo-ve@example.com', 'authenticated', 'authenticated', 'hash-equipo-3', now(), null),
    (v_otro, 'prueba-acc-equipo-otro@example.com', 'authenticated', 'authenticated', 'hash-equipo-4', now(), null),
    (v_baja, 'prueba-acc-equipo-baja@example.com', 'authenticated', 'authenticated', 'hash-equipo-5', now(), null),
    (v_acc2, 'prueba-acc-equipo-accesos-contacto@example.com', 'authenticated', 'authenticated', 'hash-equipo-6', now(), null),
    (v_ges2, 'prueba-acc-equipo-gestiona-contacto@example.com', 'authenticated', 'authenticated', 'hash-equipo-7', now(), null);

  -- Equipo del CRM, como lo da de alta la Edge Function crm-equipo.
  for i in 1..6 loop
    insert into public.crm_roles (name) values ('Prueba Campus ' || i) returning id into v_role;
    v_roles := array_append(v_roles, v_role);
  end loop;
  insert into public.crm_role_permissions values
    (v_roles[1], 'campus.accesos'),
    (v_roles[2], 'suscripciones.gestionar'),
    (v_roles[3], 'suscripciones.ver'),
    (v_roles[4], 'personas.ver'), (v_roles[4], 'personas.ver_contacto'),
    (v_roles[5], 'campus.accesos'), (v_roles[5], 'personas.ver_contacto'),
    (v_roles[6], 'suscripciones.gestionar'), (v_roles[6], 'personas.ver_contacto');
  insert into public.crm_members (user_id, email, role_id, active) values
    (v_acc, 'prueba-acc-equipo-accesos@example.com', v_roles[1], true),
    (v_ges, 'prueba-acc-equipo-gestiona@example.com', v_roles[2], true),
    (v_ver, 'prueba-acc-equipo-ve@example.com', v_roles[3], true),
    (v_otro, 'prueba-acc-equipo-otro@example.com', v_roles[4], true),
    (v_baja, 'prueba-acc-equipo-baja@example.com', v_roles[1], false),
    (v_acc2, 'prueba-acc-equipo-accesos-contacto@example.com', v_roles[5], true),
    (v_ges2, 'prueba-acc-equipo-gestiona-contacto@example.com', v_roles[6], true);

  -- Personas del CRM (sin escribir en leads, como el alta manual).
  v_p_tmp := crm_private.crm_upsert_person_from_lead('prueba-acc-temporal@example.com', 'Temporal', null, null, null, now());
  v_p_perm := crm_private.crm_upsert_person_from_lead('prueba-acc-permanente@example.com', 'Permanente', null, null, null, now());
  v_p_mix := crm_private.crm_upsert_person_from_lead('prueba-acc-mixto@example.com', 'Mixto', null, null, null, now());
  v_p_old := crm_private.crm_upsert_person_from_lead('prueba-acc-vencido@example.com', 'Vencido', null, null, null, now());
  v_p_edge := crm_private.crm_upsert_person_from_lead('prueba-acc-vence-ahora@example.com', 'Vence', null, null, null, now());
  v_p_rev := crm_private.crm_upsert_person_from_lead('prueba-acc-quitado@example.com', 'Quitado', null, null, null, now());
  v_p_fut := crm_private.crm_upsert_person_from_lead('prueba-acc-futuro@example.com', 'Futuro', null, null, null, now());
  v_p_ini := crm_private.crm_upsert_person_from_lead('prueba-acc-inicial@example.com', 'Inicial', null, null, null, now());
  v_p_none := crm_private.crm_upsert_person_from_lead('prueba-acc-sin-acceso@example.com', 'Sin acceso', null, null, null, now());
  v_p_sin_cuenta := crm_private.crm_upsert_person_from_lead('prueba-acc-sin-cuenta@example.com', 'Sin cuenta', null, null, null, now());
  v_p_admin := crm_private.crm_upsert_person_from_lead(v_admin_email, 'Aimar', null, null, null, now());
  v_p_equipo := crm_private.crm_upsert_person_from_lead('prueba-acc-equipo-gestiona@example.com', 'Equipo', null, null, null, now());
  v_p_equipo_baja := crm_private.crm_upsert_person_from_lead('prueba-acc-equipo-baja@example.com', 'Equipo baja', null, null, null, now());
  v_p_ex_pago := crm_private.crm_upsert_person_from_lead('prueba-acc-ex-pago@example.com', 'Ex pago', null, null, null, now());
  v_p_combo := crm_private.crm_upsert_person_from_lead('prueba-acc-combo@example.com', 'Combo', null, null, null, now());
  v_p_combo2 := crm_private.crm_upsert_person_from_lead('prueba-acc-combo2@example.com', 'Combo dos', null, null, null, now());

  -- Accesos manuales (como los guarda el CRM) y suscripciones pagas. Las fichas con el email de
  -- Núcleo y del equipo también tienen accesos (quitado, vencido y vigente): así se ve que la base
  -- las reconoce como del equipo aunque alguien les haya dado acceso. La ficha "Sin cuenta" tiene un
  -- acceso vigente pero todavía no tiene cuenta (por ejemplo, falló la Edge Function al crearla).
  insert into public.crm_campus_grants (code, person_id, kind, master_id, starts_at, ends_at, reason, adult_checked,
    revoked_at, revoked_by_email, revoke_note) values
    (crm_private.crm_new_code('ACC'), v_p_tmp, 'plan', null, now() - interval '1 day', v_tmp_end, 'Prueba', true, null, null, null),
    (crm_private.crm_new_code('ACC'), v_p_perm, 'master', v_m1, now() - interval '1 day', null, 'Cortesía', true, null, null, null),
    (crm_private.crm_new_code('ACC'), v_p_mix, 'master', v_m2, now() - interval '1 day', null, 'Beca', true, null, null, null),
    (crm_private.crm_new_code('ACC'), v_p_old, 'plan', null, now() - interval '40 days', now() - interval '10 days', 'Prueba', true, null, null, null),
    (crm_private.crm_new_code('ACC'), v_p_edge, 'plan', null, now() - interval '30 days', now(), 'Prueba', true, null, null, null),
    (crm_private.crm_new_code('ACC'), v_p_rev, 'plan', null, now() - interval '5 days', now() + interval '30 days', 'Prueba', true,
      now() - interval '1 hour', 'prueba@example.com', 'Quitado en la prueba'),
    (crm_private.crm_new_code('ACC'), v_p_fut, 'plan', null, now() + interval '2 days', now() + interval '30 days', 'Prueba', true, null, null, null),
    (crm_private.crm_new_code('ACC'), v_p_ini, 'plan', null, now() - interval '1 hour', null, 'Cortesía', true, null, null, null),
    (crm_private.crm_new_code('ACC'), v_p_admin, 'plan', null, now() - interval '5 days', null, 'Prueba', true,
      now() - interval '1 hour', 'prueba@example.com', null),
    (crm_private.crm_new_code('ACC'), v_p_equipo, 'master', v_m1, now() - interval '40 days', now() - interval '10 days', 'Prueba', true, null, null, null),
    (crm_private.crm_new_code('ACC'), v_p_equipo_baja, 'master', v_m2, now() - interval '1 day', null, 'Prueba', true, null, null, null),
    (crm_private.crm_new_code('ACC'), v_p_sin_cuenta, 'master', v_m1, now() - interval '1 hour', now() + interval '30 days', 'Prueba', true, null, null, null),
    (crm_private.crm_new_code('ACC'), v_p_combo, 'master', v_m1, now() - interval '1 day', null, 'Cortesía', true, null, null, null),
    (crm_private.crm_new_code('ACC'), v_p_combo2, 'plan', null, now() - interval '1 day', null, 'Cortesía', true, null, null, null);
  insert into public.crm_subscriptions (code, person_id, kind, master_id, status, provider, currency, started_at,
    current_period_start, current_period_end)
  values
    (crm_private.crm_new_code('SUS'), v_p_mix, 'master', v_m1, 'activa', 'manual', 'USD', now() - interval '10 days',
      now() - interval '10 days', now() + interval '355 days'),
    -- Pagó hace más de un año y no renovó: ya no da acceso.
    (crm_private.crm_new_code('SUS'), v_p_ex_pago, 'plan', null, 'vencida', 'manual', 'USD', now() - interval '400 days',
      now() - interval '400 days', now() - interval '35 days'),
    (crm_private.crm_new_code('SUS'), v_p_combo, 'plan', null, 'activa', 'manual', 'USD', now() - interval '65 days',
      now() - interval '65 days', v_combo_end),
    (crm_private.crm_new_code('SUS'), v_p_combo2, 'master', v_m2, 'activa', 'manual', 'USD', now() - interval '65 days',
      now() - interval '65 days', v_combo_end),
    -- Alguien del equipo que además paga un Máster: es del Campus, pero su cuenta es del equipo.
    (crm_private.crm_new_code('SUS'), v_p_equipo, 'master', v_m2, 'activa', 'manual', 'USD', now() - interval '10 days',
      now() - interval '10 days', now() + interval '355 days');
  select s.id into v_sub_mix from public.crm_subscriptions s where s.person_id = v_p_mix;

  -- Contenido: un curso por Máster y uno de regalo, con una clase publicada cada uno. La del
  -- primer Máster tiene un material y, al lado, una clase sin publicar. Además, un curso sin publicar.
  insert into public.campus_courses (master_id, slug, title, published, position)
    values (v_m1, 'prueba-acc-curso-1', '{"es":"Curso 1"}', true, 1) returning id into v_c1;
  insert into public.campus_courses (master_id, slug, title, published)
    values (v_m2, 'prueba-acc-curso-2', '{"es":"Curso 2"}', true) returning id into v_c2;
  insert into public.campus_courses (master_id, slug, title, published)
    values (null, 'prueba-acc-regalo', '{"es":"Regalo"}', true) returning id into v_gift;
  with m as (insert into public.campus_modules (course_id, title) values (v_c1, '{"es":"M"}') returning id)
  insert into public.campus_lessons (module_id, title, youtube_id, published)
    select id, '{"es":"L1"}', 'aaaaaaaaaaa', true from m returning id into v_l1;
  with m as (insert into public.campus_modules (course_id, title) values (v_c2, '{"es":"M"}') returning id)
  insert into public.campus_lessons (module_id, title, youtube_id, published)
    select id, '{"es":"L2"}', 'bbbbbbbbbbb', true from m returning id into v_l2;
  with m as (insert into public.campus_modules (course_id, title) values (v_gift, '{"es":"M"}') returning id)
  insert into public.campus_lessons (module_id, title, published)
    select id, '{"es":"LG"}', true from m returning id into v_lg;
  insert into public.campus_lesson_resources (lesson_id, label, url)
    values (v_l1, '{"es":"PDF"}', 'https://example.com/prueba-acc.pdf');
  -- Material como archivo en Storage (migración 20261010120100): lo puede leer quien ve la clase.
  v_path := v_l1::text || '/' || gen_random_uuid()::text || '.pdf';
  insert into public.campus_lesson_resources (lesson_id, label, kind, storage_path, file_name, file_size, mime_type)
    values (v_l1, '{"es":"Guía"}', 'file', v_path, 'guia.pdf', 1000, 'application/pdf');
  insert into public.campus_lessons (module_id, title, published)
    select module_id, '{"es":"L1 sin publicar"}', false from public.campus_lessons where id = v_l1
    returning id into v_l1_draft;
  insert into public.campus_courses (master_id, slug, title, published)
    values (null, 'prueba-acc-sin-publicar', '{"es":"Sin publicar"}', false) returning id into v_draft;
  with m as (insert into public.campus_modules (course_id, title) values (v_draft, '{"es":"M"}') returning id)
  insert into public.campus_lessons (module_id, title, published)
    select id, '{"es":"LD"}', true from m returning id into v_ld;

  -- El vencido había terminado una clase mientras tenía acceso.
  insert into public.campus_progress (user_id, lesson_id) values (v_old, v_l1);

  -- 1. Edge Function (service_role): marca la contraseña inicial.
  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  execute 'set local role service_role';
  perform public.campus_admin_mark_initial_password(v_ini, 'prueba@example.com');
  r := r || 'service.marca_inicial=ok ';
  begin
    perform public.campus_admin_mark_initial_password(v_nopass, null);
    r := r || 'service.no_marca_sin_contrasena=MAL '; fallas := fallas + 1;
  exception when invalid_parameter_value then r := r || 'service.no_marca_sin_contrasena=ok ';
  end;
  begin
    perform public.campus_admin_mark_initial_password(gen_random_uuid(), null);
    r := r || 'service.no_marca_cuenta_inexistente=MAL '; fallas := fallas + 1;
  exception when no_data_found then r := r || 'service.no_marca_cuenta_inexistente=ok ';
  end;
  begin
    perform 1 from campus_private.initial_passwords;
    r := r || 'service.no_lee_huellas=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'service.no_lee_huellas=ok ';
  end;
  -- La Edge Function lee el email para crear la cuenta o invitar, sin que pase por el navegador.
  if public.campus_admin_person_email(v_p_ini) = 'prueba-acc-inicial@example.com'
     and public.campus_admin_person_email(gen_random_uuid()) is null
  then r := r || 'service.lee_email=ok '; else r := r || 'service.lee_email=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  select k.fingerprint = encode(extensions.digest('hash-inicial', 'sha256'), 'hex') and k.set_by_email = 'prueba@example.com'
    into v_ok from campus_private.initial_passwords k where k.user_id = v_ini;
  if coalesce(v_ok, false) then r := r || 'datos.guarda_solo_la_huella=ok '; else r := r || 'datos.guarda_solo_la_huella=MAL '; fallas := fallas + 1; end if;

  -- 2. Acceso manual anual por 30 días, con la contraseña ya cambiada: todo, también el regalo.
  perform set_config('request.jwt.claims', json_build_object('sub', v_tmp, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_j := public.campus_me();
  if (v_j ->> 'plan')::boolean and not (v_j ->> 'must_change_password')::boolean
     and jsonb_array_length(v_j -> 'accesses') = 1
     and (v_j -> 'accesses' -> 0 ->> 'manual')::boolean
     and v_j -> 'accesses' -> 0 ->> 'kind' = 'plan'
  then r := r || 'temporal.me=ok '; else r := r || 'temporal.me=MAL '; fallas := fallas + 1; end if;
  -- Fechas, con el acceso guardado como lo guarda el CRM (crm_grant_end de hoy + 30 días):
  --   until = el fin exclusivo (la medianoche de Buenos Aires del día siguiente al último);
  --   last_day = el último día con acceso, el mismo que el CRM muestra "hasta el ... a las 23:59";
  --   access_until = el último instante con acceso: en Buenos Aires cae en el último día, no en el siguiente.
  if (v_j -> 'accesses' -> 0 ->> 'until')::timestamptz = v_tmp_end
     and (v_j -> 'accesses' -> 0 ->> 'last_day')::date = v_tmp_last_day
     and (v_j ->> 'access_until')::timestamptz = v_tmp_end - interval '1 microsecond'
     and ((v_j ->> 'access_until')::timestamptz at time zone 'America/Argentina/Buenos_Aires')::date = v_tmp_last_day
     and ((v_j -> 'accesses' -> 0 ->> 'until')::timestamptz at time zone 'America/Argentina/Buenos_Aires')::date = v_tmp_last_day + 1
  then r := r || 'temporal.me_ultimo_dia=ok '; else r := r || 'temporal.me_ultimo_dia=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lessons where id in (v_l1, v_l2, v_lg);
  if v_n = 3 then r := r || 'temporal.ve_todas_las_clases=ok '; else r := r || 'temporal.ve_todas_las_clases=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lessons where id in (v_l1_draft, v_ld);
  if v_n = 0 then r := r || 'temporal.solo_lo_publicado=ok '; else r := r || 'temporal.solo_lo_publicado=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_courses where id = v_draft;
  if v_n = 0 then r := r || 'temporal.no_ve_curso_sin_publicar=ok '; else r := r || 'temporal.no_ve_curso_sin_publicar=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lesson_resources where lesson_id = v_l1;
  if v_n = 2 then r := r || 'temporal.ve_materiales=ok '; else r := r || 'temporal.ve_materiales=MAL '; fallas := fallas + 1; end if;
  if campus_private.can_read_material(v_path) then r := r || 'temporal.lee_archivo=ok '; else r := r || 'temporal.lee_archivo=MAL '; fallas := fallas + 1; end if;
  insert into public.campus_progress (lesson_id) values (v_lg);
  r := r || 'temporal.marca_progreso=ok ';
  begin
    perform * from public.campus_account_target(v_p_tmp);
    r := r || 'temporal.no_lee_destino=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'temporal.no_lee_destino=ok ';
  end;
  begin
    perform * from public.campus_accounts_status(array[v_p_tmp]);
    r := r || 'temporal.no_lee_estado_cuentas=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'temporal.no_lee_estado_cuentas=ok ';
  end;
  begin
    perform public.campus_admin_mark_initial_password(v_tmp, null);
    r := r || 'temporal.no_marca_contrasena=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'temporal.no_marca_contrasena=ok ';
  end;
  begin
    perform public.campus_admin_clear_initial_password(v_ini);
    r := r || 'temporal.no_borra_marca=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'temporal.no_borra_marca=ok ';
  end;
  begin
    perform public.campus_admin_person_email(v_p_ini);
    r := r || 'temporal.no_lee_email=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'temporal.no_lee_email=ok ';
  end;
  begin
    perform * from public.campus_invite_target(v_sub_mix);
    r := r || 'temporal.no_lee_invitacion=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'temporal.no_lee_invitacion=ok ';
  end;
  begin
    perform 1 from campus_private.initial_passwords;
    r := r || 'temporal.no_lee_huellas=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'temporal.no_lee_huellas=ok ';
  end;
  begin
    insert into campus_private.initial_passwords (user_id, fingerprint) values (v_tmp, repeat('a', 64));
    r := r || 'temporal.no_escribe_huellas=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'temporal.no_escribe_huellas=ok ';
  end;
  begin
    perform campus_private.initial_password_pending(v_ini);
    r := r || 'temporal.no_consulta_otras_cuentas=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'temporal.no_consulta_otras_cuentas=ok ';
  end;
  begin
    perform campus_private.is_team_email(v_admin_email);
    r := r || 'temporal.no_consulta_equipo=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'temporal.no_consulta_equipo=ok ';
  end;
  begin
    select count(*) into v_n from public.crm_campus_grants;
    if v_n = 0 then r := r || 'temporal.no_lee_accesos_del_crm=ok '; else r := r || 'temporal.no_lee_accesos_del_crm=MAL '; fallas := fallas + 1; end if;
  exception when insufficient_privilege then r := r || 'temporal.no_lee_accesos_del_crm=ok ';
  end;
  execute 'reset role';

  -- 3. Acceso manual permanente a un Máster: solo ese Máster, sin fecha de fin.
  perform set_config('request.jwt.claims', json_build_object('sub', v_perm, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_j := public.campus_me();
  if not (v_j ->> 'plan')::boolean and v_j -> 'master_ids' = jsonb_build_array(v_m1)
     and v_j ? 'access_until' and v_j -> 'access_until' = 'null'::jsonb
     and v_j -> 'accesses' -> 0 -> 'until' = 'null'::jsonb
     and v_j -> 'accesses' -> 0 -> 'last_day' = 'null'::jsonb
     and (v_j -> 'accesses' -> 0 ->> 'manual')::boolean
  then r := r || 'permanente.me=ok '; else r := r || 'permanente.me=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lessons where id = v_l1 and youtube_id is not null;
  if v_n = 1 then r := r || 'permanente.ve_su_master=ok '; else r := r || 'permanente.ve_su_master=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lessons where id in (v_l2, v_lg);
  if v_n = 0 then r := r || 'permanente.no_ve_otros=ok '; else r := r || 'permanente.no_ve_otros=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- 4. Máster pago + acceso manual permanente a otro Máster: se suman.
  perform set_config('request.jwt.claims', json_build_object('sub', v_mix, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from public.campus_lessons where id in (v_l1, v_l2);
  if v_n = 2 then r := r || 'mixto.suma_accesos=ok '; else r := r || 'mixto.suma_accesos=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lessons where id = v_lg;
  if v_n = 0 then r := r || 'mixto.sin_regalo=ok '; else r := r || 'mixto.sin_regalo=MAL '; fallas := fallas + 1; end if;
  v_j := public.campus_me();
  if v_j -> 'access_until' = 'null'::jsonb
     and jsonb_array_length(v_j -> 'accesses') = 2
     and jsonb_array_length(v_j -> 'master_ids') = 2
     and exists (select 1 from jsonb_array_elements(v_j -> 'accesses') e
                 where (e ->> 'manual')::boolean and e -> 'until' = 'null'::jsonb and e ->> 'master_id' = v_m2::text)
     and exists (select 1 from jsonb_array_elements(v_j -> 'accesses') e
                 where not (e ->> 'manual')::boolean and e ->> 'until' is not null and e ->> 'last_day' is not null
                   and e ->> 'master_id' = v_m1::text)
  then r := r || 'mixto.me=ok '; else r := r || 'mixto.me=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- 4b. Anual paga con fecha + Máster permanente: "Mi cuenta" resume la anual, así que access_until
  -- es el fin de la anual (no null, que la haría parecer permanente).
  perform set_config('request.jwt.claims', json_build_object('sub', v_combo, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_j := public.campus_me();
  if (v_j ->> 'plan')::boolean
     and (v_j ->> 'access_until')::timestamptz = v_combo_end - interval '1 microsecond'
     and jsonb_array_length(v_j -> 'accesses') = 2
     and exists (select 1 from jsonb_array_elements(v_j -> 'accesses') e
                 where not (e ->> 'manual')::boolean and e ->> 'kind' = 'plan'
                   and (e ->> 'until')::timestamptz = v_combo_end
                   and (e ->> 'last_day')::date = ((v_combo_end - interval '1 microsecond') at time zone 'America/Argentina/Buenos_Aires')::date)
     and exists (select 1 from jsonb_array_elements(v_j -> 'accesses') e
                 where (e ->> 'manual')::boolean and e ->> 'master_id' = v_m1::text
                   and e -> 'until' = 'null'::jsonb and e -> 'last_day' = 'null'::jsonb)
  then r := r || 'anual_paga_y_master_permanente.me=ok '; else r := r || 'anual_paga_y_master_permanente.me=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- 4c. Anual manual permanente + Máster pago con fecha: la anual no vence, así que no hay fecha.
  perform set_config('request.jwt.claims', json_build_object('sub', v_combo2, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_j := public.campus_me();
  if (v_j ->> 'plan')::boolean and v_j -> 'access_until' = 'null'::jsonb
     and jsonb_array_length(v_j -> 'accesses') = 2
  then r := r || 'anual_permanente_y_master_pago.me=ok '; else r := r || 'anual_permanente_y_master_pago.me=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- 5. Acceso vencido: pierde las clases, la cuenta y el progreso quedan.
  perform set_config('request.jwt.claims', json_build_object('sub', v_old, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_j := public.campus_me();
  if v_j is not null and v_j ->> 'first_name' = 'Vencido' and not (v_j ->> 'plan')::boolean
     and jsonb_array_length(v_j -> 'accesses') = 0
  then r := r || 'vencido.cuenta_queda=ok '; else r := r || 'vencido.cuenta_queda=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lessons;
  if v_n = 0 then r := r || 'vencido.sin_clases=ok '; else r := r || 'vencido.sin_clases=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lesson_resources;
  if v_n = 0 then r := r || 'vencido.sin_materiales=ok '; else r := r || 'vencido.sin_materiales=MAL '; fallas := fallas + 1; end if;
  if not campus_private.can_read_material(v_path) then r := r || 'vencido.no_lee_archivo=ok '; else r := r || 'vencido.no_lee_archivo=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_progress where lesson_id = v_l1;
  if v_n = 1 then r := r || 'vencido.progreso_queda=ok '; else r := r || 'vencido.progreso_queda=MAL '; fallas := fallas + 1; end if;
  begin
    insert into public.campus_progress (lesson_id) values (v_l2);
    r := r || 'vencido.no_marca=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'vencido.no_marca=ok ';
  end;
  execute 'reset role';

  -- 6. Acceso que termina justo ahora (medianoche de Buenos Aires): ya no entra.
  perform set_config('request.jwt.claims', json_build_object('sub', v_edge, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from public.campus_lessons;
  if v_n = 0 and not (public.campus_me() ->> 'plan')::boolean then r := r || 'vence_ahora.sin_acceso=ok '; else r := r || 'vence_ahora.sin_acceso=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- 7. Acceso quitado: deja de ver las clases aunque la fecha de fin no llegó.
  perform set_config('request.jwt.claims', json_build_object('sub', v_rev, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from public.campus_lessons;
  if v_n = 0 and not (public.campus_me() ->> 'plan')::boolean then r := r || 'quitado.sin_acceso=ok '; else r := r || 'quitado.sin_acceso=MAL '; fallas := fallas + 1; end if;
  if not campus_private.can_read_material(v_path) then r := r || 'quitado.no_lee_archivo=ok '; else r := r || 'quitado.no_lee_archivo=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- 8. Acceso que todavía no empezó.
  perform set_config('request.jwt.claims', json_build_object('sub', v_fut, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from public.campus_lessons;
  if v_n = 0 and not (public.campus_me() ->> 'plan')::boolean then r := r || 'futuro.todavia_no=ok '; else r := r || 'futuro.todavia_no=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- 9. Cuenta sin ningún acceso.
  perform set_config('request.jwt.claims', json_build_object('sub', v_none, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_j := public.campus_me();
  if not (v_j ->> 'plan')::boolean and not (v_j ->> 'must_change_password')::boolean
     and jsonb_array_length(v_j -> 'accesses') = 0 and jsonb_array_length(v_j -> 'master_ids') = 0
     and v_j -> 'access_until' = 'null'::jsonb
  then r := r || 'sin_acceso.me=ok '; else r := r || 'sin_acceso.me=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lessons;
  if v_n = 0 then r := r || 'sin_acceso.sin_clases=ok '; else r := r || 'sin_acceso.sin_clases=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- 10. Equipo con "Dar acceso al Campus sin cobro", sin "Ver email y teléfono": los datos para crear la
  -- cuenta, sin el email (lo lee la Edge Function con la clave de servicio) y con permiso para contraseñas.
  perform set_config('request.jwt.claims', json_build_object('sub', v_acc, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select * into v_rec from public.campus_account_target(v_p_ini);
  if found and v_rec.email is null and v_rec.first_name = 'Inicial'
     and v_rec.has_access and not v_rec.has_paid and not v_rec.is_team and v_rec.can_set_password
  then r := r || 'accesos.destino_alumno=ok '; else r := r || 'accesos.destino_alumno=MAL '; fallas := fallas + 1; end if;
  select * into v_rec from public.campus_account_target(v_p_mix);
  if found and v_rec.email is null and v_rec.has_access and v_rec.has_paid and not v_rec.is_team and v_rec.can_set_password
  then r := r || 'accesos.destino_con_pago=ok '; else r := r || 'accesos.destino_con_pago=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n
  from unnest(array[v_p_old, v_p_edge, v_p_rev, v_p_fut]) as x(id), lateral public.campus_account_target(x.id) t
  where not t.has_access and not t.has_paid and not t.is_team and t.email is null;
  if v_n = 4 then r := r || 'accesos.sin_acceso_vigente=ok '; else r := r || 'accesos.sin_acceso_vigente=MAL '; fallas := fallas + 1; end if;
  -- Pagó y venció: sigue siendo del Campus (por ejemplo, para eliminar su cuenta), sin acceso.
  select * into v_rec from public.campus_account_target(v_p_ex_pago);
  if found and v_rec.email is null and v_rec.first_name = 'Ex pago' and not v_rec.has_access and not v_rec.has_paid
  then r := r || 'accesos.destino_pago_vencido=ok '; else r := r || 'accesos.destino_pago_vencido=MAL '; fallas := fallas + 1; end if;
  -- Una ficha del CRM que nunca tuvo nada en el Campus: no sale por acá.
  begin
    perform * from public.campus_account_target(v_p_none);
    r := r || 'accesos.no_destino_fuera_del_campus=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'accesos.no_destino_fuera_del_campus=ok ';
  end;
  select count(*) into v_n
  from unnest(array[v_p_admin, v_p_equipo, v_p_equipo_baja]) as x(id), lateral public.campus_account_target(x.id) t
  where t.is_team;
  if v_n = 3 then r := r || 'accesos.reconoce_equipo_y_nucleo=ok '; else r := r || 'accesos.reconoce_equipo_y_nucleo=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_account_target(gen_random_uuid());
  if v_n = 0 then r := r || 'accesos.persona_inexistente=ok '; else r := r || 'accesos.persona_inexistente=MAL '; fallas := fallas + 1; end if;
  -- El email solo lo lee la Edge Function: desde el navegador, ni con este permiso.
  begin
    perform public.campus_admin_person_email(v_p_ini);
    r := r || 'accesos.no_lee_email_directo=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'accesos.no_lee_email_directo=ok ';
  end;
  -- Invitar por email sigue pidiendo "Gestionar suscripciones".
  begin
    perform * from public.campus_invite_target(v_sub_mix);
    r := r || 'accesos.no_lee_invitacion=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'accesos.no_lee_invitacion=ok ';
  end;
  -- Estado de las cuentas: "Sin cuenta" tiene un acceso vigente y todavía no tiene cuenta.
  select count(*),
         count(*) filter (where not s.is_team and (
           (s.person_id = v_p_ini and s.has_account and s.confirmed and s.last_sign_in_at is null and s.must_change_password)
           or (s.person_id = v_p_tmp and s.has_account and s.confirmed and s.last_sign_in_at is not null and not s.must_change_password)
           or (s.person_id = v_p_sin_cuenta and not s.has_account and not s.confirmed and not s.must_change_password)))
    into v_n, v_n2
  from public.campus_accounts_status(array[v_p_ini, v_p_tmp, v_p_sin_cuenta, gen_random_uuid()]) s;
  if v_n = 3 and v_n2 = 3 then r := r || 'accesos.estado_cuentas=ok '; else r := r || 'accesos.estado_cuentas=MAL '; fallas := fallas + 1; end if;
  -- Fichas del CRM que nunca tuvieron nada en el Campus: no responde por ellas.
  select count(*) into v_n from public.campus_accounts_status(array[v_p_none]);
  if v_n = 0 then r := r || 'accesos.estado_fuera_del_campus=ok '; else r := r || 'accesos.estado_fuera_del_campus=MAL '; fallas := fallas + 1; end if;
  -- Cuentas del equipo y de Núcleo (la ficha con el email de la propietaria, la de alguien del equipo
  -- que entró ayer y la de un miembro desactivado): dice que existen, nada más.
  select count(*),
         count(*) filter (where s.is_team and s.has_account and s.confirmed is null
                            and s.last_sign_in_at is null and s.must_change_password is null)
    into v_n, v_n2
  from public.campus_accounts_status(array[v_p_admin, v_p_equipo, v_p_equipo_baja]) s;
  if v_n = 3 and v_n2 = 3 then r := r || 'accesos.estado_oculta_equipo=ok '; else r := r || 'accesos.estado_oculta_equipo=MAL '; fallas := fallas + 1; end if;
  begin
    perform * from public.campus_accounts_status(array_fill(gen_random_uuid(), array[2001]));
    r := r || 'accesos.tope_de_personas=MAL '; fallas := fallas + 1;
  exception when invalid_parameter_value then r := r || 'accesos.tope_de_personas=ok ';
  end;
  execute 'reset role';

  -- 10b. "Dar acceso al Campus sin cobro" con "Ver email y teléfono": también el email.
  perform set_config('request.jwt.claims', json_build_object('sub', v_acc2, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select * into v_rec from public.campus_account_target(v_p_ini);
  if found and v_rec.email = 'prueba-acc-inicial@example.com' and v_rec.can_set_password
  then r := r || 'accesos_contacto.destino_con_email=ok '; else r := r || 'accesos_contacto.destino_con_email=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- 11. Equipo con solo "Gestionar suscripciones": personas con suscripción paga, no los accesos manuales.
  -- Sin el email y sin permiso para contraseñas: para esas personas le queda invitar por email.
  perform set_config('request.jwt.claims', json_build_object('sub', v_ges, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select * into v_rec from public.campus_account_target(v_p_mix);
  if found and v_rec.has_paid and v_rec.email is null and not v_rec.can_set_password
  then r := r || 'gestiona.destino_con_pago=ok '; else r := r || 'gestiona.destino_con_pago=MAL '; fallas := fallas + 1; end if;
  begin
    perform * from public.campus_account_target(v_p_tmp);
    r := r || 'gestiona.no_destino_manual=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'gestiona.no_destino_manual=ok ';
  end;
  begin
    perform * from public.campus_account_target(v_p_ex_pago);
    r := r || 'gestiona.no_destino_pago_vencido=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'gestiona.no_destino_pago_vencido=ok ';
  end;
  begin
    perform * from public.campus_accounts_status(array[v_p_mix]);
    r := r || 'gestiona.no_lee_estado=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'gestiona.no_lee_estado=ok ';
  end;
  -- Invitación (campus_invite_target, reemplazada en esta migración): sin el email, con la persona
  -- para que la Edge Function lea el email con la clave de servicio.
  select * into v_rec from public.campus_invite_target(v_sub_mix);
  if found and v_rec.email is null and v_rec.person_id = v_p_mix and v_rec.first_name = 'Mixto'
     and v_rec.status = 'activa' and v_rec.subscription_code is not null
  then r := r || 'gestiona.invitacion_sin_email=ok '; else r := r || 'gestiona.invitacion_sin_email=MAL '; fallas := fallas + 1; end if;
  begin
    perform public.campus_admin_person_email(v_p_mix);
    r := r || 'gestiona.no_lee_email_directo=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'gestiona.no_lee_email_directo=ok ';
  end;
  execute 'reset role';

  -- 11b. "Gestionar suscripciones" con "Ver email y teléfono": ve el email, pero sigue sin poder
  -- generar contraseñas.
  perform set_config('request.jwt.claims', json_build_object('sub', v_ges2, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select * into v_rec from public.campus_account_target(v_p_mix);
  if found and v_rec.email = 'prueba-acc-mixto@example.com' and v_rec.has_paid and not v_rec.can_set_password
  then r := r || 'gestiona_contacto.destino=ok '; else r := r || 'gestiona_contacto.destino=MAL '; fallas := fallas + 1; end if;
  select * into v_rec from public.campus_invite_target(v_sub_mix);
  if found and v_rec.email = 'prueba-acc-mixto@example.com' and v_rec.person_id = v_p_mix
  then r := r || 'gestiona_contacto.invitacion=ok '; else r := r || 'gestiona_contacto.invitacion=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- 12. Equipo con solo "Ver suscripciones": ve el estado de las cuentas de quienes tienen una
  -- suscripción paga vigente; no los accesos manuales, ni leads, ni datos de las cuentas del equipo.
  perform set_config('request.jwt.claims', json_build_object('sub', v_ver, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*),
         count(*) filter (where s.person_id = v_p_mix and s.has_account and s.confirmed
                            and not s.must_change_password and not s.is_team)
    into v_n, v_n2
  from public.campus_accounts_status(array[v_p_mix, v_p_tmp]) s;
  if v_n = 1 and v_n2 = 1 then r := r || 've.lee_estado=ok '; else r := r || 've.lee_estado=MAL '; fallas := fallas + 1; end if;
  -- La ficha con el email de Núcleo (acceso quitado), un lead sin nada, un acceso manual y un pago vencido.
  select count(*) into v_n from public.campus_accounts_status(array[v_p_admin, v_p_none, v_p_tmp, v_p_ex_pago]);
  if v_n = 0 then r := r || 've.solo_pagos_vigentes=ok '; else r := r || 've.solo_pagos_vigentes=MAL '; fallas := fallas + 1; end if;
  -- Alguien del equipo que paga un Máster: aparece, sin cuándo entró ni el estado de su contraseña.
  select count(*) into v_n from public.campus_accounts_status(array[v_p_equipo]) s
  where s.is_team and s.has_account and s.confirmed is null and s.last_sign_in_at is null and s.must_change_password is null;
  if v_n = 1 then r := r || 've.oculta_equipo=ok '; else r := r || 've.oculta_equipo=MAL '; fallas := fallas + 1; end if;
  begin
    perform * from public.campus_account_target(v_p_mix);
    r := r || 've.no_lee_destino=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 've.no_lee_destino=ok ';
  end;
  execute 'reset role';

  -- 13. Equipo sin permisos del Campus y miembro desactivado: nada.
  perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    perform * from public.campus_account_target(v_p_ini);
    r := r || 'otro.no_lee_destino=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'otro.no_lee_destino=ok ';
  end;
  begin
    perform * from public.campus_accounts_status(array[v_p_ini]);
    r := r || 'otro.no_lee_estado=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'otro.no_lee_estado=ok ';
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', v_baja, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    perform * from public.campus_account_target(v_p_ini);
    r := r || 'desactivado.no_lee_destino=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'desactivado.no_lee_destino=ok ';
  end;
  begin
    perform * from public.campus_accounts_status(array[v_p_ini]);
    r := r || 'desactivado.no_lee_estado=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'desactivado.no_lee_estado=ok ';
  end;
  execute 'reset role';

  -- 14. Propietaria (y cuenta de Núcleo): siempre tiene el permiso y ve todo el contenido.
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select * into v_rec from public.campus_account_target(v_p_tmp);
  if found and v_rec.has_access and not v_rec.has_paid and v_rec.email = 'prueba-acc-temporal@example.com'
     and v_rec.can_set_password
  then r := r || 'propietaria.destino=ok '; else r := r || 'propietaria.destino=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_accounts_status(array[v_p_tmp, v_p_ini]);
  if v_n = 2 then r := r || 'propietaria.estado=ok '; else r := r || 'propietaria.estado=MAL '; fallas := fallas + 1; end if;
  select * into v_rec from public.campus_invite_target(v_sub_mix);
  if found and v_rec.email = 'prueba-acc-mixto@example.com' then r := r || 'propietaria.invitacion=ok '; else r := r || 'propietaria.invitacion=MAL '; fallas := fallas + 1; end if;
  begin
    perform public.campus_admin_person_email(v_p_tmp);
    r := r || 'propietaria.no_lee_email_directo=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'propietaria.no_lee_email_directo=ok ';
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from public.campus_lessons where id in (v_l1, v_l2, v_lg, v_l1_draft, v_ld);
  if v_n = 5 then r := r || 'nucleo.ve_todo=ok '; else r := r || 'nucleo.ve_todo=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- 15. Contraseña inicial: sin cambiarla no hay clases; al cambiarla se abren solas.
  perform set_config('request.jwt.claims', json_build_object('sub', v_ini, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_j := public.campus_me();
  if (v_j ->> 'must_change_password')::boolean and (v_j ->> 'plan')::boolean and v_j -> 'access_until' = 'null'::jsonb
  then r := r || 'inicial.me_pide_cambio=ok '; else r := r || 'inicial.me_pide_cambio=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lessons;
  if v_n = 0 then r := r || 'inicial.sin_clases=ok '; else r := r || 'inicial.sin_clases=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lesson_resources;
  if v_n = 0 then r := r || 'inicial.sin_materiales=ok '; else r := r || 'inicial.sin_materiales=MAL '; fallas := fallas + 1; end if;
  if not campus_private.can_read_material(v_path) then r := r || 'inicial.no_lee_archivo=ok '; else r := r || 'inicial.no_lee_archivo=MAL '; fallas := fallas + 1; end if;
  begin
    insert into public.campus_progress (lesson_id) values (v_lg);
    r := r || 'inicial.no_marca=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'inicial.no_marca=ok ';
  end;
  execute 'reset role';

  -- El alumno elige su contraseña: Supabase guarda otro hash y la huella deja de coincidir.
  update auth.users set encrypted_password = 'hash-elegido-por-el-alumno' where id = v_ini;
  perform set_config('request.jwt.claims', json_build_object('sub', v_ini, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from public.campus_lessons where id in (v_l1, v_l2, v_lg);
  if v_n = 3 and not (public.campus_me() ->> 'must_change_password')::boolean
  then r := r || 'inicial.cambio_abre_clases=ok '; else r := r || 'inicial.cambio_abre_clases=MAL '; fallas := fallas + 1; end if;
  if campus_private.can_read_material(v_path) then r := r || 'inicial.cambio_abre_archivos=ok '; else r := r || 'inicial.cambio_abre_archivos=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- "Contraseña nueva" desde el CRM: otra contraseña inicial y otra marca.
  update auth.users set encrypted_password = 'hash-inicial-2' where id = v_ini;
  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  execute 'set local role service_role';
  perform public.campus_admin_mark_initial_password(v_ini, 'prueba@example.com');
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', v_ini, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from public.campus_lessons;
  if v_n = 0 and (public.campus_me() ->> 'must_change_password')::boolean
  then r := r || 'inicial.contrasena_nueva_bloquea=ok '; else r := r || 'inicial.contrasena_nueva_bloquea=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- La Edge Function borra la marca: el acceso se abre y la segunda vez no hay nada que borrar.
  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  execute 'set local role service_role';
  v_ok := public.campus_admin_clear_initial_password(v_ini);
  v_ok2 := public.campus_admin_clear_initial_password(v_ini);
  if v_ok and not v_ok2 then r := r || 'service.borra_marca=ok '; else r := r || 'service.borra_marca=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', v_ini, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from public.campus_lessons where id in (v_l1, v_l2, v_lg);
  if v_n = 3 and not (public.campus_me() ->> 'must_change_password')::boolean
  then r := r || 'inicial.sin_marca_accede=ok '; else r := r || 'inicial.sin_marca_accede=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- 16. La contraseña inicial también frena lo pago (cuenta creada desde una suscripción): sigue viendo
  -- qué incluye su acceso, pero no las clases hasta cambiarla.
  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  execute 'set local role service_role';
  perform public.campus_admin_mark_initial_password(v_mix, 'prueba@example.com');
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', v_mix, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from public.campus_lessons where id in (v_l1, v_l2);
  v_j := public.campus_me();
  if v_n = 0 and (v_j ->> 'must_change_password')::boolean and jsonb_array_length(v_j -> 'accesses') = 2
  then r := r || 'pago.inicial_bloquea=ok '; else r := r || 'pago.inicial_bloquea=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- 17. Visitante sin sesión: nada.
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  begin
    perform * from public.campus_account_target(v_p_tmp);
    r := r || 'anon.sin_destino=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.sin_destino=ok ';
  end;
  begin
    perform * from public.campus_accounts_status(array[v_p_tmp]);
    r := r || 'anon.sin_estado=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.sin_estado=ok ';
  end;
  begin
    perform public.campus_admin_mark_initial_password(v_tmp, null);
    r := r || 'anon.no_marca=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.no_marca=ok ';
  end;
  begin
    perform public.campus_admin_clear_initial_password(v_ini);
    r := r || 'anon.no_borra_marca=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.no_borra_marca=ok ';
  end;
  begin
    perform public.campus_admin_person_email(v_p_tmp);
    r := r || 'anon.sin_email=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.sin_email=ok ';
  end;
  begin
    perform * from public.campus_invite_target(v_sub_mix);
    r := r || 'anon.sin_invitacion=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.sin_invitacion=ok ';
  end;
  begin
    perform public.campus_me();
    r := r || 'anon.sin_me=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.sin_me=ok ';
  end;
  begin
    perform 1 from campus_private.initial_passwords;
    r := r || 'anon.sin_huellas=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.sin_huellas=ok ';
  end;
  begin
    perform campus_private.can_read_material(v_path);
    r := r || 'anon.sin_archivos=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.sin_archivos=ok ';
  end;
  execute 'reset role';

  raise exception 'Resultado (se revierte todo): % FALLAS: %', r, fallas;
end;
$$;
