import { useCallback, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { RichText } from '../components/RichText'
import { Loading, LoadError } from '../components/StatusScreens'
import { useToast } from '../components/Toast'
import { useI18n } from '../i18n/context'
import { flattenLessons, neighbors, sortModules } from '../lib/catalog'
import { errorKey } from '../lib/errors'
import { loadCourse, loadLessonContent, setLessonDone } from '../lib/queries'
import { useAsync } from '../lib/useAsync'
import { isYoutubeId, youtubeEmbedUrl } from '../lib/youtube'

export function LessonPage() {
  const { slug = '', lessonId = '' } = useParams()
  const { t, text, locale } = useI18n()
  const toast = useToast()
  const navigate = useNavigate()
  const [saving, setSaving] = useState(false)
  // Cambios de "terminada" hechos en esta pantalla, encima de lo que vino de la base.
  const [overrides, setOverrides] = useState<Record<string, boolean>>({})

  const load = useCallback(async () => {
    const [course, content] = await Promise.all([loadCourse(slug), loadLessonContent(lessonId)])
    return { course, content }
  }, [slug, lessonId])
  const { data, error, loading, reload } = useAsync(load, `${slug}/${lessonId}`)

  if (loading && !data) return <Loading />
  if (error != null) return <LoadError error={error} onRetry={() => void reload()} />

  const course = data?.course
  const content = data?.content
  const lessons = course ? flattenLessons(course.modules) : []
  const lesson = lessons.find((l) => l.id === lessonId)

  if (!course || !content || !lesson) {
    return (
      <section className="stack-md">
        <h1 className="h-lg" tabIndex={-1} data-page-title>
          {t('lesson.notFound')}
        </h1>
        <Link to={course ? `/cursos/${slug}` : '/'} className="text-link">
          {course ? t('lesson.backToCourse') : t('course.allCourses')}
        </Link>
      </section>
    )
  }

  const isDone = (id: string) => overrides[id] ?? course.done.has(id)
  const done = isDone(lesson.id)
  const { previous, next } = neighbors(lessons, lesson.id)
  const title = text(lesson.title)
  const body = text(content.body)
  const modules = sortModules(course.modules).filter((m) => m.lessons.length > 0)

  async function toggleDone(goNext: boolean) {
    setSaving(true)
    try {
      await setLessonDone(lessonId, !done)
      setOverrides((o) => ({ ...o, [lessonId]: !done }))
      if (!done) toast.show(t('lesson.marked'))
      if (!done && goNext && next) navigate(`/cursos/${slug}/clases/${next.id}`)
    } catch (e) {
      toast.show(t(errorKey(e)), 'error')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="lesson-layout">
      <article className="lesson-main stack-md">
        <header className="stack-sm">
          <Link to={`/cursos/${slug}`} className="back-link">
            ← {text(course.course.title)}
          </Link>
          <h1 className="h-xl" tabIndex={-1} data-page-title>
            {title}
          </h1>
          {!lesson.published && <p className="form-note">{t('lesson.draft')}</p>}
        </header>

        {isYoutubeId(content.youtubeId) ? (
          <div className="stack-sm">
            <div className="video-frame">
              <iframe
                src={youtubeEmbedUrl(content.youtubeId, locale)}
                title={t('lesson.video', { title })}
                allow="accelerometer; encrypted-media; gyroscope; picture-in-picture; fullscreen"
                referrerPolicy="strict-origin-when-cross-origin"
                allowFullScreen
              />
            </div>
            {locale !== 'es' && <p className="field-help">{t('lesson.subtitles')}</p>}
          </div>
        ) : (
          <p className="form-note">{t('lesson.noVideo')}</p>
        )}

        {body && <RichText source={body} />}

        {content.resources.length > 0 && (
          <section className="stack-sm" aria-labelledby="materiales">
            <h2 id="materiales" className="h-md">
              {t('lesson.resources')}
            </h2>
            <ul className="resource-list">
              {content.resources.map((r) => (
                <li key={r.id}>
                  <a href={r.url} target="_blank" rel="noopener noreferrer" className="text-link">
                    {text(r.label)} ↗
                  </a>
                </li>
              ))}
            </ul>
          </section>
        )}

        <div className="lesson-actions">
          <button
            type="button"
            className={done ? 'btn btn-outline' : 'btn btn-solid'}
            aria-pressed={done}
            disabled={saving}
            aria-busy={saving}
            onClick={() => void toggleDone(true)}
          >
            {done ? t('lesson.markUndone') : t('lesson.markDone')}
          </button>
          <nav className="lesson-nav" aria-label={t('lesson.outline')}>
            {previous && (
              <Link to={`/cursos/${slug}/clases/${previous.id}`} className="btn btn-ghost">
                ← {t('lesson.previous')}
              </Link>
            )}
            {next && (
              <Link to={`/cursos/${slug}/clases/${next.id}`} className="btn btn-ghost">
                {t('lesson.next')} →
              </Link>
            )}
          </nav>
        </div>
      </article>

      <aside className="lesson-outline" aria-labelledby="clases-del-curso">
        <h2 id="clases-del-curso" className="h-md">
          {t('lesson.outline')}
        </h2>
        <ol className="outline-modules">
          {modules.map((module) => (
            <li key={module.id}>
              <p className="outline-module-title">{text(module.title)}</p>
              <ol className="outline-lessons">
                {module.lessons.map((l) => (
                  <li key={l.id}>
                    <Link
                      to={`/cursos/${slug}/clases/${l.id}`}
                      className={l.id === lesson.id ? 'outline-link is-current' : 'outline-link'}
                      aria-current={l.id === lesson.id ? 'page' : undefined}
                    >
                      <span className="lesson-check" aria-hidden="true">
                        {isDone(l.id) ? '✓' : ''}
                      </span>
                      <span>{text(l.title)}</span>
                      {isDone(l.id) && <span className="visually-hidden">{t('course.lessonDone')}</span>}
                    </Link>
                  </li>
                ))}
              </ol>
            </li>
          ))}
        </ol>
      </aside>
    </div>
  )
}
