import { useCallback } from 'react'
import { useStudent } from '../auth/context'
import { LanguageSelect } from '../components/LanguageSelect'
import { PasswordForm } from '../components/PasswordForm'
import { useToast } from '../components/Toast'
import { useI18n } from '../i18n/context'
import { loadMasters } from '../lib/queries'
import { useAsync } from '../lib/useAsync'

export function AccountPage() {
  const { me, session } = useStudent()
  const { t, text, formatDate } = useI18n()
  const toast = useToast()
  const load = useCallback(() => (me.masterIds.length ? loadMasters() : Promise.resolve([])), [me.masterIds])
  const { data: masters } = useAsync(load)

  const masterNames = (masters ?? []).filter((m) => me.masterIds.includes(m.id)).map((m) => text(m.title))

  return (
    <section className="stack-lg narrow">
      <h1 className="h-xl" tabIndex={-1} data-page-title>
        {t('account.title')}
      </h1>

      <section className="panel stack-sm" aria-labelledby="acceso">
        <h2 id="acceso" className="h-md">
          {t('account.access')}
        </h2>
        <p className="text-muted">
          {t('account.email')}: <strong className="text-strong">{session.user.email}</strong>
        </p>
        {me.isStaff && <p>{t('account.staff')}</p>}
        {me.plan && <p>{t('account.plan')}</p>}
        {!me.plan && masterNames.length > 0 && <p>{t('account.masters', { names: masterNames.join(', ') })}</p>}
        {me.accessUntil && <p className="text-muted">{t('account.until', { date: formatDate(me.accessUntil) })}</p>}
      </section>

      <section className="panel stack-sm">
        <LanguageSelect signedIn />
        <p className="field-help">{t('account.languageHelp')}</p>
      </section>

      <section className="panel stack-sm" aria-labelledby="contrasena">
        <h2 id="contrasena" className="h-md">
          {t('account.passwordTitle')}
        </h2>
        <PasswordForm submitLabel={t('account.passwordSubmit')} onSaved={() => toast.show(t('account.passwordSaved'))} />
      </section>
    </section>
  )
}
