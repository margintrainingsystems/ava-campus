import { useCallback } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useStudent } from '../auth/context'
import { ProgressBar } from '../components/ProgressBar'
import { Loading, LoadError } from '../components/StatusScreens'
import { useI18n } from '../i18n/context'
import { canOpenCourse, flattenLessons, formatDuration, nextLesson, sortModules } from '../lib/catalog'
import { loadCourse } from '../lib/queries'
import { useAsync } from '../lib/useAsync'

export function CoursePage() {
  const { slug = '' } = useParams()
  const { me } = useStudent()
  const { t, text } = useI18n()
  const load = useCallback(() => loadCourse(slug), [slug])
  const { data, error, loading, reload } = useAsync(load, slug)

  if (loading && !data) return <Loading />
  if (error != null) return <LoadError error={error} onRetry={() => void reload()} />
  if (!data) {
    return (
      <section className="stack-md">
        <h1 className="h-lg" tabIndex={-1} data-page-title>
          {t('course.notFound')}
        </h1>
        <Link to="/" className="text-link">
          {t('course.allCourses')}
        </Link>
      </section>
    )
  }

  const { course, done } = data
  const modules = sortModules(data.modules).filter((m) => m.lessons.length > 0)
  const lessons = flattenLessons(modules)
  const open = canOpenCourse(me, course.masterId)
  const next = nextLesson(lessons, done)
  const first = lessons[0]
  const summary = text(course.summary)

  return (
    <article className="stack-lg">
      <header className="stack-sm">
        <Link to="/" className="back-link">
          ← {t('course.allCourses')}
        </Link>
        <h1 className="h-xl" tabIndex={-1} data-page-title>
          {text(course.title)}
        </h1>
        {summary && <p className="text-muted measure">{summary}</p>}
      </header>

      {!open ? (
        <p className="form-note">{t('course.locked')}</p>
      ) : lessons.length === 0 ? (
        <p className="empty-state">{t('course.empty')}</p>
      ) : (
        <div className="course-actions">
          <ProgressBar done={course.doneCount} total={course.lessonCount} />
          {next ? (
            <Link to={`/cursos/${course.slug}/clases/${next.id}`} className="btn btn-solid">
              {done.size === 0 ? t('course.start') : t('course.continue')}
            </Link>
          ) : (
            <>
              <p className="course-done">{t('course.completed')}</p>
              {first && (
                <Link to={`/cursos/${course.slug}/clases/${first.id}`} className="btn btn-outline">
                  {t('course.review')}
                </Link>
              )}
            </>
          )}
        </div>
      )}

      {open && modules.length > 0 && (
        <section className="stack-md" aria-labelledby="contenido-curso">
          <h2 id="contenido-curso" className="h-lg">
            {t('course.lessonsTitle')}
          </h2>
          <ol className="module-list">
            {modules.map((module, mi) => (
              <li key={module.id} className="module">
                <h3 className="module-title">
                  <span className="module-number">{t('course.module', { n: mi + 1 })}</span>
                  {text(module.title)}
                </h3>
                <ol className="lesson-list">
                  {module.lessons.map((lesson) => {
                    const isDone = done.has(lesson.id)
                    const duration = formatDuration(lesson.durationSeconds)
                    return (
                      <li key={lesson.id}>
                        <Link
                          to={`/cursos/${course.slug}/clases/${lesson.id}`}
                          className={isDone ? 'lesson-row lesson-row-done' : 'lesson-row'}
                        >
                          <span className="lesson-check" aria-hidden="true">
                            {isDone ? '✓' : ''}
                          </span>
                          <span className="lesson-row-title">{text(lesson.title)}</span>
                          {!lesson.published && <span className="tag">{t('home.draft')}</span>}
                          {duration && <span className="lesson-row-meta">{duration}</span>}
                          {isDone && <span className="visually-hidden">{t('course.lessonDone')}</span>}
                        </Link>
                      </li>
                    )
                  })}
                </ol>
              </li>
            ))}
          </ol>
        </section>
      )}
    </article>
  )
}
