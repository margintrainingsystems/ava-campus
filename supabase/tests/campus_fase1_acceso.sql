-- Prueba de acceso del Campus, fase 1.
-- Correla en el SQL Editor de Supabase o con la herramienta execute_sql.
-- Crea cuentas, personas, suscripciones y cursos de prueba, simula cada tipo de cuenta y
-- termina con un error a propósito: así Postgres revierte todo y la base queda igual que antes.
-- Leé el mensaje del error: cada chequeo dice "ok" o "MAL", y al final "FALLAS: n".

do $$
declare
  v_admin uuid := (select user_id from public.admins order by created_at limit 1);
  v_plan uuid := gen_random_uuid();
  v_master uuid := gen_random_uuid();
  v_cancel_ok uuid := gen_random_uuid();
  v_cancel_old uuid := gen_random_uuid();
  v_none uuid := gen_random_uuid();
  v_m1 uuid;
  v_m2 uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_gift uuid;
  v_draft uuid;
  v_l1 uuid;
  v_l1_draft uuid;
  v_l2 uuid;
  v_lg uuid;
  v_sub_master uuid;
  v_n int;
  v_j jsonb;
  r text := '';
  fallas int := 0;
begin
  select id into v_m1 from public.masters order by order_index limit 1;
  select id into v_m2 from public.masters order by order_index offset 1 limit 1;
  if v_admin is null or v_m1 is null or v_m2 is null then
    raise exception 'La prueba necesita una cuenta en admins y al menos dos Másteres';
  end if;

  -- Cuentas, personas del CRM y suscripciones (como las registra el CRM).
  insert into auth.users (id, email, aud, role) values
    (v_plan, 'prueba-anual@example.com', 'authenticated', 'authenticated'),
    (v_master, 'prueba-master@example.com', 'authenticated', 'authenticated'),
    (v_cancel_ok, 'prueba-baja-vigente@example.com', 'authenticated', 'authenticated'),
    (v_cancel_old, 'prueba-baja-vencida@example.com', 'authenticated', 'authenticated'),
    (v_none, 'prueba-sin-plan@example.com', 'authenticated', 'authenticated');

  with p as (
    insert into public.crm_people (email_normalized, email, first_name) values
      ('prueba-anual@example.com', 'prueba-anual@example.com', 'Anual'),
      ('prueba-master@example.com', 'prueba-master@example.com', 'Master'),
      ('prueba-baja-vigente@example.com', 'prueba-baja-vigente@example.com', 'Vigente'),
      ('prueba-baja-vencida@example.com', 'prueba-baja-vencida@example.com', 'Vencida'),
      ('prueba-sin-plan@example.com', 'prueba-sin-plan@example.com', 'Sin plan')
    returning id, email_normalized
  )
  insert into public.crm_subscriptions (code, person_id, kind, master_id, status, provider, currency, started_at,
    current_period_start, current_period_end)
  select 'SUS-T' || substr(md5(p.email_normalized), 1, 5), p.id,
    case when p.email_normalized like 'prueba-master%' then 'master' else 'plan' end,
    case when p.email_normalized like 'prueba-master%' then v_m1 end,
    case
      when p.email_normalized like 'prueba-baja-vigente%' then 'cancelada'
      when p.email_normalized like 'prueba-baja-vencida%' then 'cancelada'
      when p.email_normalized like 'prueba-sin-plan%' then 'vencida'
      else 'activa'
    end,
    'manual', 'USD', now() - interval '400 days',
    case when p.email_normalized like 'prueba-baja-vencida%' or p.email_normalized like 'prueba-sin-plan%'
      then now() - interval '400 days' else now() - interval '10 days' end,
    case when p.email_normalized like 'prueba-baja-vencida%' or p.email_normalized like 'prueba-sin-plan%'
      then now() - interval '35 days' else now() + interval '355 days' end
  from p;
  select s.id into v_sub_master from public.crm_subscriptions s
    join public.crm_people p on p.id = s.person_id where p.email_normalized = 'prueba-master@example.com';

  -- Contenido: un curso por Máster, uno de regalo y un borrador.
  insert into public.campus_courses (master_id, slug, title, published, position)
    values (v_m1, 'prueba-curso-1', '{"es":"Curso 1","en":"Course 1"}', true, 1) returning id into v_c1;
  insert into public.campus_courses (master_id, slug, title, published)
    values (v_m2, 'prueba-curso-2', '{"es":"Curso 2"}', true) returning id into v_c2;
  insert into public.campus_courses (master_id, slug, title, published)
    values (null, 'prueba-regalo', '{"es":"Regalo"}', true) returning id into v_gift;
  insert into public.campus_courses (master_id, slug, title, published)
    values (v_m1, 'prueba-borrador', '{"es":"Borrador"}', false) returning id into v_draft;

  with m as (insert into public.campus_modules (course_id, title) values (v_c1, '{"es":"M"}') returning id)
  insert into public.campus_lessons (module_id, title, youtube_id) select id, '{"es":"L1"}', 'aaaaaaaaaaa' from m
  returning id into v_l1;
  insert into public.campus_lessons (module_id, title, published)
    select module_id, '{"es":"L1 borrador"}', false from public.campus_lessons where id = v_l1
    returning id into v_l1_draft;
  insert into public.campus_lesson_resources (lesson_id, label, url) values (v_l1, '{"es":"PDF"}', 'https://example.com/a.pdf');
  with m as (insert into public.campus_modules (course_id, title) values (v_c2, '{"es":"M"}') returning id)
  insert into public.campus_lessons (module_id, title, youtube_id) select id, '{"es":"L2"}', 'bbbbbbbbbbb' from m
  returning id into v_l2;
  with m as (insert into public.campus_modules (course_id, title) values (v_gift, '{"es":"M"}') returning id)
  insert into public.campus_lessons (module_id, title) select id, '{"es":"LG"}' from m returning id into v_lg;

  -- Formato de los textos traducibles.
  begin
    insert into public.campus_courses (slug, title) values ('prueba-sin-es', '{"en":"Only English"}');
    r := r || 'datos.exige_espanol=MAL '; fallas := fallas + 1;
  exception when check_violation then r := r || 'datos.exige_espanol=ok ';
  end;
  begin
    insert into public.campus_courses (slug, title) values ('prueba-idioma', '{"es":"x","fr":"x"}');
    r := r || 'datos.solo_es_en_pt=MAL '; fallas := fallas + 1;
  exception when check_violation then r := r || 'datos.solo_es_en_pt=ok ';
  end;
  begin
    update public.campus_lessons set youtube_id = 'https://youtu.be/aaaaaaaaaaa' where id = v_l1;
    r := r || 'datos.youtube_solo_id=MAL '; fallas := fallas + 1;
  exception when check_violation then r := r || 'datos.youtube_solo_id=ok ';
  end;

  -- 1. Suscripción anual: todos los cursos publicados, también el de regalo.
  perform set_config('request.jwt.claims', json_build_object('sub', v_plan, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_j := public.campus_me();
  if (v_j ->> 'plan')::boolean and v_j ->> 'first_name' = 'Anual' then r := r || 'anual.me=ok '; else r := r || 'anual.me=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lessons where id in (v_l1, v_l2, v_lg);
  if v_n = 3 then r := r || 'anual.ve_todas_las_clases=ok '; else r := r || 'anual.ve_todas_las_clases=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lessons where id = v_l1_draft;
  if v_n = 0 then r := r || 'anual.no_ve_clase_borrador=ok '; else r := r || 'anual.no_ve_clase_borrador=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_courses where id = v_draft;
  if v_n = 0 then r := r || 'anual.no_ve_curso_borrador=ok '; else r := r || 'anual.no_ve_curso_borrador=MAL '; fallas := fallas + 1; end if;
  select lessons into v_n from public.campus_course_lesson_counts() where course_id = v_c1;
  if v_n = 1 then r := r || 'anual.cuenta_solo_publicadas=ok '; else r := r || 'anual.cuenta_solo_publicadas=MAL '; fallas := fallas + 1; end if;
  insert into public.campus_progress (lesson_id) values (v_lg);
  r := r || 'anual.marca_regalo=ok ';
  begin
    insert into public.campus_courses (slug, title) values ('prueba-intento', '{"es":"x"}');
    r := r || 'anual.no_edita_contenido=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anual.no_edita_contenido=ok ';
  end;
  begin
    perform * from public.campus_invite_target(v_sub_master);
    r := r || 'anual.no_lee_suscripciones=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anual.no_lee_suscripciones=ok ';
  end;
  execute 'reset role';

  -- 2. Máster suelto: solo los cursos de su Máster, sin los de regalo.
  perform set_config('request.jwt.claims', json_build_object('sub', v_master, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_j := public.campus_me();
  if not (v_j ->> 'plan')::boolean and v_j -> 'master_ids' = jsonb_build_array(v_m1) then r := r || 'master.me=ok '; else r := r || 'master.me=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lessons where id = v_l1 and youtube_id is not null;
  if v_n = 1 then r := r || 'master.ve_su_video=ok '; else r := r || 'master.ve_su_video=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lessons where id in (v_l2, v_lg);
  if v_n = 0 then r := r || 'master.no_ve_otras_clases=ok '; else r := r || 'master.no_ve_otras_clases=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lesson_resources;
  if v_n = 1 then r := r || 'master.materiales_propios=ok '; else r := r || 'master.materiales_propios=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_courses where id in (v_c1, v_c2, v_gift);
  if v_n = 3 then r := r || 'master.ve_catalogo=ok '; else r := r || 'master.ve_catalogo=MAL '; fallas := fallas + 1; end if;
  insert into public.campus_progress (lesson_id) values (v_l1);
  r := r || 'master.marca_su_clase=ok ';
  begin
    insert into public.campus_progress (lesson_id) values (v_l2);
    r := r || 'master.no_marca_ajena=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'master.no_marca_ajena=ok ';
  end;
  begin
    insert into public.campus_progress (user_id, lesson_id) values (v_plan, v_l1);
    r := r || 'master.no_marca_por_otra=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'master.no_marca_por_otra=ok ';
  end;
  select count(*) into v_n from public.campus_progress;
  if v_n = 1 then r := r || 'master.ve_solo_su_progreso=ok '; else r := r || 'master.ve_solo_su_progreso=MAL '; fallas := fallas + 1; end if;
  delete from public.campus_progress where lesson_id = v_l1;
  select count(*) into v_n from public.campus_progress;
  if v_n = 0 then r := r || 'master.desmarca=ok '; else r := r || 'master.desmarca=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- 3. Baja vigente: acceso hasta el fin del período. Baja vencida y suscripción vencida: sin acceso.
  perform set_config('request.jwt.claims', json_build_object('sub', v_cancel_ok, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from public.campus_lessons where id = v_l1;
  if v_n = 1 then r := r || 'baja_vigente.accede=ok '; else r := r || 'baja_vigente.accede=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub', v_cancel_old, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from public.campus_lessons;
  if v_n = 0 then r := r || 'baja_vencida.sin_clases=ok '; else r := r || 'baja_vencida.sin_clases=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub', v_none, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_j := public.campus_me();
  if not (v_j ->> 'plan')::boolean and jsonb_array_length(v_j -> 'master_ids') = 0 then r := r || 'vencida.me_sin_acceso=ok '; else r := r || 'vencida.me_sin_acceso=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lessons;
  if v_n = 0 then r := r || 'vencida.sin_clases=ok '; else r := r || 'vencida.sin_clases=MAL '; fallas := fallas + 1; end if;
  begin
    insert into public.campus_progress (lesson_id) values (v_l1);
    r := r || 'vencida.no_marca=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'vencida.no_marca=ok ';
  end;
  execute 'reset role';

  -- 4. Cuenta de Núcleo: ve borradores y edita contenido. Como propietaria del CRM, lee la suscripción.
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from public.campus_courses where id = v_draft;
  if v_n = 1 then r := r || 'nucleo.ve_borrador=ok '; else r := r || 'nucleo.ve_borrador=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lessons where id = v_l1_draft;
  if v_n = 1 then r := r || 'nucleo.ve_clase_borrador=ok '; else r := r || 'nucleo.ve_clase_borrador=MAL '; fallas := fallas + 1; end if;
  update public.campus_courses set position = 5 where id = v_c2;
  get diagnostics v_n = row_count;
  if v_n = 1 then r := r || 'nucleo.edita=ok '; else r := r || 'nucleo.edita=MAL '; fallas := fallas + 1; end if;
  if (select email from public.campus_invite_target(v_sub_master)) = 'prueba-master@example.com' then
    r := r || 'nucleo.lee_destino_invitacion=ok ';
  else
    r := r || 'nucleo.lee_destino_invitacion=MAL '; fallas := fallas + 1;
  end if;
  execute 'reset role';

  -- 5. Visitante sin sesión: nada.
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  begin
    perform 1 from public.campus_courses;
    r := r || 'anon.sin_cursos=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.sin_cursos=ok ';
  end;
  begin
    perform public.campus_me();
    r := r || 'anon.sin_me=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.sin_me=ok ';
  end;
  execute 'reset role';

  raise exception 'Resultado (se revierte todo): % FALLAS: %', r, fallas;
end;
$$;
