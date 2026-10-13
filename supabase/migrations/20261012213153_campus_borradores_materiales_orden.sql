-- Campus de AVA: borradores de cursos, materiales como archivos (Supabase Storage) y orden de los cursos.
--
-- Va entre la migración del CRM 20261010120000 y la del Campus 20261010120200, pero no depende de
-- ninguna de las dos. No crea ni modifica tablas del CRM ni del sitio. No redefine funciones de acceso
-- (current_subscriptions, has_course_access, has_lesson_access, campus_me): los archivos usan
-- has_lesson_access tal como esté, así que también quedan detrás de los accesos manuales y de la
-- contraseña inicial de la 20261010120200.
--
-- Borradores (decisión de la dueña): Núcleo carga cada curso entero en un borrador, con tres
-- acciones: "Guardar como borrador", "Publicar cambios" y "Descartar borrador". Los alumnos solo ven
-- lo publicado, que son las tablas de siempre (campus_courses, campus_modules, campus_lessons y
-- campus_lesson_resources). El borrador es un jsonb por curso:
--   { "course":  { "title": {es,en,pt}, "summary": {es,en,pt}, "master_id": uuid | null, "slug": text },
--     "modules": [ { "id": uuid, "title": {es,en,pt},
--                    "lessons": [ { "id": uuid, "title": {...}, "body": {...}, "youtube_id": text | null,
--                                   "duration_seconds": int | null, "published": bool,
--                                   "resources": [ { "id": uuid, "label": {...}, "kind": "link" | "file",
--                                                    "url": text | null, "storage_path": text | null,
--                                                    "file_name": text | null, "file_size": int | null,
--                                                    "mime_type": text | null } ] } ] } ] }
--   El orden de las listas es el orden. Los ids los genera Núcleo (crypto.randomUUID) para lo nuevo y
--   son los ids vivos para lo que ya existe: así, al publicar, una clase que cambió de módulo conserva
--   su id y el progreso de los alumnos.
--   Publicar aplica el borrador entero en una sola transacción y lo borra. Lo que no está en el
--   borrador se borra (con el progreso de esas clases). Crear un curso sigue siendo un insert directo
--   en campus_courses (nace sin publicar); el orden de los cursos se cambia en vivo, sin borrador.
--
-- Materiales como archivos: bucket privado campus-materiales, hasta 20 MB por archivo. Solo formatos
-- seguros y necesarios para las clases (decisión de la dueña, 12/10/2026): PDF, Word (.docx), Excel
-- (.xlsx), PowerPoint (.pptx), CSV, PNG, JPG y texto. Quedan afuera los formatos que pueden traer
-- macros (.xls, .xlsm, .docm, .pptm y OpenDocument), .zip, .svg, .html y los ejecutables. El bucket
-- solo compara el tipo que declara quien sube, sin mirar el contenido.
-- Ruta de cada archivo: <id de la clase>/<uuid>.<extensión>, en minúsculas. La base solo exige ese
-- formato, sin relación con la clase: en un borrador la clase puede ser nueva y todavía no existir.
-- El bucket lo leen solo las cuentas de Núcleo, que además suben, cambian y borran. Los alumnos no
-- tienen ninguna política sobre storage.objects, a propósito: con permiso de lectura, Storage les
-- firmaría links de la duración que pidieran (createSignedUrl acepta cualquier vencimiento), y un
-- link firmado no se puede anular: el archivo se seguiría bajando después de vencer o quitarse el
-- acceso. Por eso el alumno baja cada archivo con la Edge Function campus-material: le pregunta a
-- campus_material_file(ruta) con la sesión del alumno (decide la base, con la misma regla de las
-- clases) y, si puede, firma con la service_role un link de 60 segundos. Ese tope lo pone la
-- función, no el Campus. Límite que queda: durante esos 60 segundos el link sirve para cualquiera que
-- lo tenga, y un archivo ya bajado se puede reenviar.
-- Desde SQL no se pueden borrar archivos (trigger storage.protect_delete). Por eso no hay cola de
-- borrado: campus_storage_orphans() lista los archivos que ya no usa ninguna fila viva ni ningún
-- borrador y tienen más de 24 horas, y Núcleo los borra con la API de Storage. Mientras tanto ningún
-- alumno los puede bajar: sacar un material y publicar corta el acceso a su archivo enseguida (un
-- link ya entregado vence a los 60 segundos), sin esperar esa limpieza.

-- ---------------------------------------------------------------------------
-- Ayudas
-- ---------------------------------------------------------------------------

-- Tipos de archivo que se pueden subir como material. Los usa el bucket, la tabla y los borradores.
-- Sin formatos que puedan traer macros (.xls, .xlsm, .docm, .pptm, OpenDocument): ver el encabezado.
create function campus_private.material_mime_types()
returns text[]
language sql immutable set search_path = ''
as $$
  select array[
    'application/pdf',                                                           -- .pdf
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',         -- .xlsx
    'text/csv',                                                                  -- .csv
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',   -- .docx
    'application/vnd.openxmlformats-officedocument.presentationml.presentation', -- .pptx
    'image/png',                                                                 -- .png
    'image/jpeg',                                                                -- .jpg y .jpeg
    'text/plain'                                                                 -- .txt
  ]::text[];
$$;

-- Ruta de un archivo en el bucket: <uuid>/<uuid>.<extensión permitida>, todo en minúsculas.
create function campus_private.valid_material_path(p_path text)
returns boolean
language sql immutable set search_path = ''
as $$
  select p_path ~ ('^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
    || '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    || '[.](pdf|xlsx|csv|docx|pptx|png|jpg|jpeg|txt)$');
$$;

-- Nombre original del archivo, para la descarga: de 1 a 200 caracteres, sin barras ni caracteres
-- de control.
create function campus_private.valid_file_name(p_name text)
returns boolean
language sql immutable set search_path = ''
as $$
  select char_length(p_name) between 1 and 200
    and btrim(p_name) <> ''
    and strpos(p_name, '/') = 0
    and strpos(p_name, chr(92)) = 0
    and p_name !~ '[[:cntrl:]]';
$$;

-- ---------------------------------------------------------------------------
-- Materiales: link o archivo
-- ---------------------------------------------------------------------------

-- kind = 'link': url https (como hasta ahora) y nada de archivo.
-- kind = 'file': ruta, nombre, peso y tipo del archivo, sin url.
-- La ruta es única: dos materiales nunca comparten archivo. La unicidad se revisa al final de cada
-- sentencia (deferrable), así publicar puede intercambiar archivos entre dos materiales.
alter table public.campus_lesson_resources
  alter column url drop not null,
  add column kind text not null default 'link' check (kind in ('link', 'file')),
  add column storage_path text check (campus_private.valid_material_path(storage_path)),
  add column file_name text check (campus_private.valid_file_name(file_name)),
  add column file_size bigint check (file_size between 1 and 20971520),
  add column mime_type text check (mime_type = any (campus_private.material_mime_types())),
  add constraint campus_lesson_resources_storage_path_key unique (storage_path) deferrable initially immediate,
  add constraint campus_lesson_resources_kind_fields_check check (
    (kind = 'link' and url is not null
      and storage_path is null and file_name is null and file_size is null and mime_type is null)
    or (kind = 'file' and url is null
      and storage_path is not null and file_name is not null and file_size is not null and mime_type is not null)
  );

-- ---------------------------------------------------------------------------
-- Espacio de archivos (Supabase Storage)
-- ---------------------------------------------------------------------------

-- Privado: no hay links públicos. 20 MB por archivo (el plan gratis permite 50).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('campus-materiales', 'campus-materiales', false, 20971520, campus_private.material_mime_types())
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Si la cuenta que llama puede bajar un archivo: es material de una clase viva a la que tiene acceso
-- (has_lesson_access, la misma regla de las clases; con la 20261010120200 también cuentan los
-- accesos manuales y el bloqueo de la contraseña inicial). Un archivo sin fila viva (huérfano o solo
-- en un borrador) no lo baja ningún alumno.
create function campus_private.can_read_material(p_path text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.campus_lesson_resources r
    where r.storage_path = p_path
      and campus_private.has_lesson_access(r.lesson_id)
  );
$$;

-- La llama la Edge Function campus-material con la sesión del alumno, antes de firmar el link de 60
-- segundos: devuelve el nombre original del archivo (para la descarga) si la cuenta puede bajarlo
-- ahora, o null si no (sin acceso, clase o curso sin publicar, o un archivo que no es material de
-- ninguna clase viva).
create function public.campus_material_file(p_path text)
returns text
language sql stable security definer set search_path = ''
as $$
  select r.file_name
  from public.campus_lesson_resources r
  where r.storage_path = p_path
    and campus_private.can_read_material(p_path);
$$;

-- Políticas solo para este bucket y solo para cuentas de Núcleo. Nada para alumnos ni para anon: los
-- alumnos bajan con la Edge Function campus-material (ver el encabezado).
create policy campus_materiales_read on storage.objects
  for select to authenticated using (bucket_id = 'campus-materiales' and (select public.is_admin()));
create policy campus_materiales_insert on storage.objects
  for insert to authenticated with check (
    bucket_id = 'campus-materiales'
    and (select public.is_admin())
    and campus_private.valid_material_path(name)
  );
create policy campus_materiales_update on storage.objects
  for update to authenticated
  using (bucket_id = 'campus-materiales' and (select public.is_admin()))
  with check (
    bucket_id = 'campus-materiales'
    and (select public.is_admin())
    and campus_private.valid_material_path(name)
  );
create policy campus_materiales_delete on storage.objects
  for delete to authenticated using (bucket_id = 'campus-materiales' and (select public.is_admin()));

-- ---------------------------------------------------------------------------
-- Borradores de cursos
-- ---------------------------------------------------------------------------

-- Un borrador por curso. Solo lo ven y lo tocan las cuentas de Núcleo; los alumnos nunca lo leen.
create table public.campus_course_drafts (
  course_id uuid primary key references public.campus_courses (id) on delete cascade,
  content jsonb not null check (jsonb_typeof(content) = 'object'),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  updated_by_email text check (char_length(coalesce(updated_by_email, '')) <= 320)
);

comment on table public.campus_course_drafts is
  'Borrador de cada curso del Campus. Se guarda, publica y descarta con las funciones campus_course_*.';

create index campus_course_drafts_updated_by_idx on public.campus_course_drafts (updated_by);

create trigger campus_course_drafts_updated_at before update on public.campus_course_drafts
  for each row execute function public.set_updated_at();

alter table public.campus_course_drafts enable row level security;

create policy campus_course_drafts_admin on public.campus_course_drafts
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- Los privilegios por defecto del schema public le darían todo a anon y a authenticated (también
-- truncate, que no pasa por RLS): se sacan y se da solo lo que cubre la política.
revoke all on public.campus_course_drafts from public, anon, authenticated;
grant select, insert, update, delete on public.campus_course_drafts to authenticated;

-- Qué le falta a un texto traducible, en palabras (null si está bien). Mismas reglas que valid_i18n.
create function campus_private.i18n_problem(p_value jsonb, p_require_es boolean, p_max int)
returns text
language sql immutable set search_path = ''
as $$
  select case
    when p_value is null or p_value = 'null'::jsonb then
      case when p_require_es then 'falta en español' end
    when jsonb_typeof(p_value) <> 'object' then
      'no tiene el formato esperado (un texto por idioma: es, en, pt)'
    when exists (select 1 from jsonb_object_keys(p_value) k where k not in ('es', 'en', 'pt')) then
      'solo puede estar en español (es), inglés (en) y portugués (pt)'
    when exists (select 1 from jsonb_each(p_value) e where jsonb_typeof(e.value) <> 'string') then
      'tiene que ser texto en cada idioma'
    when exists (select 1 from jsonb_each(p_value) e where char_length(e.value #>> '{}') > p_max) then
      format('es demasiado largo (hasta %s caracteres por idioma)', p_max)
    when p_require_es and char_length(btrim(coalesce(p_value ->> 'es', ''))) = 0 then
      'falta en español'
  end;
$$;

-- Primera clave de un objeto que no está entre las permitidas (null si no hay ninguna).
create function campus_private.draft_unknown_key(p_obj jsonb, p_allowed text[])
returns text
language sql immutable set search_path = ''
as $$
  select k from jsonb_object_keys(p_obj) k where k <> all (p_allowed) order by k limit 1;
$$;

-- Si un valor del borrador es un uuid escrito como texto.
create function campus_private.draft_is_uuid(p_value jsonb)
returns boolean
language sql immutable set search_path = ''
as $$
  select coalesce(
    jsonb_typeof(p_value) = 'string'
      and (p_value #>> '{}') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    false);
$$;

-- Un número entero del borrador (null si no es un número entero).
create function campus_private.draft_int(p_value jsonb)
returns numeric
language sql immutable set search_path = ''
as $$
  select case when jsonb_typeof(p_value) = 'number' then
    case when (p_value #>> '{}')::numeric = trunc((p_value #>> '{}')::numeric) then (p_value #>> '{}')::numeric end
  end;
$$;

-- Revisa la forma de un borrador: estructura, tipos y tamaños, con las mismas reglas que las tablas
-- vivas. Corta en el primer problema con un mensaje que dice dónde está ("Módulo 2, clase 3: ...").
-- No mira la base: que los ids no sean de otro curso y que el Máster exista lo revisa la publicación.
create function campus_private.draft_check(p_content jsonb)
returns void
language plpgsql immutable set search_path = ''
as $$
declare
  v_course jsonb;
  v_mod jsonb;
  v_les jsonb;
  v_res jsonb;
  v_mi int;
  v_li int;
  v_ri int;
  v_at text;
  v_problem text;
  v_dup text;
  v_lessons int := 0;
begin
  if p_content is null or jsonb_typeof(p_content) <> 'object' then
    raise exception 'El borrador no tiene el formato esperado: tiene que traer "course" y "modules"'
      using errcode = '22023';
  end if;
  if octet_length(p_content::text) > 4194304 then
    raise exception 'El borrador es demasiado grande (más de 4 MB): acortá los textos o dividí el curso'
      using errcode = '22023';
  end if;
  v_problem := campus_private.draft_unknown_key(p_content, array['course', 'modules']);
  if v_problem is not null then
    raise exception 'El borrador trae un dato que no corresponde ("%")', v_problem using errcode = '22023';
  end if;

  -- Datos del curso
  v_course := p_content -> 'course';
  if jsonb_typeof(v_course) is distinct from 'object' then
    raise exception 'Faltan los datos del curso ("course")' using errcode = '22023';
  end if;
  v_problem := campus_private.draft_unknown_key(v_course, array['title', 'summary', 'master_id', 'slug']);
  if v_problem is not null then
    raise exception 'Datos del curso: trae un dato que no corresponde ("%")', v_problem using errcode = '22023';
  end if;
  v_problem := campus_private.i18n_problem(v_course -> 'title', true, 160);
  if v_problem is not null then
    raise exception 'Datos del curso: el nombre %', v_problem using errcode = '22023';
  end if;
  v_problem := campus_private.i18n_problem(v_course -> 'summary', false, 1000);
  if v_problem is not null then
    raise exception 'Datos del curso: la descripción %', v_problem using errcode = '22023';
  end if;
  if jsonb_typeof(v_course -> 'slug') is distinct from 'string'
     or not (v_course ->> 'slug' ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(v_course ->> 'slug') <= 80) then
    raise exception 'Datos del curso: la dirección solo puede tener letras minúsculas sin acentos, números y guiones (hasta 80 caracteres)'
      using errcode = '22023';
  end if;
  if not (v_course ? 'master_id') then
    raise exception 'Datos del curso: falta elegir el Máster o marcarlo como curso de regalo' using errcode = '22023';
  end if;
  if v_course -> 'master_id' <> 'null'::jsonb and not campus_private.draft_is_uuid(v_course -> 'master_id') then
    raise exception 'Datos del curso: el Máster no es válido' using errcode = '22023';
  end if;

  -- Módulos
  if jsonb_typeof(p_content -> 'modules') is distinct from 'array' then
    raise exception 'El temario tiene que ser una lista de módulos ("modules")' using errcode = '22023';
  end if;
  if jsonb_array_length(p_content -> 'modules') > 100 then
    raise exception 'El curso tiene demasiados módulos (hasta 100)' using errcode = '22023';
  end if;

  for v_mod, v_mi in
    select e.value, e.n from jsonb_array_elements(p_content -> 'modules') with ordinality as e(value, n)
  loop
    v_at := format('Módulo %s', v_mi);
    if jsonb_typeof(v_mod) <> 'object' then
      raise exception '%: no tiene el formato esperado', v_at using errcode = '22023';
    end if;
    v_problem := campus_private.draft_unknown_key(v_mod, array['id', 'title', 'lessons']);
    if v_problem is not null then
      raise exception '%: trae un dato que no corresponde ("%")', v_at, v_problem using errcode = '22023';
    end if;
    if not campus_private.draft_is_uuid(v_mod -> 'id') then
      raise exception '%: falta el identificador (id) o no es válido', v_at using errcode = '22023';
    end if;
    v_problem := campus_private.i18n_problem(v_mod -> 'title', true, 160);
    if v_problem is not null then
      raise exception '%: el nombre %', v_at, v_problem using errcode = '22023';
    end if;
    if v_mod ? 'lessons' and jsonb_typeof(v_mod -> 'lessons') <> 'array' then
      raise exception '%: las clases tienen que ser una lista', v_at using errcode = '22023';
    end if;
    if jsonb_array_length(coalesce(v_mod -> 'lessons', '[]'::jsonb)) > 200 then
      raise exception '%: tiene demasiadas clases (hasta 200)', v_at using errcode = '22023';
    end if;

    -- Clases
    for v_les, v_li in
      select e.value, e.n
      from jsonb_array_elements(coalesce(v_mod -> 'lessons', '[]'::jsonb)) with ordinality as e(value, n)
    loop
      v_lessons := v_lessons + 1;
      v_at := format('Módulo %s, clase %s', v_mi, v_li);
      if jsonb_typeof(v_les) <> 'object' then
        raise exception '%: no tiene el formato esperado', v_at using errcode = '22023';
      end if;
      v_problem := campus_private.draft_unknown_key(v_les,
        array['id', 'title', 'body', 'youtube_id', 'duration_seconds', 'published', 'resources']);
      if v_problem is not null then
        raise exception '%: trae un dato que no corresponde ("%")', v_at, v_problem using errcode = '22023';
      end if;
      if not campus_private.draft_is_uuid(v_les -> 'id') then
        raise exception '%: falta el identificador (id) o no es válido', v_at using errcode = '22023';
      end if;
      v_problem := campus_private.i18n_problem(v_les -> 'title', true, 160);
      if v_problem is not null then
        raise exception '%: el nombre %', v_at, v_problem using errcode = '22023';
      end if;
      v_problem := campus_private.i18n_problem(v_les -> 'body', false, 20000);
      if v_problem is not null then
        raise exception '%: el texto %', v_at, v_problem using errcode = '22023';
      end if;
      if coalesce(v_les -> 'youtube_id', 'null'::jsonb) <> 'null'::jsonb
         and not (jsonb_typeof(v_les -> 'youtube_id') = 'string' and v_les ->> 'youtube_id' ~ '^[A-Za-z0-9_-]{11}$') then
        raise exception '%: el video tiene que ser el código de 11 caracteres de YouTube (lo que va después de v=)', v_at
          using errcode = '22023';
      end if;
      if coalesce(v_les -> 'duration_seconds', 'null'::jsonb) <> 'null'::jsonb
         and not coalesce(campus_private.draft_int(v_les -> 'duration_seconds') between 0 and 86400, false) then
        raise exception '%: la duración tiene que ser un número entero de segundos, hasta 24 horas', v_at
          using errcode = '22023';
      end if;
      if jsonb_typeof(v_les -> 'published') is distinct from 'boolean' then
        raise exception '%: falta indicar si la ven los alumnos (published)', v_at using errcode = '22023';
      end if;
      if v_les ? 'resources' and jsonb_typeof(v_les -> 'resources') <> 'array' then
        raise exception '%: los materiales tienen que ser una lista', v_at using errcode = '22023';
      end if;
      if jsonb_array_length(coalesce(v_les -> 'resources', '[]'::jsonb)) > 30 then
        raise exception '%: tiene demasiados materiales (hasta 30)', v_at using errcode = '22023';
      end if;

      -- Materiales
      for v_res, v_ri in
        select e.value, e.n
        from jsonb_array_elements(coalesce(v_les -> 'resources', '[]'::jsonb)) with ordinality as e(value, n)
      loop
        v_at := format('Módulo %s, clase %s, material %s', v_mi, v_li, v_ri);
        if jsonb_typeof(v_res) <> 'object' then
          raise exception '%: no tiene el formato esperado', v_at using errcode = '22023';
        end if;
        v_problem := campus_private.draft_unknown_key(v_res,
          array['id', 'label', 'kind', 'url', 'storage_path', 'file_name', 'file_size', 'mime_type']);
        if v_problem is not null then
          raise exception '%: trae un dato que no corresponde ("%")', v_at, v_problem using errcode = '22023';
        end if;
        if not campus_private.draft_is_uuid(v_res -> 'id') then
          raise exception '%: falta el identificador (id) o no es válido', v_at using errcode = '22023';
        end if;
        v_problem := campus_private.i18n_problem(v_res -> 'label', true, 160);
        if v_problem is not null then
          raise exception '%: el nombre %', v_at, v_problem using errcode = '22023';
        end if;
        if jsonb_typeof(v_res -> 'kind') is distinct from 'string' or v_res ->> 'kind' not in ('link', 'file') then
          raise exception '%: el tipo tiene que ser "link" o "file"', v_at using errcode = '22023';
        end if;

        if v_res ->> 'kind' = 'link' then
          if not coalesce(jsonb_typeof(v_res -> 'url') = 'string'
                          and v_res ->> 'url' ~ '^https://' and char_length(v_res ->> 'url') <= 2000, false) then
            raise exception '%: el link tiene que empezar con https:// (hasta 2000 caracteres)', v_at using errcode = '22023';
          end if;
          if jsonb_strip_nulls(v_res) ?| array['storage_path', 'file_name', 'file_size', 'mime_type'] then
            raise exception '%: un link no lleva archivo', v_at using errcode = '22023';
          end if;
        else
          if jsonb_strip_nulls(v_res) ? 'url' then
            raise exception '%: un archivo no lleva link', v_at using errcode = '22023';
          end if;
          if not coalesce(jsonb_typeof(v_res -> 'storage_path') = 'string'
                          and campus_private.valid_material_path(v_res ->> 'storage_path'), false) then
            raise exception '%: la ruta del archivo no es válida (tiene que ser <id de la clase>/<id del archivo>.<extensión>, con una extensión permitida)', v_at
              using errcode = '22023';
          end if;
          if not coalesce(jsonb_typeof(v_res -> 'file_name') = 'string'
                          and campus_private.valid_file_name(v_res ->> 'file_name'), false) then
            raise exception '%: el nombre del archivo tiene que tener entre 1 y 200 caracteres, sin barras', v_at
              using errcode = '22023';
          end if;
          if not coalesce(campus_private.draft_int(v_res -> 'file_size') between 1 and 20971520, false) then
            raise exception '%: el archivo tiene que pesar entre 1 byte y 20 MB', v_at using errcode = '22023';
          end if;
          if not coalesce(jsonb_typeof(v_res -> 'mime_type') = 'string'
                          and (v_res ->> 'mime_type') = any (campus_private.material_mime_types()), false) then
            raise exception '%: ese tipo de archivo no se puede subir (PDF, Word, Excel, PowerPoint, CSV, PNG, JPG o texto)', v_at
              using errcode = '22023';
          end if;
        end if;
      end loop;
    end loop;
  end loop;

  if v_lessons > 500 then
    raise exception 'El curso tiene demasiadas clases (hasta 500)' using errcode = '22023';
  end if;

  -- Cada id aparece una sola vez, y cada archivo es de un solo material.
  select lower(x.value #>> '{}') into v_dup
  from jsonb_path_query(p_content, '$.modules[*].id') as x(value)
  group by 1 having count(*) > 1 limit 1;
  if v_dup is not null then
    raise exception 'Hay dos módulos con el mismo identificador (%)', v_dup using errcode = '22023';
  end if;
  select lower(x.value #>> '{}') into v_dup
  from jsonb_path_query(p_content, '$.modules[*].lessons[*].id') as x(value)
  group by 1 having count(*) > 1 limit 1;
  if v_dup is not null then
    raise exception 'Hay dos clases con el mismo identificador (%)', v_dup using errcode = '22023';
  end if;
  select lower(x.value #>> '{}') into v_dup
  from jsonb_path_query(p_content, '$.modules[*].lessons[*].resources[*].id') as x(value)
  group by 1 having count(*) > 1 limit 1;
  if v_dup is not null then
    raise exception 'Hay dos materiales con el mismo identificador (%)', v_dup using errcode = '22023';
  end if;
  select x.value #>> '{}' into v_dup
  from jsonb_path_query(p_content, '$.modules[*].lessons[*].resources[*].storage_path') as x(value)
  where jsonb_typeof(x.value) = 'string'
  group by 1 having count(*) > 1 limit 1;
  if v_dup is not null then
    raise exception 'Dos materiales usan el mismo archivo (%): subilo de nuevo en uno de los dos', v_dup
      using errcode = '22023';
  end if;
end;
$$;

-- Módulos, clases y materiales de un borrador ya revisado, en filas y con su lugar (1..n) en su lista.
-- "position" va entre comillas en returns table: es palabra clave de PostgreSQL y sin comillas no se
-- acepta como nombre de columna ahí (la migración entera daría error de sintaxis). Las referencias
-- con alias (d.position) no necesitan comillas.
create function campus_private.draft_modules(p_content jsonb)
returns table (id uuid, title jsonb, "position" int)
language sql immutable set search_path = ''
as $$
  select (mods.m ->> 'id')::uuid, mods.m -> 'title', mods.n::int
  from jsonb_array_elements(p_content -> 'modules') with ordinality as mods(m, n);
$$;

create function campus_private.draft_lessons(p_content jsonb)
returns table (id uuid, module_id uuid, title jsonb, body jsonb, youtube_id text, duration_seconds int,
  published boolean, "position" int, module_position int)
language sql immutable set search_path = ''
as $$
  select (les.l ->> 'id')::uuid, (mods.m ->> 'id')::uuid, les.l -> 'title',
         coalesce(nullif(les.l -> 'body', 'null'::jsonb), '{}'::jsonb),
         les.l ->> 'youtube_id', (les.l ->> 'duration_seconds')::numeric::int,
         (les.l ->> 'published')::boolean, les.n::int, mods.n::int
  from jsonb_array_elements(p_content -> 'modules') with ordinality as mods(m, n)
  cross join lateral jsonb_array_elements(coalesce(mods.m -> 'lessons', '[]'::jsonb)) with ordinality as les(l, n);
$$;

create function campus_private.draft_resources(p_content jsonb)
returns table (id uuid, lesson_id uuid, label jsonb, kind text, url text, storage_path text, file_name text,
  file_size bigint, mime_type text, "position" int, lesson_position int, module_position int)
language sql immutable set search_path = ''
as $$
  select (res.r ->> 'id')::uuid, (les.l ->> 'id')::uuid, res.r -> 'label', res.r ->> 'kind',
         case when res.r ->> 'kind' = 'link' then res.r ->> 'url' end,
         case when res.r ->> 'kind' = 'file' then res.r ->> 'storage_path' end,
         case when res.r ->> 'kind' = 'file' then res.r ->> 'file_name' end,
         case when res.r ->> 'kind' = 'file' then (res.r ->> 'file_size')::numeric::bigint end,
         case when res.r ->> 'kind' = 'file' then res.r ->> 'mime_type' end,
         res.n::int, les.n::int, mods.n::int
  from jsonb_array_elements(p_content -> 'modules') with ordinality as mods(m, n)
  cross join lateral jsonb_array_elements(coalesce(mods.m -> 'lessons', '[]'::jsonb)) with ordinality as les(l, n)
  cross join lateral jsonb_array_elements(coalesce(les.l -> 'resources', '[]'::jsonb)) with ordinality as res(r, n);
$$;

-- "Guardar como borrador": revisa la forma y guarda (o reemplaza) el borrador del curso. No toca lo
-- que ven los alumnos. Devuelve la hora del guardado.
create function public.campus_course_draft_save(p_course uuid, p_content jsonb)
returns timestamptz
language plpgsql security definer set search_path = ''
as $$
declare
  v_at timestamptz;
begin
  perform crm_private.crm_require(public.is_admin());
  if not exists (select 1 from public.campus_courses c where c.id = p_course) then
    raise exception 'El curso no existe' using errcode = 'P0002';
  end if;
  perform campus_private.draft_check(p_content);

  insert into public.campus_course_drafts (course_id, content, updated_at, updated_by, updated_by_email)
  values (p_course, p_content, now(), auth.uid(), campus_private.current_email())
  on conflict (course_id) do update set
    content = excluded.content,
    updated_at = excluded.updated_at,
    updated_by = excluded.updated_by,
    updated_by_email = excluded.updated_by_email
  returning updated_at into v_at;
  return v_at;
end;
$$;

-- "Descartar borrador": borra el borrador del curso. Lo publicado queda igual. Si no había, no hace nada.
create function public.campus_course_discard_draft(p_course uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  perform crm_private.crm_require(public.is_admin());
  delete from public.campus_course_drafts d where d.course_id = p_course;
end;
$$;

-- "Publicar cambios": aplica el borrador del curso en una sola transacción, publica el curso y borra
-- el borrador. Devuelve cuánto se agregó y cuánto se borró.
--   - Módulos, clases y materiales se actualizan por id. Una clase puede cambiar de módulo (dentro de
--     este curso) y un material de clase, sin perder el progreso de los alumnos.
--   - Lo que no está en el borrador se borra; las clases borradas se llevan el progreso de esas clases.
--   - El lugar de cada cosa es su posición en la lista del borrador (1..n).
--   - Un id que ya es de otro curso se rechaza: publicarlo se lo quitaría a ese curso.
-- Los archivos que quedan sin usar no se borran acá: los lista campus_storage_orphans().
create function public.campus_course_publish(p_course uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_content jsonb;
  v_course jsonb;
  v_mod_ids uuid[];
  v_les_ids uuid[];
  v_res_ids uuid[];
  v_where text;
  v_mod_new int;
  v_mod_del int;
  v_les_new int;
  v_les_del int;
  v_res_new int;
  v_res_del int;
  v_state text;
  v_constraint text;
begin
  perform crm_private.crm_require(public.is_admin());

  perform 1 from public.campus_courses c where c.id = p_course for update;
  if not found then
    raise exception 'El curso no existe' using errcode = 'P0002';
  end if;
  select d.content into v_content from public.campus_course_drafts d where d.course_id = p_course for update;
  if not found then
    raise exception 'Este curso no tiene un borrador para publicar: guardá los cambios como borrador primero'
      using errcode = 'P0002';
  end if;

  -- El borrador pudo cambiar por fuera de campus_course_draft_save: se revisa de nuevo entero.
  perform campus_private.draft_check(v_content);
  v_course := v_content -> 'course';

  if v_course ->> 'master_id' is not null
     and not exists (select 1 from public.masters ms where ms.id = (v_course ->> 'master_id')::uuid) then
    raise exception 'Datos del curso: el Máster elegido no existe. Elegí otro' using errcode = '22023';
  end if;
  if exists (select 1 from public.campus_courses c where c.slug = v_course ->> 'slug' and c.id <> p_course) then
    raise exception 'Datos del curso: ya hay otro curso con la dirección "%". Probá con otra', v_course ->> 'slug'
      using errcode = '23505';
  end if;

  select format('Módulo %s', d.position) into v_where
  from campus_private.draft_modules(v_content) d
  join public.campus_modules m on m.id = d.id
  where m.course_id <> p_course
  order by d.position limit 1;
  if v_where is not null then
    raise exception '%: ese módulo es de otro curso. Para copiarlo, creá un módulo nuevo', v_where
      using errcode = '22023';
  end if;

  select format('Módulo %s, clase %s', d.module_position, d.position) into v_where
  from campus_private.draft_lessons(v_content) d
  join public.campus_lessons l on l.id = d.id
  join public.campus_modules m on m.id = l.module_id
  where m.course_id <> p_course
  order by d.module_position, d.position limit 1;
  if v_where is not null then
    raise exception '%: esa clase es de otro curso. Para copiarla, creá una clase nueva', v_where
      using errcode = '22023';
  end if;

  select format('Módulo %s, clase %s, material %s', d.module_position, d.lesson_position, d.position) into v_where
  from campus_private.draft_resources(v_content) d
  join public.campus_lesson_resources r on r.id = d.id
  join public.campus_lessons l on l.id = r.lesson_id
  join public.campus_modules m on m.id = l.module_id
  where m.course_id <> p_course
  order by d.module_position, d.lesson_position, d.position limit 1;
  if v_where is not null then
    raise exception '%: ese material es de otro curso. Para copiarlo, creá un material nuevo', v_where
      using errcode = '22023';
  end if;

  select format('Módulo %s, clase %s, material %s', d.module_position, d.lesson_position, d.position) into v_where
  from campus_private.draft_resources(v_content) d
  join public.campus_lesson_resources r on r.storage_path = d.storage_path and r.id <> d.id
  join public.campus_lessons l on l.id = r.lesson_id
  join public.campus_modules m on m.id = l.module_id
  where m.course_id <> p_course
  order by d.module_position, d.lesson_position, d.position limit 1;
  if v_where is not null then
    raise exception '%: ese archivo ya lo usa un material de otro curso. Subilo de nuevo', v_where
      using errcode = '22023';
  end if;

  -- Resumen, antes de escribir.
  v_mod_ids := array(select d.id from campus_private.draft_modules(v_content) d);
  v_les_ids := array(select d.id from campus_private.draft_lessons(v_content) d);
  v_res_ids := array(select d.id from campus_private.draft_resources(v_content) d);

  select count(*) into v_mod_new from unnest(v_mod_ids) x(id)
  where not exists (select 1 from public.campus_modules m where m.id = x.id);
  select count(*) into v_mod_del from public.campus_modules m
  where m.course_id = p_course and m.id <> all (v_mod_ids);
  select count(*) into v_les_new from unnest(v_les_ids) x(id)
  where not exists (select 1 from public.campus_lessons l where l.id = x.id);
  select count(*) into v_les_del from public.campus_lessons l
  join public.campus_modules m on m.id = l.module_id
  where m.course_id = p_course and l.id <> all (v_les_ids);
  select count(*) into v_res_new from unnest(v_res_ids) x(id)
  where not exists (select 1 from public.campus_lesson_resources r where r.id = x.id);
  select count(*) into v_res_del from public.campus_lesson_resources r
  join public.campus_lessons l on l.id = r.lesson_id
  join public.campus_modules m on m.id = l.module_id
  where m.course_id = p_course and r.id <> all (v_res_ids);

  begin
    update public.campus_courses c set
      title = v_course -> 'title',
      summary = coalesce(nullif(v_course -> 'summary', 'null'::jsonb), '{}'::jsonb),
      master_id = (v_course ->> 'master_id')::uuid,
      slug = v_course ->> 'slug',
      published = true
    where c.id = p_course;

    -- 1. Materiales que ya no están: primero, así sus archivos quedan libres para otro material.
    delete from public.campus_lesson_resources r
    using public.campus_lessons l, public.campus_modules m
    where l.id = r.lesson_id and m.id = l.module_id and m.course_id = p_course
      and r.id <> all (v_res_ids);

    -- 2. Módulos, clases y materiales del borrador: nuevos o actualizados (solo si algo cambió).
    insert into public.campus_modules as m (id, course_id, title, position)
    select d.id, p_course, d.title, d.position from campus_private.draft_modules(v_content) d
    on conflict (id) do update set title = excluded.title, position = excluded.position
    where (m.title, m.position) is distinct from (excluded.title, excluded.position);

    insert into public.campus_lessons as l (id, module_id, title, body, youtube_id, duration_seconds, published, position)
    select d.id, d.module_id, d.title, d.body, d.youtube_id, d.duration_seconds, d.published, d.position
    from campus_private.draft_lessons(v_content) d
    on conflict (id) do update set
      module_id = excluded.module_id,
      title = excluded.title,
      body = excluded.body,
      youtube_id = excluded.youtube_id,
      duration_seconds = excluded.duration_seconds,
      published = excluded.published,
      position = excluded.position
    where (l.module_id, l.title, l.body, l.youtube_id, l.duration_seconds, l.published, l.position)
      is distinct from (excluded.module_id, excluded.title, excluded.body, excluded.youtube_id,
                        excluded.duration_seconds, excluded.published, excluded.position);

    insert into public.campus_lesson_resources as r (id, lesson_id, label, kind, url, storage_path, file_name,
      file_size, mime_type, position)
    select d.id, d.lesson_id, d.label, d.kind, d.url, d.storage_path, d.file_name, d.file_size, d.mime_type, d.position
    from campus_private.draft_resources(v_content) d
    on conflict (id) do update set
      lesson_id = excluded.lesson_id,
      label = excluded.label,
      kind = excluded.kind,
      url = excluded.url,
      storage_path = excluded.storage_path,
      file_name = excluded.file_name,
      file_size = excluded.file_size,
      mime_type = excluded.mime_type,
      position = excluded.position
    where (r.lesson_id, r.label, r.kind, r.url, r.storage_path, r.file_name, r.file_size, r.mime_type, r.position)
      is distinct from (excluded.lesson_id, excluded.label, excluded.kind, excluded.url, excluded.storage_path,
                        excluded.file_name, excluded.file_size, excluded.mime_type, excluded.position);

    -- 3. Clases y módulos que ya no están. Va al final: las clases que se mudaron ya no cuelgan de
    --    los módulos que se borran.
    delete from public.campus_lessons l
    using public.campus_modules m
    where m.id = l.module_id and m.course_id = p_course
      and l.id <> all (v_les_ids);

    delete from public.campus_modules m
    where m.course_id = p_course and m.id <> all (v_mod_ids);

    delete from public.campus_course_drafts d where d.course_id = p_course;
  exception
    when unique_violation or check_violation or foreign_key_violation or not_null_violation then
      get stacked diagnostics v_state = returned_sqlstate, v_constraint = constraint_name;
      raise exception '%', case
          when v_constraint = 'campus_courses_slug_key' then
            'Datos del curso: ya hay otro curso con esa dirección. Probá con otra'
          when v_constraint = 'campus_lesson_resources_storage_path_key' then
            'Dos materiales usan el mismo archivo: subilo de nuevo en uno de los dos'
          when v_constraint = 'campus_courses_master_id_fkey' then
            'Datos del curso: el Máster elegido no existe. Elegí otro'
          when v_state = '23505' then 'No se pudo publicar: hay un dato repetido (' || coalesce(v_constraint, '') || ')'
          when v_state = '23514' then 'No se pudo publicar: un dato no tiene el formato correcto (' || coalesce(v_constraint, '') || ')'
          when v_state = '23503' then 'No se pudo publicar: falta un dato relacionado (' || coalesce(v_constraint, '') || ')'
          else 'No se pudo publicar: falta un dato obligatorio'
        end
        using errcode = v_state;
  end;

  return jsonb_build_object(
    'modulos_nuevos', v_mod_new,
    'modulos_borrados', v_mod_del,
    'clases_nuevas', v_les_new,
    'clases_borradas', v_les_del,
    'materiales_nuevos', v_res_new,
    'materiales_borrados', v_res_del
  );
end;
$$;

-- "Pasar a borrador": los alumnos dejan de ver el curso. El progreso y el borrador (si hay) quedan.
create function public.campus_course_unpublish(p_course uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  perform crm_private.crm_require(public.is_admin());
  update public.campus_courses c set published = false where c.id = p_course;
  if not found then
    raise exception 'El curso no existe' using errcode = 'P0002';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Orden de los cursos (en vivo, sin borrador)
-- ---------------------------------------------------------------------------

-- Numera 1..n los cursos en el orden recibido, en un solo paso (todo o nada). Puede recibir todos
-- los cursos o solo los de un Máster: el Campus los ordena dentro de cada Máster.
create function public.campus_order_courses(p_ids uuid[])
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_n int;
begin
  perform crm_private.crm_require(public.is_admin());
  if coalesce(array_ndims(p_ids), 0) <> 1 then
    raise exception 'Mandá la lista de cursos en el orden nuevo' using errcode = '22023';
  end if;
  v_n := cardinality(p_ids);
  if v_n > 1000 then
    raise exception 'Demasiados cursos en un solo pedido' using errcode = '22023';
  end if;
  if array_position(p_ids, null) is not null then
    raise exception 'La lista de cursos tiene un lugar vacío' using errcode = '22023';
  end if;
  if (select count(distinct x) from unnest(p_ids) x) <> v_n then
    raise exception 'Un curso aparece dos veces en la lista' using errcode = '22023';
  end if;
  if (select count(*) from public.campus_courses c where c.id = any (p_ids)) <> v_n then
    raise exception 'Algún curso de la lista ya no existe. Recargá la página' using errcode = 'P0002';
  end if;

  update public.campus_courses c set position = o.n::int
  from unnest(p_ids) with ordinality as o(id, n)
  where c.id = o.id and c.position is distinct from o.n::int;
end;
$$;

-- ---------------------------------------------------------------------------
-- Limpieza de archivos
-- ---------------------------------------------------------------------------

-- Rutas del bucket que no usa ningún material vivo ni ningún borrador y que tienen más de 24 horas
-- (el margen cubre un archivo recién subido que todavía no se guardó en el borrador). Núcleo las
-- borra con la API de Storage: storage.from('campus-materiales').remove(rutas). El margen no deja
-- archivos al alcance de los alumnos: sin material vivo, campus_material_file ya no los entrega.
create function public.campus_storage_orphans()
returns setof text
language plpgsql security definer set search_path = ''
as $$
begin
  perform crm_private.crm_require(public.is_admin());
  return query
    with draft_paths as (
      select distinct p.value #>> '{}' as path
      from public.campus_course_drafts d
      cross join lateral jsonb_path_query(d.content, '$.modules[*].lessons[*].resources[*].storage_path') as p(value)
    )
    select o.name
    from storage.objects o
    where o.bucket_id = 'campus-materiales'
      and o.created_at < now() - interval '24 hours'
      and not exists (select 1 from public.campus_lesson_resources r where r.storage_path = o.name)
      and not exists (select 1 from draft_paths dp where dp.path = o.name)
    order by o.created_at, o.name;
end;
$$;

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------

-- Las que usan las restricciones de las tablas y las políticas (corren con la cuenta que escribe o lee).
-- can_read_material ya no está en ninguna política: queda para las pruebas y solo responde por la
-- propia cuenta.
revoke all on function campus_private.material_mime_types(), campus_private.valid_material_path(text),
  campus_private.valid_file_name(text), campus_private.can_read_material(text) from public, anon;
grant execute on function campus_private.material_mime_types(), campus_private.valid_material_path(text),
  campus_private.valid_file_name(text), campus_private.can_read_material(text) to authenticated;

-- Internas: solo las llaman las funciones de arriba (que corren como dueñas).
revoke all on function campus_private.i18n_problem(jsonb, boolean, int), campus_private.draft_unknown_key(jsonb, text[]),
  campus_private.draft_is_uuid(jsonb), campus_private.draft_int(jsonb), campus_private.draft_check(jsonb),
  campus_private.draft_modules(jsonb), campus_private.draft_lessons(jsonb), campus_private.draft_resources(jsonb)
  from public, anon, authenticated;

revoke all on function public.campus_course_draft_save(uuid, jsonb), public.campus_course_discard_draft(uuid),
  public.campus_course_publish(uuid), public.campus_course_unpublish(uuid), public.campus_order_courses(uuid[]),
  public.campus_storage_orphans(), public.campus_material_file(text) from public, anon;
grant execute on function public.campus_course_draft_save(uuid, jsonb), public.campus_course_discard_draft(uuid),
  public.campus_course_publish(uuid), public.campus_course_unpublish(uuid), public.campus_order_courses(uuid[]),
  public.campus_storage_orphans(), public.campus_material_file(text) to authenticated;
