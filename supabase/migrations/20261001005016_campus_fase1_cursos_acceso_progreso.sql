-- Campus de AVA, fase 1: cursos, módulos, lecciones, acceso por suscripción y progreso.
--
-- Comparte el proyecto con el sitio, Núcleo y el CRM. Las tablas nuevas llevan el prefijo
-- campus_ y RLS. No toca ninguna tabla existente.
--
-- Textos traducibles: jsonb con las claves es, en y pt. El español es obligatorio; si falta
-- otro idioma, el Campus muestra el español.
--
-- Acceso: lo da crm_subscriptions, a través de la persona del CRM con el mismo email que la cuenta.
--   - kind = 'plan'   → todos los cursos publicados (incluidos los de regalo, sin Máster).
--   - kind = 'master' → los cursos publicados de ese Máster.
--   - status 'activa' da acceso (el CRM la vence con 3 días de gracia); 'cancelada' da acceso
--     hasta current_period_end. 'vencida' y 'reembolsada', no.
-- Las cuentas de Núcleo (public.admins) ven todo, incluso lo no publicado, para revisar.

create schema if not exists campus_private;
revoke all on schema campus_private from public, anon;
grant usage on schema campus_private to authenticated;

-- ---------------------------------------------------------------------------
-- Ayudas
-- ---------------------------------------------------------------------------

-- Un texto traducible: objeto con es (obligatorio si p_require_es), en y pt, nada más.
create function campus_private.valid_i18n(p_value jsonb, p_require_es boolean, p_max int)
returns boolean
language sql immutable set search_path = ''
as $$
  select jsonb_typeof(p_value) = 'object'
    and not exists (select 1 from jsonb_object_keys(p_value) k where k not in ('es', 'en', 'pt'))
    and not exists (
      select 1 from jsonb_each(p_value) e
      where jsonb_typeof(e.value) <> 'string' or char_length(e.value #>> '{}') > p_max
    )
    and (not p_require_es or char_length(btrim(coalesce(p_value ->> 'es', ''))) > 0);
$$;

-- Email de la cuenta que llama, en minúsculas (el mismo formato que crm_people.email_normalized).
create function campus_private.current_email()
returns text
language sql stable security definer set search_path = ''
as $$
  select lower(btrim(u.email)) from auth.users u where u.id = auth.uid();
$$;

-- Suscripciones que hoy dan acceso a la cuenta que llama.
create function campus_private.current_subscriptions()
returns table (kind text, master_id uuid, period_end timestamptz, status text)
language sql stable security definer set search_path = ''
as $$
  select s.kind, s.master_id, s.current_period_end, s.status
  from public.crm_subscriptions s
  join public.crm_people p on p.id = s.person_id
  where p.email_normalized = campus_private.current_email()
    and (s.status = 'activa' or (s.status = 'cancelada' and now() < s.current_period_end));
$$;

create function campus_private.is_staff()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.admins a where a.user_id = auth.uid());
$$;

-- ---------------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------------

-- Traducciones de los Másteres del sitio (public.masters tiene el nombre solo en español).
create table public.campus_masters (
  master_id uuid primary key references public.masters (id) on delete cascade,
  title jsonb not null default '{}'::jsonb check (campus_private.valid_i18n(title, false, 120)),
  summary jsonb not null default '{}'::jsonb check (campus_private.valid_i18n(summary, false, 600)),
  updated_at timestamptz not null default now()
);

create table public.campus_courses (
  id uuid primary key default gen_random_uuid(),
  -- Sin Máster = curso de regalo: solo lo ve la suscripción anual.
  master_id uuid references public.masters (id) on delete restrict,
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) <= 80),
  title jsonb not null check (campus_private.valid_i18n(title, true, 160)),
  summary jsonb not null default '{}'::jsonb check (campus_private.valid_i18n(summary, false, 1000)),
  position int not null default 0,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index campus_courses_master_idx on public.campus_courses (master_id, position);

create table public.campus_modules (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.campus_courses (id) on delete cascade,
  title jsonb not null check (campus_private.valid_i18n(title, true, 160)),
  position int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index campus_modules_course_idx on public.campus_modules (course_id, position);

create table public.campus_lessons (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.campus_modules (id) on delete cascade,
  title jsonb not null check (campus_private.valid_i18n(title, true, 160)),
  -- Texto de la clase. Mismo formato que los textos del sitio: renglón vacío = párrafo,
  -- "## " = título, "- " = lista.
  body jsonb not null default '{}'::jsonb check (campus_private.valid_i18n(body, false, 20000)),
  -- Video de YouTube oculto (no listado): solo el id de 11 caracteres.
  youtube_id text check (youtube_id ~ '^[A-Za-z0-9_-]{11}$'),
  duration_seconds int check (duration_seconds between 0 and 86400),
  position int not null default 0,
  published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index campus_lessons_module_idx on public.campus_lessons (module_id, position);

-- Materiales de una clase (plantillas, PDF, planillas): links a donde estén guardados.
create table public.campus_lesson_resources (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.campus_lessons (id) on delete cascade,
  label jsonb not null check (campus_private.valid_i18n(label, true, 160)),
  url text not null check (url ~ '^https://' and char_length(url) <= 2000),
  position int not null default 0,
  created_at timestamptz not null default now()
);
create index campus_lesson_resources_lesson_idx on public.campus_lesson_resources (lesson_id, position);

-- Clases terminadas por cada cuenta.
create table public.campus_progress (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  lesson_id uuid not null references public.campus_lessons (id) on delete cascade,
  completed_at timestamptz not null default now(),
  primary key (user_id, lesson_id)
);
create index campus_progress_lesson_idx on public.campus_progress (lesson_id);

create trigger campus_masters_updated_at before update on public.campus_masters
  for each row execute function public.set_updated_at();
create trigger campus_courses_updated_at before update on public.campus_courses
  for each row execute function public.set_updated_at();
create trigger campus_modules_updated_at before update on public.campus_modules
  for each row execute function public.set_updated_at();
create trigger campus_lessons_updated_at before update on public.campus_lessons
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Acceso
-- ---------------------------------------------------------------------------

create function campus_private.has_course_access(p_course uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select campus_private.is_staff() or exists (
    select 1
    from public.campus_courses c
    join campus_private.current_subscriptions() s
      on s.kind = 'plan' or (s.kind = 'master' and s.master_id = c.master_id)
    where c.id = p_course and c.published
  );
$$;

create function campus_private.has_lesson_access(p_lesson uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.campus_lessons l
    join public.campus_modules m on m.id = l.module_id
    where l.id = p_lesson
      and (l.published or campus_private.is_staff())
      and campus_private.has_course_access(m.course_id)
  );
$$;

-- ---------------------------------------------------------------------------
-- RLS
--   - Cursos y módulos publicados: los ve cualquier cuenta con sesión (para mostrar el
--     catálogo, también lo que no incluye su plan).
--   - Clases y materiales (donde está el id del video): solo con acceso al curso.
--   - Progreso: cada cuenta lee y marca el suyo, solo en clases a las que tiene acceso.
--   - Editar contenido: solo las cuentas de Núcleo.
-- ---------------------------------------------------------------------------

alter table public.campus_masters enable row level security;
alter table public.campus_courses enable row level security;
alter table public.campus_modules enable row level security;
alter table public.campus_lessons enable row level security;
alter table public.campus_lesson_resources enable row level security;
alter table public.campus_progress enable row level security;

create policy campus_masters_read on public.campus_masters
  for select to authenticated using (true);
create policy campus_masters_admin on public.campus_masters
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

create policy campus_courses_read on public.campus_courses
  for select to authenticated using (published or (select campus_private.is_staff()));
create policy campus_courses_admin on public.campus_courses
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

create policy campus_modules_read on public.campus_modules
  for select to authenticated using (
    exists (
      select 1 from public.campus_courses c
      where c.id = course_id and (c.published or (select campus_private.is_staff()))
    )
  );
create policy campus_modules_admin on public.campus_modules
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

create policy campus_lessons_read on public.campus_lessons
  for select to authenticated using (campus_private.has_lesson_access(id));
create policy campus_lessons_admin on public.campus_lessons
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

create policy campus_lesson_resources_read on public.campus_lesson_resources
  for select to authenticated using (campus_private.has_lesson_access(lesson_id));
create policy campus_lesson_resources_admin on public.campus_lesson_resources
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

create policy campus_progress_read on public.campus_progress
  for select to authenticated using (user_id = (select auth.uid()));
create policy campus_progress_insert on public.campus_progress
  for insert to authenticated with check (
    user_id = (select auth.uid()) and campus_private.has_lesson_access(lesson_id)
  );
create policy campus_progress_delete on public.campus_progress
  for delete to authenticated using (user_id = (select auth.uid()));

revoke all on public.campus_masters, public.campus_courses, public.campus_modules, public.campus_lessons,
  public.campus_lesson_resources, public.campus_progress from anon;
grant select, insert, update, delete on public.campus_masters, public.campus_courses, public.campus_modules,
  public.campus_lessons, public.campus_lesson_resources to authenticated;
grant select, insert, delete on public.campus_progress to authenticated;

-- ---------------------------------------------------------------------------
-- Funciones para el Campus
-- ---------------------------------------------------------------------------

-- Quién entra y qué incluye su acceso. Solo devuelve datos de la propia cuenta.
create function public.campus_me()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'first_name', (
      select p.first_name from public.crm_people p
      where p.email_normalized = campus_private.current_email()
    ),
    'is_staff', campus_private.is_staff(),
    'plan', exists (select 1 from campus_private.current_subscriptions() s where s.kind = 'plan'),
    'master_ids', coalesce(
      (select jsonb_agg(distinct s.master_id) from campus_private.current_subscriptions() s where s.kind = 'master'),
      '[]'::jsonb
    ),
    'access_until', (select max(s.period_end) from campus_private.current_subscriptions() s)
  )
  where auth.uid() is not null;
$$;

-- Cantidad de clases publicadas de cada curso (para la barra de progreso de los cursos
-- que la cuenta todavía no abrió). No expone títulos ni videos.
create function public.campus_course_lesson_counts()
returns table (course_id uuid, lessons int)
language sql stable security definer set search_path = ''
as $$
  select m.course_id, count(l.id)::int
  from public.campus_modules m
  join public.campus_courses c on c.id = m.course_id
  join public.campus_lessons l on l.module_id = m.id
  where auth.uid() is not null and c.published and l.published
  group by m.course_id;
$$;

-- Para la Edge Function campus-acceso: datos de la persona de una suscripción, solo si
-- quien llama es del equipo del CRM con permiso para gestionar suscripciones.
create function public.campus_invite_target(p_subscription uuid)
returns table (email text, first_name text, subscription_code text, status text)
language plpgsql security definer set search_path = ''
as $$
begin
  perform crm_private.crm_require(
    crm_private.crm_is_member() and crm_private.crm_has_permission('suscripciones.gestionar')
  );
  return query
    select p.email_normalized, p.first_name, s.code, s.status
    from public.crm_subscriptions s
    join public.crm_people p on p.id = s.person_id
    where s.id = p_subscription;
end;
$$;

revoke all on function public.campus_me(), public.campus_course_lesson_counts(),
  public.campus_invite_target(uuid) from public, anon;
grant execute on function public.campus_me(), public.campus_course_lesson_counts(),
  public.campus_invite_target(uuid) to authenticated;

revoke all on all functions in schema campus_private from public, anon;
grant execute on all functions in schema campus_private to authenticated;
