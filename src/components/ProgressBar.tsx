import { useI18n } from '../i18n/context'
import { percent } from '../lib/catalog'

export function ProgressBar({ done, total }: { done: number; total: number }) {
  const { t } = useI18n()
  const value = percent(done, total)
  const label = t('home.progress', { done, total })
  return (
    <div className="progress">
      <div
        className="progress-track"
        role="progressbar"
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={value}
        aria-label={label}
      >
        <span className="progress-fill" style={{ width: `${value}%` }} />
      </div>
      <span className="progress-label">{label}</span>
    </div>
  )
}
