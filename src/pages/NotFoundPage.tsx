import { Link } from 'react-router-dom'
import { useI18n } from '../i18n/context'

export function NotFoundPage() {
  const { t } = useI18n()
  return (
    <section className="stack-md">
      <h1 className="h-lg" tabIndex={-1} data-page-title>
        {t('notFound.title')}
      </h1>
      <p className="text-muted">{t('notFound.body')}</p>
      <Link to="/" className="text-link">
        {t('course.allCourses')}
      </Link>
    </section>
  )
}
