-- Prueba de los borradores de cursos, los materiales como archivos (Supabase Storage) y el orden de
-- los cursos. Necesita aplicada la migración del Campus 20261010120100. Si además está aplicada la
-- 20261010120200 (accesos manuales), suma los casos de acceso manual permanente, quitado y vencido.
-- Correla en el SQL Editor de Supabase o con la herramienta execute_sql.
-- Crea cuentas, personas, suscripciones, cursos, materiales y archivos de prueba (filas en
-- storage.objects, sin archivos de verdad), simula cada tipo de cuenta y termina con un error a
-- propósito: así Postgres revierte todo y la base queda igual que antes (tampoco se dispara el
-- trigger que impide borrar archivos con SQL). Leé el mensaje del error: cada chequeo dice "ok" o
-- "MAL", y al final "FALLAS: n".
-- Los alumnos no leen el bucket (así Storage no les firma links de la duración que quieran): bajan
-- cada archivo con la Edge Function campus-material, que firma 60 segundos. La prueba revisa lo que
-- esa función le pregunta a la base, campus_material_file(ruta), y que ningún alumno lea
-- storage.objects. La función en sí (la firma) no se puede probar desde SQL.

do $$
declare
  v_admin uuid := (select user_id from public.admins order by created_at limit 1);
  v_admin_email text;
  -- Cuentas
  v_plan uuid := gen_random_uuid();        -- suscripción anual activa
  v_master uuid := gen_random_uuid();      -- Máster suelto del primer Máster
  v_other uuid := gen_random_uuid();       -- Máster suelto del segundo Máster
  v_cancel_ok uuid := gen_random_uuid();   -- anual dada de baja, todavía dentro del año pagado
  v_cancel_old uuid := gen_random_uuid();  -- anual dada de baja, con el año pagado terminado
  v_expired uuid := gen_random_uuid();     -- anual vencida
  v_refund uuid := gen_random_uuid();      -- anual reembolsada
  v_none uuid := gen_random_uuid();        -- cuenta sin persona en el CRM
  v_g_perm uuid := gen_random_uuid();      -- acceso manual anual permanente (con la 20261010120200)
  v_g_rev uuid := gen_random_uuid();       -- acceso manual anual quitado
  v_g_old uuid := gen_random_uuid();       -- acceso manual anual vencido
  v_grants boolean;
  v_m1 uuid;
  v_m2 uuid;
  -- Cursos
  v_c1 uuid := gen_random_uuid();      -- primer Máster, publicado: el que se edita con borradores
  v_c2 uuid := gen_random_uuid();      -- segundo Máster, publicado
  v_gift uuid := gen_random_uuid();    -- de regalo, publicado
  v_hidden uuid := gen_random_uuid();  -- primer Máster, sin publicar
  -- Módulos
  v_ma uuid := gen_random_uuid();      -- c1, módulo A
  v_mb uuid := gen_random_uuid();      -- c1, módulo B: el borrador lo borra
  v_mc2 uuid := gen_random_uuid();
  v_mg uuid := gen_random_uuid();
  v_mh uuid := gen_random_uuid();
  v_mn uuid := gen_random_uuid();      -- módulo nuevo del borrador
  -- Clases
  v_l1 uuid := gen_random_uuid();      -- c1, módulo A
  v_l2 uuid := gen_random_uuid();      -- c1, módulo A: el borrador la borra (tiene progreso)
  v_l3 uuid := gen_random_uuid();      -- c1, módulo B: el borrador la pasa al módulo nuevo (tiene progreso)
  v_l4 uuid := gen_random_uuid();      -- c1, módulo B, sin publicar: el borrador la borra
  v_l5 uuid := gen_random_uuid();      -- c2
  v_lg uuid := gen_random_uuid();      -- regalo
  v_lh uuid := gen_random_uuid();      -- curso sin publicar
  v_ln uuid := gen_random_uuid();      -- clase nueva del borrador
  -- Materiales
  v_r1 uuid := gen_random_uuid();      -- archivo de L1
  v_r2 uuid := gen_random_uuid();      -- link de L1: el borrador lo pasa a la clase nueva
  v_r3 uuid := gen_random_uuid();      -- archivo de L3: el borrador lo borra
  v_r4 uuid := gen_random_uuid();      -- archivo de L4 (clase sin publicar)
  v_r5 uuid := gen_random_uuid();      -- archivo de c2
  v_rg uuid := gen_random_uuid();      -- archivo del regalo
  v_rh uuid := gen_random_uuid();      -- archivo del curso sin publicar
  v_rn uuid := gen_random_uuid();      -- archivo nuevo del borrador
  v_rx uuid;
  -- Rutas en el bucket
  v_p1 text; v_p3 text; v_p4 text; v_p5 text; v_pg text; v_ph text; v_pn text;
  v_p_draft text;                      -- solo en el borrador de c2
  v_p_old text;                        -- sin usar, subido hace dos días
  v_p_new text;                        -- sin usar, recién subido
  v_p_up text;                         -- lo sube la cuenta de Núcleo durante la prueba
  v_paths text[];
  v_all4 text[];                       -- lo que ve la suscripción anual
  -- Borradores
  v_base jsonb;                        -- borrador de c1
  v_c2_draft jsonb;
  v_swap jsonb;
  v_ts timestamptz;
  v_ts2 timestamptz;
  v_rec record;
  v_j jsonb;
  v_t text[];
  v_ok boolean;
  v_n int;
  r text := '';
  fallas int := 0;
begin
  if to_regclass('public.campus_course_drafts') is null
     or not exists (select 1 from storage.buckets where id = 'campus-materiales')
     or to_regprocedure('public.campus_material_file(text)') is null then
    raise exception 'La prueba necesita aplicada la migración del Campus 20261010120100';
  end if;
  select id into v_m1 from public.masters order by order_index limit 1;
  select id into v_m2 from public.masters order by order_index offset 1 limit 1;
  select lower(btrim(email)) into v_admin_email from auth.users where id = v_admin;
  if v_admin_email is null or v_m1 is null or v_m2 is null then
    raise exception 'La prueba necesita una cuenta en admins y al menos dos Másteres';
  end if;
  -- Accesos manuales: solo si la 20261010120200 ya cambió current_subscriptions.
  v_grants := to_regclass('public.crm_campus_grants') is not null and exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = to_regprocedure('campus_private.current_subscriptions()')
      and p.prosrc like '%crm_campus_grants%'
  );
  perform set_config('request.jwt.claims', '', true);

  v_p1 := format('%s/%s.pdf', v_l1, gen_random_uuid());
  v_p3 := format('%s/%s.xlsx', v_l3, gen_random_uuid());
  v_p4 := format('%s/%s.docx', v_l4, gen_random_uuid());
  v_p5 := format('%s/%s.pdf', v_l5, gen_random_uuid());
  v_pg := format('%s/%s.png', v_lg, gen_random_uuid());
  v_ph := format('%s/%s.pdf', v_lh, gen_random_uuid());
  v_pn := format('%s/%s.xlsx', v_ln, gen_random_uuid());
  v_p_draft := format('%s/%s.csv', v_l5, gen_random_uuid());
  v_p_old := format('%s/%s.pdf', v_l2, gen_random_uuid());
  v_p_new := format('%s/%s.txt', v_l2, gen_random_uuid());
  v_p_up := format('%s/%s.pdf', v_l1, gen_random_uuid());
  v_paths := array[v_p1, v_p3, v_p4, v_p5, v_pg, v_ph, v_pn, v_p_draft, v_p_old, v_p_new];
  v_all4 := array[v_p1, v_p3, v_p5, v_pg];

  -- Cuentas, personas del CRM y suscripciones (como las registra el CRM).
  insert into auth.users (id, email, aud, role) values
    (v_plan, 'prueba-bm-anual@example.com', 'authenticated', 'authenticated'),
    (v_master, 'prueba-bm-master@example.com', 'authenticated', 'authenticated'),
    (v_other, 'prueba-bm-otro-master@example.com', 'authenticated', 'authenticated'),
    (v_cancel_ok, 'prueba-bm-baja-vigente@example.com', 'authenticated', 'authenticated'),
    (v_cancel_old, 'prueba-bm-baja-vencida@example.com', 'authenticated', 'authenticated'),
    (v_expired, 'prueba-bm-vencida@example.com', 'authenticated', 'authenticated'),
    (v_refund, 'prueba-bm-reembolsada@example.com', 'authenticated', 'authenticated'),
    (v_none, 'prueba-bm-sin-crm@example.com', 'authenticated', 'authenticated');

  with p as (
    insert into public.crm_people (email_normalized, email, first_name) values
      ('prueba-bm-anual@example.com', 'prueba-bm-anual@example.com', 'Anual'),
      ('prueba-bm-master@example.com', 'prueba-bm-master@example.com', 'Master'),
      ('prueba-bm-otro-master@example.com', 'prueba-bm-otro-master@example.com', 'Otro Master'),
      ('prueba-bm-baja-vigente@example.com', 'prueba-bm-baja-vigente@example.com', 'Baja vigente'),
      ('prueba-bm-baja-vencida@example.com', 'prueba-bm-baja-vencida@example.com', 'Baja vencida'),
      ('prueba-bm-vencida@example.com', 'prueba-bm-vencida@example.com', 'Vencida'),
      ('prueba-bm-reembolsada@example.com', 'prueba-bm-reembolsada@example.com', 'Reembolsada')
    returning id, email_normalized
  )
  insert into public.crm_subscriptions (code, person_id, kind, master_id, status, provider, currency, started_at,
    current_period_start, current_period_end)
  select 'SUS-BM' || substr(md5(p.email_normalized), 1, 6), p.id, s.kind, s.master_id, s.status, 'manual', 'USD',
    now() - interval '400 days', s.period_start, s.period_end
  from p
  join (values
    ('prueba-bm-anual@example.com', 'plan', null::uuid, 'activa', now() - interval '10 days', now() + interval '355 days'),
    ('prueba-bm-master@example.com', 'master', v_m1, 'activa', now() - interval '10 days', now() + interval '355 days'),
    ('prueba-bm-otro-master@example.com', 'master', v_m2, 'activa', now() - interval '10 days', now() + interval '355 days'),
    ('prueba-bm-baja-vigente@example.com', 'plan', null, 'cancelada', now() - interval '10 days', now() + interval '355 days'),
    ('prueba-bm-baja-vencida@example.com', 'plan', null, 'cancelada', now() - interval '400 days', now() - interval '35 days'),
    ('prueba-bm-vencida@example.com', 'plan', null, 'vencida', now() - interval '400 days', now() - interval '35 days'),
    ('prueba-bm-reembolsada@example.com', 'plan', null, 'reembolsada', now() - interval '10 days', now() + interval '355 days')
  ) as s (email, kind, master_id, status, period_start, period_end) on s.email = p.email_normalized;

  -- Accesos manuales (como los guarda el CRM), si está la migración que los lee.
  if v_grants then
    insert into auth.users (id, email, aud, role) values
      (v_g_perm, 'prueba-bm-manual-permanente@example.com', 'authenticated', 'authenticated'),
      (v_g_rev, 'prueba-bm-manual-quitado@example.com', 'authenticated', 'authenticated'),
      (v_g_old, 'prueba-bm-manual-vencido@example.com', 'authenticated', 'authenticated');
    execute $q$
      with p as (
        insert into public.crm_people (email_normalized, email, first_name) values
          ('prueba-bm-manual-permanente@example.com', 'prueba-bm-manual-permanente@example.com', 'Permanente'),
          ('prueba-bm-manual-quitado@example.com', 'prueba-bm-manual-quitado@example.com', 'Quitado'),
          ('prueba-bm-manual-vencido@example.com', 'prueba-bm-manual-vencido@example.com', 'Vencido')
        returning id, email_normalized
      )
      insert into public.crm_campus_grants (code, person_id, kind, master_id, starts_at, ends_at, reason,
        adult_checked, revoked_at, revoked_by_email, revoke_note)
      select 'ACC-BM' || substr(md5(p.email_normalized), 1, 6), p.id, 'plan', null, now() - interval '40 days',
        case
          when p.email_normalized like '%vencido%' then now() - interval '1 day'
          when p.email_normalized like '%quitado%' then now() + interval '30 days'
        end,
        'Prueba', true,
        case when p.email_normalized like '%quitado%' then now() - interval '1 hour' end,
        case when p.email_normalized like '%quitado%' then 'prueba@example.com' end,
        case when p.email_normalized like '%quitado%' then 'Quitado en la prueba' end
      from p
    $q$;
  end if;

  -- Contenido. c1: módulo A (L1 con un archivo y un link, L2) y módulo B (L3 con un archivo, L4 sin
  -- publicar con un archivo). c2, regalo y un curso sin publicar: una clase con un archivo cada uno.
  insert into public.campus_courses (id, master_id, slug, title, summary, published, position) values
    (v_c1, v_m1, 'prueba-bm-curso-1', '{"es":"Curso 1","en":"Course 1"}', '{"es":"Resumen"}', true, 1),
    (v_c2, v_m2, 'prueba-bm-curso-2', '{"es":"Curso 2"}', '{}', true, 1),
    (v_gift, null, 'prueba-bm-regalo', '{"es":"Regalo"}', '{}', true, 1),
    (v_hidden, v_m1, 'prueba-bm-sin-publicar', '{"es":"Sin publicar"}', '{}', false, 2);
  insert into public.campus_modules (id, course_id, title, position) values
    (v_ma, v_c1, '{"es":"Módulo A"}', 1),
    (v_mb, v_c1, '{"es":"Módulo B"}', 2),
    (v_mc2, v_c2, '{"es":"M"}', 1),
    (v_mg, v_gift, '{"es":"M"}', 1),
    (v_mh, v_hidden, '{"es":"M"}', 1);
  insert into public.campus_lessons (id, module_id, title, youtube_id, published, position) values
    (v_l1, v_ma, '{"es":"L1"}', 'aaaaaaaaaaa', true, 1),
    (v_l2, v_ma, '{"es":"L2"}', null, true, 2),
    (v_l3, v_mb, '{"es":"L3"}', 'bbbbbbbbbbb', true, 1),
    (v_l4, v_mb, '{"es":"L4 sin publicar"}', null, false, 2),
    (v_l5, v_mc2, '{"es":"L5"}', null, true, 1),
    (v_lg, v_mg, '{"es":"LG"}', null, true, 1),
    (v_lh, v_mh, '{"es":"LH"}', null, true, 1);
  insert into public.campus_lesson_resources (id, lesson_id, label, kind, url, storage_path, file_name, file_size,
    mime_type, position) values
    (v_r1, v_l1, '{"es":"Guía"}', 'file', null, v_p1, 'guia.pdf', 1000, 'application/pdf', 1),
    (v_r2, v_l1, '{"es":"Plantilla en Canva"}', 'link', 'https://example.com/plantilla', null, null, null, null, 2),
    (v_r3, v_l3, '{"es":"Planilla"}', 'file', null, v_p3, 'planilla.xlsx', 2000,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 1),
    (v_r4, v_l4, '{"es":"Documento"}', 'file', null, v_p4, 'documento.docx', 3000,
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 1),
    (v_r5, v_l5, '{"es":"PDF"}', 'file', null, v_p5, 'curso-2.pdf', 4000, 'application/pdf', 1),
    (v_rg, v_lg, '{"es":"Imagen"}', 'file', null, v_pg, 'regalo.png', 5000, 'image/png', 1),
    (v_rh, v_lh, '{"es":"PDF"}', 'file', null, v_ph, 'sin-publicar.pdf', 6000, 'application/pdf', 1);

  -- Archivos del bucket (solo la fila, como la deja la API de Storage). Todos de hace dos días menos uno.
  insert into storage.objects (bucket_id, name, owner, owner_id, created_at, metadata)
  select 'campus-materiales', x.path, v_admin, v_admin::text,
    case when x.path = v_p_new then now() else now() - interval '2 days' end,
    '{"size": 1000}'::jsonb
  from unnest(v_paths) as x (path);

  -- El Máster suelto terminó L2 y L3.
  insert into public.campus_progress (user_id, lesson_id) values (v_master, v_l2), (v_master, v_l3);

  -- 1. Reglas de los materiales (las aplica la tabla para cualquier cuenta) y del bucket. Afuera los
  -- formatos que pueden traer macros (.xls, .xlsm, .docm, .pptm y OpenDocument).
  select b.public = false and b.file_size_limit = 20971520
         and b.allowed_mime_types @> array['application/pdf', 'image/png', 'image/jpeg', 'text/csv', 'text/plain',
           'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
         and not (b.allowed_mime_types && array['application/zip', 'application/x-zip-compressed', 'image/svg+xml',
           'text/html', 'application/vnd.ms-excel.sheet.macroEnabled.12',
           'application/vnd.ms-word.document.macroEnabled.12',
           'application/vnd.ms-powerpoint.presentation.macroEnabled.12', 'application/x-msdownload',
           'application/vnd.ms-excel', 'application/vnd.oasis.opendocument.spreadsheet',
           'application/vnd.oasis.opendocument.text', 'application/vnd.oasis.opendocument.presentation'])
    into v_ok from storage.buckets b where b.id = 'campus-materiales';
  if coalesce(v_ok, false) then r := r || 'bucket.privado_20mb_sin_macros_zip_svg_html=ok '; else r := r || 'bucket.privado_20mb_sin_macros_zip_svg_html=MAL '; fallas := fallas + 1; end if;

  insert into public.campus_lesson_resources (lesson_id, label, url)
    values (v_lh, '{"es":"Link"}', 'https://example.com/link') returning id into v_rx;
  if (select kind from public.campus_lesson_resources where id = v_rx) = 'link' then r := r || 'datos.link_como_antes=ok '; else r := r || 'datos.link_como_antes=MAL '; fallas := fallas + 1; end if;
  delete from public.campus_lesson_resources where id = v_rx;
  insert into public.campus_lesson_resources (lesson_id, label, kind, storage_path, file_name, file_size, mime_type)
    values (v_lh, '{"es":"Grande"}', 'file', format('%s/%s.pdf', v_lh, gen_random_uuid()), 'grande.pdf', 20971520,
      'application/pdf') returning id into v_rx;
  r := r || 'datos.acepta_20_mb=ok ';
  delete from public.campus_lesson_resources where id = v_rx;

  begin
    insert into public.campus_lesson_resources (lesson_id, label, kind) values (v_lh, '{"es":"x"}', 'link');
    r := r || 'datos.link_sin_url=MAL '; fallas := fallas + 1;
  exception when check_violation then r := r || 'datos.link_sin_url=ok ';
  end;
  begin
    insert into public.campus_lesson_resources (lesson_id, label, kind, file_name, file_size, mime_type)
      values (v_lh, '{"es":"x"}', 'file', 'a.pdf', 10, 'application/pdf');
    r := r || 'datos.archivo_sin_ruta=MAL '; fallas := fallas + 1;
  exception when check_violation then r := r || 'datos.archivo_sin_ruta=ok ';
  end;
  begin
    insert into public.campus_lesson_resources (lesson_id, label, kind, url, storage_path, file_name, file_size, mime_type)
      values (v_lh, '{"es":"x"}', 'file', 'https://example.com/a.pdf', format('%s/%s.pdf', v_lh, gen_random_uuid()),
        'a.pdf', 10, 'application/pdf');
    r := r || 'datos.archivo_con_link=MAL '; fallas := fallas + 1;
  exception when check_violation then r := r || 'datos.archivo_con_link=ok ';
  end;
  begin
    insert into public.campus_lesson_resources (lesson_id, label, kind, storage_path, file_name, file_size, mime_type)
      values (v_lh, '{"es":"x"}', 'file', 'cursos/plantilla.pdf', 'a.pdf', 10, 'application/pdf');
    r := r || 'datos.ruta_con_formato=MAL '; fallas := fallas + 1;
  exception when check_violation then r := r || 'datos.ruta_con_formato=ok ';
  end;
  begin
    insert into public.campus_lesson_resources (lesson_id, label, kind, storage_path, file_name, file_size, mime_type)
      values (v_lh, '{"es":"x"}', 'file', format('%s/%s.zip', v_lh, gen_random_uuid()), 'a.zip', 10, 'application/pdf');
    r := r || 'datos.sin_zip=MAL '; fallas := fallas + 1;
  exception when check_violation then r := r || 'datos.sin_zip=ok ';
  end;
  begin
    insert into public.campus_lesson_resources (lesson_id, label, kind, storage_path, file_name, file_size, mime_type)
      values (v_lh, '{"es":"x"}', 'file', upper(format('%s/%s.pdf', v_lh, gen_random_uuid())), 'a.pdf', 10, 'application/pdf');
    r := r || 'datos.ruta_en_minusculas=MAL '; fallas := fallas + 1;
  exception when check_violation then r := r || 'datos.ruta_en_minusculas=ok ';
  end;
  begin
    insert into public.campus_lesson_resources (lesson_id, label, kind, storage_path, file_name, file_size, mime_type)
      values (v_lh, '{"es":"x"}', 'file', format('%s/%s.pdf', v_lh, gen_random_uuid()), 'a.pdf', 20971521, 'application/pdf');
    r := r || 'datos.hasta_20_mb=MAL '; fallas := fallas + 1;
  exception when check_violation then r := r || 'datos.hasta_20_mb=ok ';
  end;
  begin
    insert into public.campus_lesson_resources (lesson_id, label, kind, storage_path, file_name, file_size, mime_type)
      values (v_lh, '{"es":"x"}', 'file', format('%s/%s.pdf', v_lh, gen_random_uuid()), 'a.pdf', 10, 'application/zip');
    r := r || 'datos.tipo_permitido=MAL '; fallas := fallas + 1;
  exception when check_violation then r := r || 'datos.tipo_permitido=ok ';
  end;
  begin
    insert into public.campus_lesson_resources (lesson_id, label, kind, storage_path, file_name, file_size, mime_type)
      values (v_lh, '{"es":"x"}', 'file', format('%s/%s.pdf', v_lh, gen_random_uuid()), 'carpeta/a.pdf', 10, 'application/pdf');
    r := r || 'datos.nombre_sin_barras=MAL '; fallas := fallas + 1;
  exception when check_violation then r := r || 'datos.nombre_sin_barras=ok ';
  end;
  begin
    insert into public.campus_lesson_resources (lesson_id, label, kind, storage_path, file_name, file_size, mime_type)
      values (v_lh, '{"es":"x"}', 'file', v_p1, 'otra.pdf', 10, 'application/pdf');
    r := r || 'datos.un_archivo_un_material=MAL '; fallas := fallas + 1;
  exception when unique_violation then r := r || 'datos.un_archivo_un_material=ok ';
  end;

  -- 2. Archivos según cada cuenta. Lo que puede bajar un alumno lo responde campus_material_file (lo
  -- pregunta la Edge Function campus-material antes de firmar). Ningún alumno lee storage.objects:
  -- Storage firma un link solo si la cuenta puede leer el archivo, así que un alumno no puede pedir
  -- links por su cuenta (con la duración que quiera).
  -- Suscripción anual: los archivos de las clases publicadas de los cursos publicados, también el regalo.
  perform set_config('request.jwt.claims', json_build_object('sub', v_plan, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select coalesce(array_agg(x.path), '{}') into v_t from unnest(v_paths) as x (path)
  where public.campus_material_file(x.path) is not null;
  if v_t @> v_all4 and v_t <@ v_all4 then r := r || 'anual.baja_archivos=ok '; else r := r || 'anual.baja_archivos=MAL '; fallas := fallas + 1; end if;
  if public.campus_material_file(v_p1) = 'guia.pdf' and public.campus_material_file(v_pg) = 'regalo.png'
     and public.campus_material_file(format('%s/%s.pdf', v_l1, gen_random_uuid())) is null
     and public.campus_material_file(null) is null then
    r := r || 'anual.nombre_para_la_descarga=ok ';
  else
    r := r || 'anual.nombre_para_la_descarga=MAL '; fallas := fallas + 1;
  end if;
  select count(*) into v_n from storage.objects o where o.bucket_id = 'campus-materiales' and o.name = any (v_paths);
  if v_n = 0 then r := r || 'anual.no_lee_el_bucket_ni_firma_links=ok '; else r := r || 'anual.no_lee_el_bucket_ni_firma_links=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lesson_resources
  where id in (v_r1, v_r3, v_r5, v_rg) and kind = 'file' and storage_path is not null and file_name is not null;
  if v_n = 4 then r := r || 'anual.ve_materiales_archivo=ok '; else r := r || 'anual.ve_materiales_archivo=MAL '; fallas := fallas + 1; end if;
  if campus_private.can_read_material(v_p1) and not campus_private.can_read_material(v_ph)
     and not campus_private.can_read_material(v_p4) and not campus_private.can_read_material(v_p_old) then
    r := r || 'anual.can_read_material=ok ';
  else
    r := r || 'anual.can_read_material=MAL '; fallas := fallas + 1;
  end if;
  begin
    insert into storage.objects (bucket_id, name) values ('campus-materiales', v_p_up);
    r := r || 'anual.no_sube_archivos=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anual.no_sube_archivos=ok ';
  end;
  update storage.objects set metadata = '{"size": 1}' where bucket_id = 'campus-materiales' and name = v_p1;
  get diagnostics v_n = row_count;
  if v_n = 0 then r := r || 'anual.no_cambia_archivos=ok '; else r := r || 'anual.no_cambia_archivos=MAL '; fallas := fallas + 1; end if;
  begin
    insert into public.campus_lesson_resources (lesson_id, label, url) values (v_l1, '{"es":"x"}', 'https://example.com/x');
    r := r || 'anual.no_crea_materiales=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anual.no_crea_materiales=ok ';
  end;
  execute 'reset role';

  -- Máster suelto del primer Máster: solo los archivos de ese Máster, publicados. Tampoco lee el bucket.
  perform set_config('request.jwt.claims', json_build_object('sub', v_master, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select coalesce(array_agg(x.path), '{}') into v_t from unnest(v_paths) as x (path)
  where public.campus_material_file(x.path) is not null;
  select count(*) into v_n from storage.objects o where o.bucket_id = 'campus-materiales' and o.name = any (v_paths);
  if v_t @> array[v_p1, v_p3] and v_t <@ array[v_p1, v_p3] and v_n = 0 then r := r || 'master.baja_solo_su_master=ok '; else r := r || 'master.baja_solo_su_master=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- Máster suelto del segundo Máster: solo el archivo de c2.
  perform set_config('request.jwt.claims', json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select coalesce(array_agg(x.path), '{}') into v_t from unnest(v_paths) as x (path)
  where public.campus_material_file(x.path) is not null;
  select count(*) into v_n from storage.objects o where o.bucket_id = 'campus-materiales' and o.name = any (v_paths);
  if v_t = array[v_p5] and v_n = 0 then r := r || 'otro_master.baja_solo_el_suyo=ok '; else r := r || 'otro_master.baja_solo_el_suyo=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- Baja vigente: igual que la anual hasta el fin del año pagado.
  perform set_config('request.jwt.claims', json_build_object('sub', v_cancel_ok, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select coalesce(array_agg(x.path), '{}') into v_t from unnest(v_paths) as x (path)
  where public.campus_material_file(x.path) is not null;
  select count(*) into v_n from storage.objects o where o.bucket_id = 'campus-materiales' and o.name = any (v_paths);
  if v_t @> v_all4 and v_t <@ v_all4 and v_n = 0 then r := r || 'baja_vigente.baja_archivos=ok '; else r := r || 'baja_vigente.baja_archivos=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- Baja vencida, vencida, reembolsada y cuenta sin persona en el CRM: ningún archivo.
  for v_rec in
    select * from (values
      ('baja_vencida', v_cancel_old), ('vencida', v_expired), ('reembolsada', v_refund), ('sin_crm', v_none)
    ) as t (chk, uid)
  loop
    perform set_config('request.jwt.claims', json_build_object('sub', v_rec.uid, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select (select count(*) from unnest(v_paths) as x (path) where public.campus_material_file(x.path) is not null)
         + (select count(*) from storage.objects o where o.bucket_id = 'campus-materiales' and o.name = any (v_paths))
      into v_n;
    if v_n = 0 then r := r || v_rec.chk || '.sin_archivos=ok '; else r := r || v_rec.chk || '.sin_archivos=MAL '; fallas := fallas + 1; end if;
    execute 'reset role';
  end loop;

  -- Accesos manuales (con la 20261010120200): el permanente baja; el quitado y el vencido, no.
  if v_grants then
    perform set_config('request.jwt.claims', json_build_object('sub', v_g_perm, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select coalesce(array_agg(x.path), '{}') into v_t from unnest(v_paths) as x (path)
    where public.campus_material_file(x.path) is not null;
    select count(*) into v_n from storage.objects o where o.bucket_id = 'campus-materiales' and o.name = any (v_paths);
    if v_t @> v_all4 and v_t <@ v_all4 and v_n = 0 then r := r || 'manual_permanente.baja_archivos=ok '; else r := r || 'manual_permanente.baja_archivos=MAL '; fallas := fallas + 1; end if;
    execute 'reset role';
    for v_rec in select * from (values ('manual_quitado', v_g_rev), ('manual_vencido', v_g_old)) as t (chk, uid)
    loop
      perform set_config('request.jwt.claims', json_build_object('sub', v_rec.uid, 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
      select (select count(*) from unnest(v_paths) as x (path) where public.campus_material_file(x.path) is not null)
           + (select count(*) from storage.objects o where o.bucket_id = 'campus-materiales' and o.name = any (v_paths))
        into v_n;
      if v_n = 0 then r := r || v_rec.chk || '.sin_archivos=ok '; else r := r || v_rec.chk || '.sin_archivos=MAL '; fallas := fallas + 1; end if;
      execute 'reset role';
    end loop;
  else
    r := r || 'manuales=omitidos(falta_20261010120200) ';
  end if;

  -- Cuenta de Núcleo: lee todos los archivos (también los sueltos y los de borradores), sube, cambia y
  -- borra (con la API). Solo con rutas <id de la clase>/<uuid>.<extensión permitida>.
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select coalesce(array_agg(o.name), '{}') into v_t from storage.objects o
  where o.bucket_id = 'campus-materiales' and o.name = any (v_paths);
  if v_t @> v_paths and v_t <@ v_paths then r := r || 'nucleo.lee_todos_los_archivos=ok '; else r := r || 'nucleo.lee_todos_los_archivos=MAL '; fallas := fallas + 1; end if;
  -- En el Campus, la cuenta de Núcleo también baja los de clases y cursos sin publicar.
  if public.campus_material_file(v_p4) = 'documento.docx' and public.campus_material_file(v_ph) = 'sin-publicar.pdf' then
    r := r || 'nucleo.baja_sin_publicar_desde_el_campus=ok ';
  else
    r := r || 'nucleo.baja_sin_publicar_desde_el_campus=MAL '; fallas := fallas + 1;
  end if;
  begin
    insert into storage.objects (bucket_id, name, owner) values ('campus-materiales', v_p_up, v_admin);
    r := r || 'nucleo.sube_archivo=ok ';
  exception when insufficient_privilege then r := r || 'nucleo.sube_archivo=MAL '; fallas := fallas + 1;
  end;
  begin
    insert into storage.objects (bucket_id, name, owner) values ('campus-materiales', 'plantilla-suelta.pdf', v_admin);
    r := r || 'nucleo.no_sube_sin_ruta=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'nucleo.no_sube_sin_ruta=ok ';
  end;
  begin
    insert into storage.objects (bucket_id, name, owner)
      values ('campus-materiales', format('%s/%s.html', v_l1, gen_random_uuid()), v_admin);
    r := r || 'nucleo.no_sube_html=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'nucleo.no_sube_html=ok ';
  end;
  update storage.objects set metadata = '{"size": 2}' where bucket_id = 'campus-materiales' and name = v_p_up;
  get diagnostics v_n = row_count;
  if v_n = 1 then r := r || 'nucleo.cambia_archivo=ok '; else r := r || 'nucleo.cambia_archivo=MAL '; fallas := fallas + 1; end if;
  begin
    update storage.objects set name = 'otra-carpeta/archivo.pdf' where bucket_id = 'campus-materiales' and name = v_p_up;
    r := r || 'nucleo.no_mueve_fuera_de_formato=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'nucleo.no_mueve_fuera_de_formato=ok ';
  end;
  -- Desde SQL no se borran archivos (trigger de Supabase): por eso existe campus_storage_orphans().
  begin
    delete from storage.objects where bucket_id = 'campus-materiales' and name = v_p_up;
    r := r || 'nucleo.sql_no_borra_archivos=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'nucleo.sql_no_borra_archivos=ok ';
  end;
  execute 'reset role';

  -- Borrar como lo hace la API de Storage (con storage.allow_delete_query): el alumno no borra nada,
  -- Núcleo sí.
  perform set_config('storage.allow_delete_query', 'true', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_plan, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  delete from storage.objects where bucket_id = 'campus-materiales' and name in (v_p1, v_p_up);
  get diagnostics v_n = row_count;
  if v_n = 0 then r := r || 'anual.no_borra_archivos=ok '; else r := r || 'anual.no_borra_archivos=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  delete from storage.objects where bucket_id = 'campus-materiales' and name = v_p_up;
  get diagnostics v_n = row_count;
  if v_n = 1 then r := r || 'nucleo.borra_con_la_api=ok '; else r := r || 'nucleo.borra_con_la_api=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';
  perform set_config('storage.allow_delete_query', 'false', true);

  -- Visitante sin sesión: ningún archivo, no sube nada y no llega a las funciones internas.
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  select count(*) into v_n from storage.objects o where o.bucket_id = 'campus-materiales';
  if v_n = 0 then r := r || 'anon.sin_archivos=ok '; else r := r || 'anon.sin_archivos=MAL '; fallas := fallas + 1; end if;
  begin
    insert into storage.objects (bucket_id, name) values ('campus-materiales', format('%s/%s.pdf', v_l1, gen_random_uuid()));
    r := r || 'anon.no_sube=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.no_sube=ok ';
  end;
  begin
    perform campus_private.can_read_material(v_p1);
    r := r || 'anon.sin_funciones_internas=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.sin_funciones_internas=ok ';
  end;
  begin
    perform public.campus_material_file(v_p1);
    r := r || 'anon.no_pide_archivos=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.no_pide_archivos=ok ';
  end;
  execute 'reset role';

  -- 3. Borrador de c1. Pasa L3 a un módulo nuevo (con su progreso), borra el módulo B (y L4), borra L2,
  -- borra el archivo de L3, suma una clase con un archivo nuevo, pasa el link de L1 a la clase nueva y
  -- cambia los datos del curso.
  v_base := jsonb_build_object(
    'course', jsonb_build_object(
      'title', '{"es":"Curso 1 nuevo","en":"Course 1 new"}'::jsonb,
      'summary', '{"es":"Resumen nuevo"}'::jsonb,
      'master_id', v_m1,
      'slug', 'prueba-bm-curso-1-nuevo'),
    'modules', jsonb_build_array(
      jsonb_build_object('id', v_mn, 'title', '{"es":"Módulo nuevo"}'::jsonb, 'lessons', jsonb_build_array(
        jsonb_build_object('id', v_l3, 'title', '{"es":"L3 movida"}'::jsonb, 'body', '{"es":"Texto de L3"}'::jsonb,
          'youtube_id', 'bbbbbbbbbbb', 'duration_seconds', 420, 'published', true, 'resources', '[]'::jsonb),
        jsonb_build_object('id', v_ln, 'title', '{"es":"Clase nueva","pt":"Aula nova"}'::jsonb, 'body', null,
          'youtube_id', null, 'duration_seconds', null, 'published', true, 'resources', jsonb_build_array(
            jsonb_build_object('id', v_rn, 'label', '{"es":"Planilla nueva"}'::jsonb, 'kind', 'file', 'url', null,
              'storage_path', v_pn, 'file_name', 'planilla-nueva.xlsx', 'file_size', 2048,
              'mime_type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
            jsonb_build_object('id', v_r2, 'label', '{"es":"Plantilla en Canva"}'::jsonb, 'kind', 'link',
              'url', 'https://example.com/plantilla', 'storage_path', null, 'file_name', null, 'file_size', null,
              'mime_type', null))))),
      jsonb_build_object('id', v_ma, 'title', '{"es":"Módulo A, segunda versión"}'::jsonb, 'lessons', jsonb_build_array(
        jsonb_build_object('id', v_l1, 'title', '{"es":"L1"}'::jsonb, 'body', '{}'::jsonb,
          'youtube_id', 'ccccccccccc', 'duration_seconds', 600, 'published', true, 'resources', jsonb_build_array(
            jsonb_build_object('id', v_r1, 'label', '{"es":"Guía"}'::jsonb, 'kind', 'file', 'url', null,
              'storage_path', v_p1, 'file_name', 'guia.pdf', 'file_size', 1000, 'mime_type', 'application/pdf')))))));

  -- c2: su contenido de hoy más un archivo que solo está en el borrador.
  v_c2_draft := jsonb_build_object(
    'course', jsonb_build_object('title', '{"es":"Curso 2"}'::jsonb, 'summary', '{}'::jsonb, 'master_id', v_m2,
      'slug', 'prueba-bm-curso-2'),
    'modules', jsonb_build_array(
      jsonb_build_object('id', v_mc2, 'title', '{"es":"M"}'::jsonb, 'lessons', jsonb_build_array(
        jsonb_build_object('id', v_l5, 'title', '{"es":"L5"}'::jsonb, 'published', true, 'resources', jsonb_build_array(
          jsonb_build_object('id', v_r5, 'label', '{"es":"PDF"}'::jsonb, 'kind', 'file', 'storage_path', v_p5,
            'file_name', 'curso-2.pdf', 'file_size', 4000, 'mime_type', 'application/pdf'),
          jsonb_build_object('id', gen_random_uuid(), 'label', '{"es":"Datos"}'::jsonb, 'kind', 'file',
            'storage_path', v_p_draft, 'file_name', 'datos.csv', 'file_size', 100, 'mime_type', 'text/csv')))))));

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  -- Forma del borrador: cada error dice dónde está.
  for v_rec in
    select * from (values
      ('no_es_objeto', '[]'::jsonb, 'El borrador no tiene el formato esperado'),
      ('dato_de_mas', v_base || '{"extra": true}', 'El borrador trae un dato que no corresponde ("extra")'),
      ('sin_espanol', jsonb_set(v_base, '{course,title}', '{"en":"Only English"}'), 'Datos del curso: el nombre falta en español'),
      ('idioma_desconocido', jsonb_set(v_base, '{modules,0,title}', '{"es":"x","fr":"x"}'), 'Módulo 1: el nombre solo puede estar en español'),
      ('direccion', jsonb_set(v_base, '{course,slug}', '"Curso 1"'), 'Datos del curso: la dirección solo puede'),
      ('sin_master', v_base #- '{course,master_id}', 'Datos del curso: falta elegir el Máster'),
      ('modulo_sin_id', jsonb_set(v_base, '{modules,0,id}', '"no-es-un-id"'), 'Módulo 1: falta el identificador'),
      ('video', jsonb_set(v_base, '{modules,0,lessons,1,youtube_id}', '"https://youtu.be/aaaaaaaaaaa"'), 'Módulo 1, clase 2: el video'),
      ('duracion', jsonb_set(v_base, '{modules,1,lessons,0,duration_seconds}', '90000'), 'Módulo 2, clase 1: la duración'),
      ('sin_published', v_base #- '{modules,1,lessons,0,published}', 'Módulo 2, clase 1: falta indicar si la ven los alumnos'),
      ('ruta_vacia', jsonb_set(v_base, '{modules,0,lessons,1,resources,0,storage_path}', 'null'), 'Módulo 1, clase 2, material 1: la ruta del archivo no es válida'),
      ('ruta_formato', jsonb_set(v_base, '{modules,0,lessons,1,resources,0,storage_path}', '"cursos/planilla.xlsx"'), 'Módulo 1, clase 2, material 1: la ruta del archivo no es válida'),
      ('tipo_zip', jsonb_set(v_base, '{modules,0,lessons,1,resources,0,mime_type}', '"application/zip"'), 'Módulo 1, clase 2, material 1: ese tipo de archivo no se puede subir'),
      ('peso', jsonb_set(v_base, '{modules,0,lessons,1,resources,0,file_size}', '20971521'), 'Módulo 1, clase 2, material 1: el archivo tiene que pesar'),
      ('archivo_con_link', jsonb_set(v_base, '{modules,0,lessons,1,resources,0,url}', '"https://example.com/x"'), 'Módulo 1, clase 2, material 1: un archivo no lleva link'),
      ('link_http', jsonb_set(v_base, '{modules,0,lessons,1,resources,1,url}', '"http://example.com/x"'), 'Módulo 1, clase 2, material 2: el link tiene que empezar con https://'),
      ('link_con_archivo', jsonb_set(v_base, '{modules,0,lessons,1,resources,1,storage_path}', to_jsonb(v_p_old)), 'Módulo 1, clase 2, material 2: un link no lleva archivo'),
      ('tipo_material', jsonb_set(v_base, '{modules,0,lessons,1,resources,1,kind}', '"video"'), 'Módulo 1, clase 2, material 2: el tipo tiene que ser'),
      ('clase_repetida', jsonb_set(v_base, '{modules,1,lessons,0,id}', to_jsonb(v_l3)), 'Hay dos clases con el mismo identificador'),
      ('archivo_repetido', jsonb_set(v_base, '{modules,0,lessons,1,resources,0,storage_path}', to_jsonb(v_p1)), 'Dos materiales usan el mismo archivo')
    ) as t (chk, content, msg)
  loop
    begin
      perform public.campus_course_draft_save(v_c1, v_rec.content);
      r := r || 'valida.' || v_rec.chk || '=MAL '; fallas := fallas + 1;
    exception when invalid_parameter_value then
      if sqlerrm like (v_rec.msg || '%') then r := r || 'valida.' || v_rec.chk || '=ok ';
      else r := r || 'valida.' || v_rec.chk || '=MAL(' || sqlerrm || ') '; fallas := fallas + 1; end if;
    end;
  end loop;
  begin
    perform public.campus_course_draft_save(gen_random_uuid(), v_base);
    r := r || 'borrador.curso_inexistente=MAL '; fallas := fallas + 1;
  exception when no_data_found then r := r || 'borrador.curso_inexistente=ok ';
  end;
  select count(*) into v_n from public.campus_course_drafts;
  if v_n = 0 then r := r || 'borrador.invalido_no_se_guarda=ok '; else r := r || 'borrador.invalido_no_se_guarda=MAL '; fallas := fallas + 1; end if;

  -- Ids de otro curso y datos que la base rechaza al publicar. Cada intento se revierte entero.
  begin
    perform public.campus_course_draft_save(v_c1, jsonb_set(v_base, '{modules,0,id}', to_jsonb(v_mc2)));
    perform public.campus_course_publish(v_c1);
    r := r || 'publicar.rechaza_modulo_de_otro_curso=MAL '; fallas := fallas + 1;
  exception when invalid_parameter_value then
    if sqlerrm like 'Módulo 1: ese módulo es de otro curso%' then r := r || 'publicar.rechaza_modulo_de_otro_curso=ok ';
    else r := r || 'publicar.rechaza_modulo_de_otro_curso=MAL(' || sqlerrm || ') '; fallas := fallas + 1; end if;
  end;
  begin
    perform public.campus_course_draft_save(v_c1, jsonb_set(v_base, '{modules,1,lessons,0,id}', to_jsonb(v_l5)));
    perform public.campus_course_publish(v_c1);
    r := r || 'publicar.rechaza_clase_de_otro_curso=MAL '; fallas := fallas + 1;
  exception when invalid_parameter_value then
    if sqlerrm like 'Módulo 2, clase 1: esa clase es de otro curso%' then r := r || 'publicar.rechaza_clase_de_otro_curso=ok ';
    else r := r || 'publicar.rechaza_clase_de_otro_curso=MAL(' || sqlerrm || ') '; fallas := fallas + 1; end if;
  end;
  begin
    perform public.campus_course_draft_save(v_c1, jsonb_set(v_base, '{modules,1,lessons,0,resources,0,id}', to_jsonb(v_r5)));
    perform public.campus_course_publish(v_c1);
    r := r || 'publicar.rechaza_material_de_otro_curso=MAL '; fallas := fallas + 1;
  exception when invalid_parameter_value then
    if sqlerrm like 'Módulo 2, clase 1, material 1: ese material es de otro curso%' then r := r || 'publicar.rechaza_material_de_otro_curso=ok ';
    else r := r || 'publicar.rechaza_material_de_otro_curso=MAL(' || sqlerrm || ') '; fallas := fallas + 1; end if;
  end;
  begin
    perform public.campus_course_draft_save(v_c1, jsonb_set(v_base, '{modules,1,lessons,0,resources,0,storage_path}', to_jsonb(v_p5)));
    perform public.campus_course_publish(v_c1);
    r := r || 'publicar.rechaza_archivo_de_otro_curso=MAL '; fallas := fallas + 1;
  exception when invalid_parameter_value then
    if sqlerrm like 'Módulo 2, clase 1, material 1: ese archivo ya lo usa un material de otro curso%' then r := r || 'publicar.rechaza_archivo_de_otro_curso=ok ';
    else r := r || 'publicar.rechaza_archivo_de_otro_curso=MAL(' || sqlerrm || ') '; fallas := fallas + 1; end if;
  end;
  begin
    perform public.campus_course_draft_save(v_c1, jsonb_set(v_base, '{course,slug}', '"prueba-bm-curso-2"'));
    perform public.campus_course_publish(v_c1);
    r := r || 'publicar.rechaza_direccion_repetida=MAL '; fallas := fallas + 1;
  exception when unique_violation then
    if sqlerrm like 'Datos del curso: ya hay otro curso con la dirección%' then r := r || 'publicar.rechaza_direccion_repetida=ok ';
    else r := r || 'publicar.rechaza_direccion_repetida=MAL(' || sqlerrm || ') '; fallas := fallas + 1; end if;
  end;
  begin
    perform public.campus_course_draft_save(v_c1, jsonb_set(v_base, '{course,master_id}', to_jsonb(gen_random_uuid())));
    perform public.campus_course_publish(v_c1);
    r := r || 'publicar.rechaza_master_inexistente=MAL '; fallas := fallas + 1;
  exception when invalid_parameter_value then
    if sqlerrm like 'Datos del curso: el Máster elegido no existe%' then r := r || 'publicar.rechaza_master_inexistente=ok ';
    else r := r || 'publicar.rechaza_master_inexistente=MAL(' || sqlerrm || ') '; fallas := fallas + 1; end if;
  end;
  begin
    perform public.campus_course_publish(v_gift);
    r := r || 'publicar.sin_borrador=MAL '; fallas := fallas + 1;
  exception when no_data_found then
    if sqlerrm like 'Este curso no tiene un borrador para publicar%' then r := r || 'publicar.sin_borrador=ok ';
    else r := r || 'publicar.sin_borrador=MAL(' || sqlerrm || ') '; fallas := fallas + 1; end if;
  end;
  begin
    perform public.campus_course_publish(gen_random_uuid());
    r := r || 'publicar.curso_inexistente=MAL '; fallas := fallas + 1;
  exception when no_data_found then r := r || 'publicar.curso_inexistente=ok ';
  end;
  execute 'reset role';
  select (select count(*) from public.campus_modules where id = v_mc2 and course_id = v_c2) = 1
     and (select module_id from public.campus_lessons where id = v_l5) = v_mc2
     and (select lesson_id from public.campus_lesson_resources where id = v_r5 and storage_path = v_p5) = v_l5
     and (select slug from public.campus_courses where id = v_c1) = 'prueba-bm-curso-1'
     and not exists (select 1 from public.campus_course_drafts)
    into v_ok;
  if v_ok then r := r || 'publicar.rechazos_no_tocan_nada=ok '; else r := r || 'publicar.rechazos_no_tocan_nada=MAL '; fallas := fallas + 1; end if;

  -- "Guardar como borrador": guarda quién y cuándo, y no cambia lo que ven los alumnos.
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_ts := public.campus_course_draft_save(v_c1, v_base);
  select d.updated_at = v_ts and d.updated_by = v_admin and d.updated_by_email = v_admin_email and d.content = v_base
    into v_ok from public.campus_course_drafts d where d.course_id = v_c1;
  if coalesce(v_ok, false) then r := r || 'borrador.guarda=ok '; else r := r || 'borrador.guarda=MAL '; fallas := fallas + 1; end if;
  v_ts2 := public.campus_course_draft_save(v_c1, v_base);
  select count(*) into v_n from public.campus_course_drafts where course_id = v_c1;
  if v_n = 1 and v_ts2 is not null then r := r || 'borrador.guardar_de_nuevo_reemplaza=ok '; else r := r || 'borrador.guardar_de_nuevo_reemplaza=MAL '; fallas := fallas + 1; end if;
  perform public.campus_course_draft_save(v_c2, v_c2_draft);
  select count(*) into v_n from public.campus_course_drafts where course_id in (v_c1, v_c2);
  if v_n = 2 then r := r || 'nucleo.lee_borradores=ok '; else r := r || 'nucleo.lee_borradores=MAL '; fallas := fallas + 1; end if;
  select (select c.slug from public.campus_courses c where c.id = v_c1) = 'prueba-bm-curso-1'
     and (select l.module_id from public.campus_lessons l where l.id = v_l3) = v_mb
     and not exists (select 1 from public.campus_modules m where m.id = v_mn)
     and not exists (select 1 from public.campus_lessons l where l.id = v_ln)
    into v_ok;
  if v_ok then r := r || 'borrador.no_cambia_lo_publicado=ok '; else r := r || 'borrador.no_cambia_lo_publicado=MAL '; fallas := fallas + 1; end if;
  -- Archivos sueltos: solo el que no usa nadie y tiene más de 24 horas (los de borradores no).
  select coalesce(array_agg(x), '{}') into v_t from public.campus_storage_orphans() x where x = any (v_paths);
  if v_t = array[v_p_old] then r := r || 'limpieza.respeta_borradores_y_24h=ok '; else r := r || 'limpieza.respeta_borradores_y_24h=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- Alumno con suscripción anual: no ve borradores ni sus archivos y no usa ninguna función de Núcleo.
  perform set_config('request.jwt.claims', json_build_object('sub', v_plan, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from public.campus_course_drafts;
  if v_n = 0 then r := r || 'anual.no_lee_borradores=ok '; else r := r || 'anual.no_lee_borradores=MAL '; fallas := fallas + 1; end if;
  select (select count(*) from unnest(array[v_pn, v_p_draft]) as x (path) where public.campus_material_file(x.path) is not null)
       + (select count(*) from storage.objects o where o.bucket_id = 'campus-materiales' and o.name in (v_pn, v_p_draft))
    into v_n;
  if v_n = 0 then r := r || 'anual.no_baja_archivos_de_borradores=ok '; else r := r || 'anual.no_baja_archivos_de_borradores=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lessons l join public.campus_modules m on m.id = l.module_id where m.course_id = v_c1;
  if v_n = 3 then r := r || 'anual.ve_lo_publicado=ok '; else r := r || 'anual.ve_lo_publicado=MAL '; fallas := fallas + 1; end if;
  begin
    insert into public.campus_course_drafts (course_id, content) values (v_gift, v_base);
    r := r || 'anual.no_escribe_borradores=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anual.no_escribe_borradores=ok ';
  end;
  update public.campus_courses set published = false where id = v_c1;
  get diagnostics v_n = row_count;
  if v_n = 0 then r := r || 'anual.no_edita_cursos=ok '; else r := r || 'anual.no_edita_cursos=MAL '; fallas := fallas + 1; end if;
  begin
    perform public.campus_course_draft_save(v_c1, v_base);
    r := r || 'anual.no_guarda_borrador=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anual.no_guarda_borrador=ok ';
  end;
  begin
    perform public.campus_course_publish(v_c1);
    r := r || 'anual.no_publica=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anual.no_publica=ok ';
  end;
  begin
    perform public.campus_course_discard_draft(v_c1);
    r := r || 'anual.no_descarta=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anual.no_descarta=ok ';
  end;
  begin
    perform public.campus_course_unpublish(v_c1);
    r := r || 'anual.no_despublica=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anual.no_despublica=ok ';
  end;
  begin
    perform public.campus_order_courses(array[v_c2, v_c1]);
    r := r || 'anual.no_ordena=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anual.no_ordena=ok ';
  end;
  begin
    perform * from public.campus_storage_orphans();
    r := r || 'anual.no_lista_sueltos=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anual.no_lista_sueltos=ok ';
  end;
  execute 'reset role';
  select count(*) into v_n from public.campus_course_drafts where course_id = v_c1 and content = v_base;
  if v_n = 1 and (select published from public.campus_courses where id = v_c1) then
    r := r || 'anual.intentos_sin_efecto=ok ';
  else
    r := r || 'anual.intentos_sin_efecto=MAL '; fallas := fallas + 1;
  end if;

  -- "Publicar cambios": aplica el borrador entero y lo borra.
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_j := public.campus_course_publish(v_c1);
  if v_j = '{"modulos_nuevos": 1, "modulos_borrados": 1, "clases_nuevas": 1, "clases_borradas": 2,
             "materiales_nuevos": 1, "materiales_borrados": 2}'::jsonb then
    r := r || 'publicar.resumen=ok ';
  else
    r := r || 'publicar.resumen=MAL(' || coalesce(v_j::text, 'null') || ') '; fallas := fallas + 1;
  end if;
  execute 'reset role';

  select c.slug = 'prueba-bm-curso-1-nuevo' and c.title = '{"es":"Curso 1 nuevo","en":"Course 1 new"}'::jsonb
     and c.summary = '{"es":"Resumen nuevo"}'::jsonb and c.master_id = v_m1 and c.published
    into v_ok from public.campus_courses c where c.id = v_c1;
  if coalesce(v_ok, false) then r := r || 'publicar.datos_del_curso=ok '; else r := r || 'publicar.datos_del_curso=MAL '; fallas := fallas + 1; end if;
  select array_agg(format('%s:%s:%s', m.id, m.position, m.title ->> 'es') order by m.position)
         = array[format('%s:1:Módulo nuevo', v_mn), format('%s:2:Módulo A, segunda versión', v_ma)]
    into v_ok from public.campus_modules m where m.course_id = v_c1;
  if coalesce(v_ok, false) then r := r || 'publicar.modulos_en_orden_y_borrado=ok '; else r := r || 'publicar.modulos_en_orden_y_borrado=MAL '; fallas := fallas + 1; end if;
  select count(*) = 3
     and bool_and(case l.id
       when v_l3 then l.module_id = v_mn and l.position = 1 and l.title = '{"es":"L3 movida"}'::jsonb
         and l.body = '{"es":"Texto de L3"}'::jsonb and l.youtube_id = 'bbbbbbbbbbb' and l.duration_seconds = 420
       when v_ln then l.module_id = v_mn and l.position = 2 and l.title = '{"es":"Clase nueva","pt":"Aula nova"}'::jsonb
         and l.body = '{}'::jsonb and l.youtube_id is null and l.duration_seconds is null and l.published
       when v_l1 then l.module_id = v_ma and l.position = 1 and l.youtube_id = 'ccccccccccc' and l.duration_seconds = 600
       else false
     end)
    into v_ok
  from public.campus_lessons l join public.campus_modules m on m.id = l.module_id where m.course_id = v_c1;
  if coalesce(v_ok, false) then r := r || 'publicar.clases_movidas_nuevas_y_borradas=ok '; else r := r || 'publicar.clases_movidas_nuevas_y_borradas=MAL '; fallas := fallas + 1; end if;
  select count(*) = 3
     and bool_and(case x.id
       when v_r1 then x.lesson_id = v_l1 and x.position = 1 and x.kind = 'file' and x.storage_path = v_p1
       when v_rn then x.lesson_id = v_ln and x.position = 1 and x.kind = 'file' and x.storage_path = v_pn
         and x.file_name = 'planilla-nueva.xlsx' and x.file_size = 2048 and x.url is null
         and x.mime_type = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
       when v_r2 then x.lesson_id = v_ln and x.position = 2 and x.kind = 'link' and x.url = 'https://example.com/plantilla'
         and x.storage_path is null
       else false
     end)
    into v_ok
  from public.campus_lesson_resources x
  join public.campus_lessons l on l.id = x.lesson_id
  join public.campus_modules m on m.id = l.module_id
  where m.course_id = v_c1;
  if coalesce(v_ok, false) then r := r || 'publicar.materiales_movidos_nuevos_y_borrados=ok '; else r := r || 'publicar.materiales_movidos_nuevos_y_borrados=MAL '; fallas := fallas + 1; end if;
  if not exists (select 1 from public.campus_modules where id = v_mb)
     and not exists (select 1 from public.campus_lessons where id in (v_l2, v_l4))
     and not exists (select 1 from public.campus_lesson_resources where id in (v_r3, v_r4)) then
    r := r || 'publicar.borra_lo_que_no_esta=ok ';
  else
    r := r || 'publicar.borra_lo_que_no_esta=MAL '; fallas := fallas + 1;
  end if;
  select count(*) into v_n from public.campus_progress where user_id = v_master and lesson_id = v_l3;
  if v_n = 1 then r := r || 'publicar.mover_conserva_progreso=ok '; else r := r || 'publicar.mover_conserva_progreso=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_progress where user_id = v_master and lesson_id = v_l2;
  if v_n = 0 then r := r || 'publicar.clase_borrada_sin_progreso=ok '; else r := r || 'publicar.clase_borrada_sin_progreso=MAL '; fallas := fallas + 1; end if;
  if not exists (select 1 from public.campus_course_drafts where course_id = v_c1)
     and exists (select 1 from public.campus_course_drafts where course_id = v_c2) then
    r := r || 'publicar.borra_solo_su_borrador=ok ';
  else
    r := r || 'publicar.borra_solo_su_borrador=MAL '; fallas := fallas + 1;
  end if;

  -- El Máster suelto, después de publicar: sigue viendo la clase movida con su progreso, baja el archivo
  -- nuevo y deja de bajar el que se borró.
  perform set_config('request.jwt.claims', json_build_object('sub', v_master, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from public.campus_lessons where id in (v_l1, v_l3, v_ln);
  if v_n = 3 then r := r || 'master.ve_clases_publicadas=ok '; else r := r || 'master.ve_clases_publicadas=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_progress where lesson_id = v_l3;
  if v_n = 1 then r := r || 'master.conserva_su_progreso=ok '; else r := r || 'master.conserva_su_progreso=MAL '; fallas := fallas + 1; end if;
  select coalesce(array_agg(x.path), '{}') into v_t from unnest(v_paths) as x (path)
  where public.campus_material_file(x.path) is not null;
  if v_t @> array[v_p1, v_pn] and v_t <@ array[v_p1, v_pn] then r := r || 'master.archivos_tras_publicar=ok '; else r := r || 'master.archivos_tras_publicar=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- Núcleo: los archivos que quedaron sin material ya aparecen para borrar. "Descartar borrador" de c2:
  -- c2 queda igual y el archivo que solo estaba en ese borrador también aparece.
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select coalesce(array_agg(x), '{}') into v_t from public.campus_storage_orphans() x where x = any (v_paths);
  if v_t @> array[v_p_old, v_p3, v_p4] and v_t <@ array[v_p_old, v_p3, v_p4] then r := r || 'limpieza.archivos_de_materiales_borrados=ok '; else r := r || 'limpieza.archivos_de_materiales_borrados=MAL '; fallas := fallas + 1; end if;
  perform public.campus_course_discard_draft(v_c2);
  select count(*) into v_n from public.campus_course_drafts where course_id = v_c2;
  if v_n = 0 then r := r || 'descartar.borra_el_borrador=ok '; else r := r || 'descartar.borra_el_borrador=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lesson_resources where lesson_id = v_l5;
  if v_n = 1 and (select published from public.campus_courses where id = v_c2) then r := r || 'descartar.no_cambia_lo_publicado=ok '; else r := r || 'descartar.no_cambia_lo_publicado=MAL '; fallas := fallas + 1; end if;
  begin
    perform public.campus_course_discard_draft(v_c2);
    r := r || 'descartar.sin_borrador_no_falla=ok ';
  exception when others then r := r || 'descartar.sin_borrador_no_falla=MAL '; fallas := fallas + 1;
  end;
  select coalesce(array_agg(x), '{}') into v_t from public.campus_storage_orphans() x where x = any (v_paths);
  if v_t @> array[v_p_old, v_p3, v_p4, v_p_draft] and v_t <@ array[v_p_old, v_p3, v_p4, v_p_draft] then r := r || 'limpieza.archivo_de_borrador_descartado=ok '; else r := r || 'limpieza.archivo_de_borrador_descartado=MAL '; fallas := fallas + 1; end if;

  -- "Pasar a borrador": los alumnos dejan de ver el curso y sus archivos; el progreso queda.
  perform public.campus_course_unpublish(v_c1);
  if not (select published from public.campus_courses where id = v_c1) then r := r || 'despublicar.curso=ok '; else r := r || 'despublicar.curso=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from storage.objects o where o.bucket_id = 'campus-materiales' and o.name in (v_p1, v_pn);
  if v_n = 2 then r := r || 'despublicar.nucleo_sigue_leyendo=ok '; else r := r || 'despublicar.nucleo_sigue_leyendo=MAL '; fallas := fallas + 1; end if;
  begin
    perform public.campus_course_unpublish(gen_random_uuid());
    r := r || 'despublicar.curso_inexistente=MAL '; fallas := fallas + 1;
  exception when no_data_found then r := r || 'despublicar.curso_inexistente=ok ';
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', v_master, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from unnest(v_paths) as x (path) where public.campus_material_file(x.path) is not null;
  if v_n = 0 then r := r || 'despublicar.alumno_sin_archivos=ok '; else r := r || 'despublicar.alumno_sin_archivos=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_lessons where id in (v_l1, v_l3, v_ln);
  if v_n = 0 then r := r || 'despublicar.alumno_sin_clases=ok '; else r := r || 'despublicar.alumno_sin_clases=MAL '; fallas := fallas + 1; end if;
  select count(*) into v_n from public.campus_progress where lesson_id = v_l3;
  if v_n = 1 then r := r || 'despublicar.progreso_queda=ok '; else r := r || 'despublicar.progreso_queda=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- Volver a publicar sin cambios: nada nuevo ni borrado. Después, dos materiales intercambian sus
  -- archivos en una sola publicación.
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  perform public.campus_course_draft_save(v_c1, v_base);
  v_j := public.campus_course_publish(v_c1);
  if v_j = '{"modulos_nuevos": 0, "modulos_borrados": 0, "clases_nuevas": 0, "clases_borradas": 0,
             "materiales_nuevos": 0, "materiales_borrados": 0}'::jsonb
     and (select published from public.campus_courses where id = v_c1) then
    r := r || 'publicar.sin_cambios=ok ';
  else
    r := r || 'publicar.sin_cambios=MAL(' || coalesce(v_j::text, 'null') || ') '; fallas := fallas + 1;
  end if;
  v_swap := jsonb_set(v_base, '{modules,0,lessons,1,resources,0}',
    (v_base #> '{modules,0,lessons,1,resources,0}')
      || jsonb_build_object('storage_path', v_p1, 'file_name', 'guia.pdf', 'file_size', 1000, 'mime_type', 'application/pdf'));
  v_swap := jsonb_set(v_swap, '{modules,1,lessons,0,resources,0}',
    (v_base #> '{modules,1,lessons,0,resources,0}')
      || jsonb_build_object('storage_path', v_pn, 'file_name', 'planilla-nueva.xlsx', 'file_size', 2048,
           'mime_type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'));
  begin
    perform public.campus_course_draft_save(v_c1, v_swap);
    perform public.campus_course_publish(v_c1);
    if (select storage_path from public.campus_lesson_resources where id = v_r1) = v_pn
       and (select storage_path from public.campus_lesson_resources where id = v_rn) = v_p1 then
      r := r || 'publicar.intercambia_archivos=ok ';
    else
      r := r || 'publicar.intercambia_archivos=MAL '; fallas := fallas + 1;
    end if;
  exception when others then r := r || 'publicar.intercambia_archivos=MAL(' || sqlerrm || ') '; fallas := fallas + 1;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', v_master, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from unnest(array[v_p1, v_pn]) as x (path) where public.campus_material_file(x.path) is not null;
  if v_n = 2 then r := r || 'master.vuelve_a_bajar_al_republicar=ok '; else r := r || 'master.vuelve_a_bajar_al_republicar=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- 4. Orden de los cursos (en vivo) y alta directa de un curso, como hace Núcleo.
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  perform public.campus_order_courses(array[v_c2, v_gift, v_c1, v_hidden]);
  select bool_and(c.position = array_position(array[v_c2, v_gift, v_c1, v_hidden], c.id)) and count(*) = 4
    into v_ok from public.campus_courses c where c.id in (v_c1, v_c2, v_gift, v_hidden);
  if coalesce(v_ok, false) then r := r || 'orden.numera_1_a_n=ok '; else r := r || 'orden.numera_1_a_n=MAL '; fallas := fallas + 1; end if;
  perform public.campus_order_courses(array[v_c1, v_c2]);
  select (select position from public.campus_courses where id = v_c1) = 1
     and (select position from public.campus_courses where id = v_c2) = 2
     and (select position from public.campus_courses where id = v_gift) = 2
     and (select position from public.campus_courses where id = v_hidden) = 4
    into v_ok;
  if v_ok then r := r || 'orden.solo_los_recibidos=ok '; else r := r || 'orden.solo_los_recibidos=MAL '; fallas := fallas + 1; end if;
  begin
    perform public.campus_order_courses(array[v_c1, v_c2, v_c1]);
    r := r || 'orden.rechaza_repetidos=MAL '; fallas := fallas + 1;
  exception when invalid_parameter_value then r := r || 'orden.rechaza_repetidos=ok ';
  end;
  begin
    perform public.campus_order_courses(array[v_c1, null]);
    r := r || 'orden.rechaza_vacios=MAL '; fallas := fallas + 1;
  exception when invalid_parameter_value then r := r || 'orden.rechaza_vacios=ok ';
  end;
  begin
    perform public.campus_order_courses('{}'::uuid[]);
    r := r || 'orden.rechaza_lista_vacia=MAL '; fallas := fallas + 1;
  exception when invalid_parameter_value then r := r || 'orden.rechaza_lista_vacia=ok ';
  end;
  begin
    perform public.campus_order_courses(array[v_c1, gen_random_uuid()]);
    r := r || 'orden.rechaza_inexistente=MAL '; fallas := fallas + 1;
  exception when no_data_found then r := r || 'orden.rechaza_inexistente=ok ';
  end;
  select (select position from public.campus_courses where id = v_c1) = 1
     and (select position from public.campus_courses where id = v_c2) = 2
    into v_ok;
  if v_ok then r := r || 'orden.rechazo_no_cambia_nada=ok '; else r := r || 'orden.rechazo_no_cambia_nada=MAL '; fallas := fallas + 1; end if;
  insert into public.campus_courses (master_id, slug, title) values (v_m2, 'prueba-bm-curso-nuevo', '{"es":"Curso nuevo"}')
    returning published into v_ok;
  if not v_ok then r := r || 'nucleo.crea_curso_sin_publicar=ok '; else r := r || 'nucleo.crea_curso_sin_publicar=MAL '; fallas := fallas + 1; end if;
  execute 'reset role';

  -- 5. Visitante sin sesión: ninguna función de Núcleo ni los borradores.
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  begin
    perform 1 from public.campus_course_drafts;
    r := r || 'anon.sin_borradores=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.sin_borradores=ok ';
  end;
  begin
    perform public.campus_course_draft_save(v_c1, v_base);
    r := r || 'anon.no_guarda_borrador=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.no_guarda_borrador=ok ';
  end;
  begin
    perform public.campus_course_publish(v_c1);
    r := r || 'anon.no_publica=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.no_publica=ok ';
  end;
  begin
    perform public.campus_course_discard_draft(v_c1);
    r := r || 'anon.no_descarta=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.no_descarta=ok ';
  end;
  begin
    perform public.campus_course_unpublish(v_c1);
    r := r || 'anon.no_despublica=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.no_despublica=ok ';
  end;
  begin
    perform public.campus_order_courses(array[v_c1]);
    r := r || 'anon.no_ordena=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.no_ordena=ok ';
  end;
  begin
    perform * from public.campus_storage_orphans();
    r := r || 'anon.no_lista_sueltos=MAL '; fallas := fallas + 1;
  exception when insufficient_privilege then r := r || 'anon.no_lista_sueltos=ok ';
  end;
  execute 'reset role';

  raise exception 'Resultado (se revierte todo): % FALLAS: %', r, fallas;
end;
$$;
