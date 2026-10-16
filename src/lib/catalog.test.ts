import {
  accessLastDay,
  canOpenCourse,
  flattenLessons,
  formatDuration,
  groupCourses,
  hasAnyAccess,
  neighbors,
  nextLesson,
  percent,
  summarizeAccesses,
  type Access,
  type CourseSummary,
  type LessonItem,
  type MasterInfo,
  type Me,
  type ModuleItem,
} from './catalog'

const me = (over: Partial<Me> = {}): Me => ({
  firstName: null,
  isStaff: false,
  mustChangePassword: false,
  plan: false,
  masterIds: [],
  accesses: [],
  ...over,
})

const course = (over: Partial<CourseSummary>): CourseSummary => ({
  id: over.slug ?? 'c',
  masterId: null,
  slug: 'c',
  title: { es: 'Curso' },
  summary: {},
  position: 0,
  published: true,
  lessonCount: 0,
  doneCount: 0,
  ...over,
})

const master = (id: string, order: number): MasterInfo => ({
  id,
  name: id,
  title: { es: id },
  summary: {},
  colorToken: 'accent-1',
  order,
})

const lesson = (id: string, position: number, moduleId = 'm1'): LessonItem => ({
  id,
  moduleId,
  title: { es: id },
  durationSeconds: null,
  position,
  published: true,
  hasVideo: true,
})

describe('acceso', () => {
  it('sin suscripción no hay acceso', () => {
    expect(hasAnyAccess(me())).toBe(false)
    expect(canOpenCourse(me(), 'm1')).toBe(false)
  })

  it('la suscripción anual abre todo, incluidos los cursos de regalo', () => {
    expect(canOpenCourse(me({ plan: true }), 'm1')).toBe(true)
    expect(canOpenCourse(me({ plan: true }), null)).toBe(true)
  })

  it('un Máster suelto abre solo sus cursos, no los de regalo', () => {
    const student = me({ masterIds: ['m1'] })
    expect(hasAnyAccess(student)).toBe(true)
    expect(canOpenCourse(student, 'm1')).toBe(true)
    expect(canOpenCourse(student, 'm2')).toBe(false)
    expect(canOpenCourse(student, null)).toBe(false)
  })

  it('las cuentas de Núcleo ven todo', () => {
    expect(canOpenCourse(me({ isStaff: true }), null)).toBe(true)
  })
})

describe('groupCourses', () => {
  it('ordena por Máster como el sitio, deja los de regalo al final y omite Másteres sin cursos', () => {
    const groups = groupCourses(
      [
        course({ slug: 'sql', masterId: 'datos', position: 2 }),
        course({ slug: 'excel', masterId: 'datos', position: 1 }),
        course({ slug: 'regalo' }),
        course({ slug: 'prompting', masterId: 'ia' }),
      ],
      [master('ia', 2), master('datos', 1), master('vacio', 3)],
    )
    expect(groups.map((g) => g.master?.id ?? 'regalo')).toEqual(['datos', 'ia', 'regalo'])
    expect(groups[0]?.courses.map((c) => c.slug)).toEqual(['excel', 'sql'])
  })
})

describe('navegación entre clases', () => {
  const modules: ModuleItem[] = [
    { id: 'm2', title: { es: 'Dos' }, position: 2, lessons: [lesson('c', 1, 'm2')] },
    { id: 'm1', title: { es: 'Uno' }, position: 1, lessons: [lesson('b', 2), lesson('a', 1)] },
  ]
  const lessons = flattenLessons(modules)

  it('aplana las clases en el orden de módulos y posiciones', () => {
    expect(lessons.map((l) => l.id)).toEqual(['a', 'b', 'c'])
  })

  it('la próxima clase es la primera sin terminar', () => {
    expect(nextLesson(lessons, new Set(['a']))?.id).toBe('b')
    expect(nextLesson(lessons, new Set(['a', 'b', 'c']))).toBeNull()
  })

  it('encuentra la clase anterior y la siguiente, también entre módulos', () => {
    expect(neighbors(lessons, 'b')).toMatchObject({ previous: { id: 'a' }, next: { id: 'c' } })
    expect(neighbors(lessons, 'a').previous).toBeNull()
    expect(neighbors(lessons, 'x')).toEqual({ previous: null, next: null })
  })
})

describe('formatos', () => {
  it('calcula el porcentaje sin pasarse de 100 ni dividir por cero', () => {
    expect(percent(1, 3)).toBe(33)
    expect(percent(5, 3)).toBe(100)
    expect(percent(0, 0)).toBe(0)
  })

  it('muestra la duración en minutos u horas', () => {
    expect(formatDuration(null)).toBeNull()
    expect(formatDuration(20)).toBe('1 min')
    expect(formatDuration(8 * 60)).toBe('8 min')
    expect(formatDuration(65 * 60)).toBe('1 h 05 min')
    expect(formatDuration(120 * 60)).toBe('2 h')
  })
})

describe('accesos de "Mi cuenta"', () => {
  const access = (over: Partial<Access>): Access => ({
    kind: 'plan',
    masterId: null,
    until: null,
    lastDay: null,
    manual: false,
    ...over,
  })

  it('usa el último día que manda la base', () => {
    expect(accessLastDay(access({ until: '2026-11-07T03:00:00Z', lastDay: '2026-11-06' }))).toBe('2026-11-06')
  })

  it('si falta, lo calcula en hora de Buenos Aires desde el fin del acceso', () => {
    // Termina el 07/11 a las 00:00 de Buenos Aires: el último día con acceso es el 06/11.
    expect(accessLastDay(access({ until: '2026-11-07T03:00:00Z' }))).toBe('2026-11-06')
    expect(accessLastDay(access({ until: '2026-11-07T03:00:01Z' }))).toBe('2026-11-07')
    expect(accessLastDay(access({}))).toBeNull()
  })

  it('deja uno por producto, con el que termina más tarde, y la anual primero', () => {
    const list = summarizeAccesses([
      access({ kind: 'master', masterId: 'm1', until: '2027-01-01T03:00:00Z' }),
      access({ kind: 'plan', until: '2026-12-01T03:00:00Z' }),
      access({ kind: 'master', masterId: 'm1', until: '2027-06-01T03:00:00Z', manual: true }),
      access({ kind: 'plan', until: null, manual: true }),
      access({ kind: 'master', masterId: 'm2', until: '2027-02-01T03:00:00Z' }),
    ])
    expect(list.map((a) => [a.kind, a.masterId, a.until, a.manual])).toEqual([
      ['plan', null, null, true],
      ['master', 'm1', '2027-06-01T03:00:00Z', true],
      ['master', 'm2', '2027-02-01T03:00:00Z', false],
    ])
  })
})
