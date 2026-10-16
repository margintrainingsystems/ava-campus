// Reglas del catálogo que no dependen de la base: acceso, orden, progreso y navegación.
// La base aplica las mismas reglas de acceso con RLS; acá solo deciden qué se muestra.
import type { I18nText } from '../i18n/types'

// Un acceso vigente: una suscripción paga o un acceso manual dado desde el CRM.
//   until:   instante en que termina (fin exclusivo, el que compara la base). Null = sin vencimiento.
//   lastDay: último día con acceso, en fecha de Buenos Aires (AAAA-MM-DD). Null = sin vencimiento.
export type Access = {
  kind: 'plan' | 'master'
  masterId: string | null
  until: string | null
  lastDay: string | null
  manual: boolean
}

export type Me = {
  firstName: string | null
  isStaff: boolean
  // Todavía tiene la contraseña inicial que le dio el equipo: la base no le entrega clases hasta
  // que la cambie.
  mustChangePassword: boolean
  plan: boolean
  masterIds: string[]
  accesses: Access[]
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

// Último día con acceso (AAAA-MM-DD, fecha de Buenos Aires), como lo muestra el CRM. Usa last_day de
// la base; si no llegara, lo calcula desde until (fin exclusivo) menos 1 ms. Null = sin vencimiento.
export function accessLastDay(access: Access): string | null {
  if (access.lastDay && /^\d{4}-\d{2}-\d{2}$/.test(access.lastDay)) return access.lastDay
  if (!access.until) return null
  const end = Date.parse(access.until)
  if (Number.isNaN(end)) return null
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Argentina/Buenos_Aires',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date(end - 1))
  const part = (type: string) => parts.find((p) => p.type === type)?.value ?? ''
  return `${part('year')}-${part('month')}-${part('day')}`
}

// Los accesos para "Mi cuenta": uno por producto (si hay una suscripción paga y un acceso manual
// del mismo, se suman y vale el que termina más tarde; sin vencimiento gana), la anual primero.
export function summarizeAccesses(accesses: Access[]): Access[] {
  const byProduct = new Map<string, Access>()
  for (const access of accesses) {
    const key = access.kind === 'plan' ? 'plan' : `master:${access.masterId ?? ''}`
    const current = byProduct.get(key)
    if (!current || endsLater(access, current)) byProduct.set(key, access)
  }
  return [...byProduct.values()].sort((a, b) => (a.kind === b.kind ? 0 : a.kind === 'plan' ? -1 : 1))
}

function endsLater(a: Access, b: Access): boolean {
  if (b.until === null) return false
  if (a.until === null) return true
  return Date.parse(a.until) > Date.parse(b.until)
}
