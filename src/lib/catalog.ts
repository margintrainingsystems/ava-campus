// Reglas del catálogo que no dependen de la base: acceso, orden, progreso y navegación.
// La base aplica las mismas reglas de acceso con RLS; acá solo deciden qué se muestra.
import type { I18nText } from '../i18n/types'

export type Me = {
  firstName: string | null
  isStaff: boolean
  plan: boolean
  masterIds: string[]
  accessUntil: string | null
}

export type MasterInfo = {
  id: string
  name: string
  title: I18nText
  summary: I18nText
  colorToken: string
  order: number
}

export type CourseSummary = {
  id: string
  masterId: string | null
  slug: string
  title: I18nText
  summary: I18nText
  position: number
  published: boolean
  lessonCount: number
  doneCount: number
}

export type LessonItem = {
  id: string
  moduleId: string
  title: I18nText
  durationSeconds: number | null
  position: number
  published: boolean
  hasVideo: boolean
}

export type ModuleItem = {
  id: string
  title: I18nText
  position: number
  lessons: LessonItem[]
}

export type CourseGroup = { master: MasterInfo | null; courses: CourseSummary[] }

export function hasAnyAccess(me: Me): boolean {
  return me.isStaff || me.plan || me.masterIds.length > 0
}

// Sin Máster = curso de regalo: solo con la suscripción anual.
export function canOpenCourse(me: Me, masterId: string | null): boolean {
  if (me.isStaff || me.plan) return true
  return masterId !== null && me.masterIds.includes(masterId)
}

// Másteres en el orden del sitio; los cursos de regalo al final.
export function groupCourses(courses: CourseSummary[], masters: MasterInfo[]): CourseGroup[] {
  const byPosition = (a: CourseSummary, b: CourseSummary) => a.position - b.position || a.slug.localeCompare(b.slug)
  const groups: CourseGroup[] = [...masters]
    .sort((a, b) => a.order - b.order)
    .map((master) => ({ master, courses: courses.filter((c) => c.masterId === master.id).sort(byPosition) }))
    .filter((g) => g.courses.length > 0)
  const gifts = courses.filter((c) => c.masterId === null || !masters.some((m) => m.id === c.masterId)).sort(byPosition)
  if (gifts.length) groups.push({ master: null, courses: gifts })
  return groups
}

export function sortModules(modules: ModuleItem[]): ModuleItem[] {
  return [...modules]
    .sort((a, b) => a.position - b.position)
    .map((m) => ({ ...m, lessons: [...m.lessons].sort((a, b) => a.position - b.position) }))
}

export function flattenLessons(modules: ModuleItem[]): LessonItem[] {
  return sortModules(modules).flatMap((m) => m.lessons)
}

// La próxima clase sin terminar, en orden. Null si terminó todas o si no hay clases.
export function nextLesson(lessons: LessonItem[], done: ReadonlySet<string>): LessonItem | null {
  return lessons.find((l) => !done.has(l.id)) ?? null
}

export function neighbors(lessons: LessonItem[], id: string): { previous: LessonItem | null; next: LessonItem | null } {
  const i = lessons.findIndex((l) => l.id === id)
  if (i === -1) return { previous: null, next: null }
  return { previous: lessons[i - 1] ?? null, next: lessons[i + 1] ?? null }
}

export function percent(done: number, total: number): number {
  if (total <= 0) return 0
  return Math.min(100, Math.round((done / total) * 100))
}

// Duración legible: "8 min", "1 h 05 min".
export function formatDuration(seconds: number | null): string | null {
  if (seconds === null || seconds <= 0) return null
  const minutes = Math.max(1, Math.round(seconds / 60))
  if (minutes < 60) return `${minutes} min`
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  return m === 0 ? `${h} h` : `${h} h ${String(m).padStart(2, '0')} min`
}
