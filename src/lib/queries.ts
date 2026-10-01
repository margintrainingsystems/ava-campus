// Consultas a la base. Las políticas RLS deciden qué llega: las clases y sus videos solo
// llegan si la cuenta tiene acceso al curso.
import type { I18nText } from '../i18n/types'
import type { CourseSummary, LessonItem, MasterInfo, Me, ModuleItem } from './catalog'
import { supabase } from './supabase'

type Row = Record<string, unknown>

function asText(value: unknown): I18nText {
  return value && typeof value === 'object' ? (value as I18nText) : {}
}

function str(value: unknown): string {
  return typeof value === 'string' ? value : ''
}

function strOrNull(value: unknown): string | null {
  return typeof value === 'string' && value !== '' ? value : null
}

function num(value: unknown, fallback = 0): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback
}

export async function loadMe(): Promise<Me> {
  const { data, error } = await supabase.rpc('campus_me')
  if (error) throw error
  const raw = (data ?? {}) as Row
  return {
    firstName: strOrNull(raw.first_name),
    isStaff: raw.is_staff === true,
    plan: raw.plan === true,
    masterIds: Array.isArray(raw.master_ids) ? raw.master_ids.filter((x): x is string => typeof x === 'string') : [],
    accessUntil: strOrNull(raw.access_until),
  }
}

export async function loadMasters(): Promise<MasterInfo[]> {
  const [masters, translations] = await Promise.all([
    supabase.from('masters').select('id, name, color_token, order_index').order('order_index'),
    supabase.from('campus_masters').select('master_id, title, summary'),
  ])
  if (masters.error) throw masters.error
  if (translations.error) throw translations.error
  const byId = new Map((translations.data as Row[]).map((t) => [str(t.master_id), t]))
  return (masters.data as Row[]).map((m) => {
    const t = byId.get(str(m.id))
    const name = str(m.name)
    return {
      id: str(m.id),
      name,
      title: { es: name, ...asText(t?.title) },
      summary: asText(t?.summary),
      colorToken: str(m.color_token) || 'accent-1',
      order: num(m.order_index),
    }
  })
}

export async function loadCourses(): Promise<CourseSummary[]> {
  const [courses, counts, progress] = await Promise.all([
    supabase.from('campus_courses').select('id, master_id, slug, title, summary, position, published').order('position'),
    supabase.rpc('campus_course_lesson_counts'),
    supabase.from('campus_progress').select('lesson_id, lesson:campus_lessons(module:campus_modules(course_id))'),
  ])
  if (courses.error) throw courses.error
  if (counts.error) throw counts.error
  if (progress.error) throw progress.error

  const totals = new Map((counts.data as Row[]).map((c) => [str(c.course_id), num(c.lessons)]))
  const done = new Map<string, number>()
  for (const p of progress.data as Row[]) {
    const lesson = p.lesson as Row | null
    const courseId = str((lesson?.module as Row | null)?.course_id)
    if (courseId) done.set(courseId, (done.get(courseId) ?? 0) + 1)
  }

  return (courses.data as Row[]).map((c) => ({
    id: str(c.id),
    masterId: strOrNull(c.master_id),
    slug: str(c.slug),
    title: asText(c.title),
    summary: asText(c.summary),
    position: num(c.position),
    published: c.published === true,
    lessonCount: totals.get(str(c.id)) ?? 0,
    doneCount: done.get(str(c.id)) ?? 0,
  }))
}

export type CourseDetail = {
  course: CourseSummary
  modules: ModuleItem[]
  done: Set<string>
}

export async function loadCourse(slug: string): Promise<CourseDetail | null> {
  const { data: courseRow, error } = await supabase
    .from('campus_courses')
    .select('id, master_id, slug, title, summary, position, published')
    .eq('slug', slug)
    .maybeSingle()
  if (error) throw error
  if (!courseRow) return null
  const c = courseRow as Row
  const courseId = str(c.id)

  const { data: moduleRows, error: modulesError } = await supabase
    .from('campus_modules')
    .select('id, title, position')
    .eq('course_id', courseId)
  if (modulesError) throw modulesError
  const moduleIds = (moduleRows as Row[]).map((m) => str(m.id))

  // Sin acceso al curso, la base no devuelve ninguna clase.
  const lessons: LessonItem[] = []
  if (moduleIds.length) {
    const { data: lessonRows, error: lessonsError } = await supabase
      .from('campus_lessons')
      .select('id, module_id, title, duration_seconds, position, published, youtube_id')
      .in('module_id', moduleIds)
    if (lessonsError) throw lessonsError
    for (const l of lessonRows as Row[]) {
      lessons.push({
        id: str(l.id),
        moduleId: str(l.module_id),
        title: asText(l.title),
        durationSeconds: typeof l.duration_seconds === 'number' ? l.duration_seconds : null,
        position: num(l.position),
        published: l.published === true,
        hasVideo: typeof l.youtube_id === 'string' && l.youtube_id !== '',
      })
    }
  }

  const done = new Set<string>()
  if (lessons.length) {
    const { data: progressRows, error: progressError } = await supabase
      .from('campus_progress')
      .select('lesson_id')
      .in(
        'lesson_id',
        lessons.map((l) => l.id),
      )
    if (progressError) throw progressError
    for (const p of progressRows as Row[]) done.add(str(p.lesson_id))
  }

  const modules: ModuleItem[] = (moduleRows as Row[]).map((m) => ({
    id: str(m.id),
    title: asText(m.title),
    position: num(m.position),
    lessons: lessons.filter((l) => l.moduleId === str(m.id)),
  }))

  return {
    course: {
      id: courseId,
      masterId: strOrNull(c.master_id),
      slug: str(c.slug),
      title: asText(c.title),
      summary: asText(c.summary),
      position: num(c.position),
      published: c.published === true,
      lessonCount: lessons.filter((l) => l.published).length,
      doneCount: lessons.filter((l) => done.has(l.id)).length,
    },
    modules,
    done,
  }
}

export type LessonResource = { id: string; label: I18nText; url: string }
export type LessonContent = { id: string; body: I18nText; youtubeId: string | null; resources: LessonResource[] }

export async function loadLessonContent(lessonId: string): Promise<LessonContent | null> {
  const { data, error } = await supabase
    .from('campus_lessons')
    .select('id, body, youtube_id, resources:campus_lesson_resources(id, label, url, position)')
    .eq('id', lessonId)
    .maybeSingle()
  if (error) throw error
  if (!data) return null
  const row = data as Row
  const resources = (Array.isArray(row.resources) ? (row.resources as Row[]) : [])
    .sort((a, b) => num(a.position) - num(b.position))
    .map((r) => ({ id: str(r.id), label: asText(r.label), url: str(r.url) }))
    // Solo links https: la base ya lo exige, esto evita mostrar cualquier otra cosa.
    .filter((r) => r.url.startsWith('https://'))
  return { id: str(row.id), body: asText(row.body), youtubeId: strOrNull(row.youtube_id), resources }
}

export async function setLessonDone(lessonId: string, done: boolean): Promise<void> {
  if (done) {
    const { error } = await supabase
      .from('campus_progress')
      .upsert({ lesson_id: lessonId }, { onConflict: 'user_id,lesson_id', ignoreDuplicates: true })
    if (error) throw error
    return
  }
  const { error } = await supabase.from('campus_progress').delete().eq('lesson_id', lessonId)
  if (error) throw error
}
