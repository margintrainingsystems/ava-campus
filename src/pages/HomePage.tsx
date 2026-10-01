import { useCallback } from 'react'
import { Link } from 'react-router-dom'
import { useStudent } from '../auth/context'
import { ProgressBar } from '../components/ProgressBar'
import { Loading, LoadError } from '../components/StatusScreens'
import { useI18n } from '../i18n/context'
import { canOpenCourse, groupCourses, type CourseSummary, type Me } from '../lib/catalog'
import { loadCourses, loadMasters } from '../lib/queries'
import { useAsync } from '../lib/useAsync'

export function HomePage() {
  const { me } = useStudent()
  const { t, text } = useI18n()
  const load = useCallback(async () => {
    const [masters, courses] = await Promise.all([loadMasters(), loadCourses()])
    return { masters, courses }
  }, [])
  const { data, error, loading, reload } = useAsync(load)

  const groups = data ? groupCourses(data.courses, data.masters) : []
  // El curso más reciente que la persona empezó y no terminó, para seguir de un toque.
  const inProgress = data?.courses.find(
    (c) => canOpenCourse(me, c.masterId) && c.doneCount > 0 && c.doneCount < c.lessonCount,
  )

  return (
    <section className="stack-lg">
      <header className="stack-sm">
        <h1 className="h-xl" tabIndex={-1} data-page-title>
          {me.firstName ? t('home.hello', { name: me.firstName }) : t('home.helloNoName')}
        </h1>
        <p className="text-muted">{t('home.intro')}</p>
      </header>

      {loading && !data && <Loading />}
      {error != null && <LoadError error={error} onRetry={() => void reload()} title={t('home.loadError')} />}

      {inProgress && (
        <Link to={`/cursos/${inProgress.slug}`} className="resume-card">
          <span className="resume-eyebrow">{t('home.continue')}</span>
          <span className="h-md">{text(inProgress.title)}</span>
          <ProgressBar done={inProgress.doneCount} total={inProgress.lessonCount} />
        </Link>
      )}

      {data && groups.length === 0 && <p className="empty-state">{t('home.empty')}</p>}

      {groups.map((group) => (
        <section key={group.master?.id ?? 'regalo'} className="stack-md" aria-labelledby={`g-${group.master?.id ?? 'regalo'}`}>
          <div className={`group-head tone-${group.master?.colorToken ?? 'green'}`}>
            <h2 id={`g-${group.master?.id ?? 'regalo'}`} className="h-lg">
              {group.master ? text(group.master.title) : t('home.gifts')}
            </h2>
            {group.master ? (
              text(group.master.summary) && <p className="text-muted measure">{text(group.master.summary)}</p>
            ) : (
              <p className="text-muted">{t('home.giftsHelp')}</p>
            )}
          </div>
          <ul className="course-grid">
            {group.courses.map((course) => (
              <li key={course.id}>
                <CourseCard course={course} me={me} />
              </li>
            ))}
          </ul>
        </section>
      ))}
    </section>
  )
}

function CourseCard({ course, me }: { course: CourseSummary; me: Me }) {
  const { t, text } = useI18n()
  const open = canOpenCourse(me, course.masterId)
  const finished = course.lessonCount > 0 && course.doneCount >= course.lessonCount
  const summary = text(course.summary)

  return (
    <Link to={`/cursos/${course.slug}`} className={open ? 'course-card' : 'course-card course-card-locked'}>
      <span className="course-card-tags">
        {!course.published && <span className="tag">{t('home.draft')}</span>}
        {!open && <span className="tag">{t('home.locked')}</span>}
        {finished && <span className="tag tag-done">{t('home.done')}</span>}
      </span>
      <span className="h-md course-card-title">{text(course.title)}</span>
      {summary && <span className="text-muted course-card-summary">{summary}</span>}
      <span className="course-card-foot">
        {open && course.lessonCount > 0 ? (
          <ProgressBar done={course.doneCount} total={course.lessonCount} />
        ) : (
          <span className="text-muted">
            {course.lessonCount === 1 ? t('home.lessonsOne') : t('home.lessons', { count: course.lessonCount })}
          </span>
        )}
      </span>
    </Link>
  )
}
