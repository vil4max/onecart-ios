import { useEffect, useMemo, useRef, useState } from 'react'
import type { Ref } from 'react'
import {
  ArrowLeft,
  Bell,
  ChevronRight,
  CircleHelp,
  Cloud,
  Coins,
  DatabaseBackup,
  Download,
  Info,
  MessageSquareText,
  Monitor,
  Moon,
  Sun,
  Trash2,
} from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import {
  PRODUCT_UNITS,
  type ProductUnit,
  type ThemePreference,
} from '../../domain/models'
import { createTranslator, updateDocumentLanguage } from '../../localization'
import type { TranslationKey } from '../../localization'
import { NotificationPreferences } from '../notifications'
import type { ShowToastOptions } from '../../shared/hooks/useAppToast'
import { runMotionTransition } from '../../shared/motion'
import { applyThemePreference } from '../../shared/theme'
import { useAppStore } from '../../store/AppStateProvider'
import { appActions } from '../../store/appReducer'
import { BottomSheet, ConfirmationDialog, IconButton } from '../../ui'

export type SettingsSection =
  | 'notifications'
  | 'language'
  | 'currency'
  | 'theme'
  | 'units'
  | 'sync'
  | 'backup'
  | 'export'
  | 'clearHistory'
  | 'support'

export type SettingsMockAction = 'sync' | 'backup' | 'export' | 'help' | 'feedback'

export interface SettingsScreenProps {
  onBack: () => void
  onOpenNotifications: () => void
  onMockAction: (action: SettingsMockAction) => void
  onShowToast: (message: string, options?: ShowToastOptions) => void
  focusSection?: SettingsSection
}

interface ActionRowProps {
  icon: LucideIcon
  label: string
  detail?: string
  onClick: () => void
  danger?: boolean
  disabled?: boolean
  elementRef?: Ref<HTMLButtonElement>
}

function ActionRow({
  danger,
  detail,
  disabled,
  elementRef,
  icon: Icon,
  label,
  onClick,
}: ActionRowProps) {
  return (
    <button
      className="settings-row"
      disabled={disabled}
      onClick={onClick}
      ref={elementRef}
      title={disabled ? detail : undefined}
      type="button"
    >
      <span className="settings-row__icon" aria-hidden="true">
        <Icon color={danger ? 'var(--color-danger)' : undefined} size={19} />
      </span>
      <span className="settings-row__copy">
        <strong>{label}</strong>
        {detail ? <span>{detail}</span> : null}
      </span>
      <ChevronRight aria-hidden="true" size={18} />
    </button>
  )
}

export function SettingsScreen({
  focusSection,
  onBack,
  onMockAction,
  onOpenNotifications,
  onShowToast,
}: SettingsScreenProps) {
  const { state, dispatch } = useAppStore()
  const [clearHistoryOpen, setClearHistoryOpen] = useState(false)
  const [aboutOpen, setAboutOpen] = useState(false)
  const focusTargets = useRef<Partial<Record<SettingsSection, HTMLElement | null>>>({})
  const locale = state.settings.locale
  const t = useMemo(() => createTranslator(locale), [locale])

  useEffect(() => {
    if (!focusSection) return undefined

    const frame = window.requestAnimationFrame(() => {
      const target = focusTargets.current[focusSection]
      if (!target) return
      const reduceMotion = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false
      target.scrollIntoView?.({
        behavior: reduceMotion ? 'auto' : 'smooth',
        block: 'start',
      })
      target.focus({ preventScroll: true })
    })

    return () => window.cancelAnimationFrame(frame)
  }, [focusSection])

  const setFocusTarget =
    (section: SettingsSection) => (element: HTMLElement | null): void => {
      focusTargets.current[section] = element
    }

  const saveLocale = (nextLocale: 'ru' | 'uk') => {
    runMotionTransition(() => {
      dispatch(appActions.setLocale(nextLocale))
      updateDocumentLanguage(nextLocale)
      onShowToast(createTranslator(nextLocale)('toast.settingsSaved'))
    }, 'language')
  }

  const saveUnit = (unit: ProductUnit) => {
    dispatch(appActions.updateSettings({ defaultUnit: unit }))
    onShowToast(t('toast.settingsSaved'))
  }

  const saveTheme = (theme: ThemePreference) => {
    runMotionTransition(() => {
      applyThemePreference(theme)
      dispatch(appActions.updateSettings({ theme }))
      onShowToast(t('toast.settingsSaved'))
    }, 'theme')
  }

  const themeOptions: ReadonlyArray<{
    icon: LucideIcon
    label: string
    value: ThemePreference
  }> = [
    { icon: Sun, label: t('settings.theme.light'), value: 'light' },
    { icon: Moon, label: t('settings.theme.dark'), value: 'dark' },
    { icon: Monitor, label: t('settings.theme.system'), value: 'system' },
  ]

  const runMock = (action: SettingsMockAction, message: string) => {
    onMockAction(action)
    onShowToast(message)
  }

  const clearHistory = () => {
    state.purchaseHistory.forEach((entry) => dispatch(appActions.deleteHistory(entry.id)))
    setClearHistoryOpen(false)
    onShowToast(t('toast.historyDeleted'))
  }

  return (
    <main className="screen" data-focus-section={focusSection}>
      <header className="app-topbar">
        <IconButton icon={ArrowLeft} label={t('common.back')} onClick={onBack} />
        <div className="app-topbar__title">
          <h1>{t('settings.title')}</h1>
          <p>{t('mock.localData')}</p>
        </div>
      </header>

      <div className="screen-content">
        <section
          aria-labelledby="settings-notifications-title"
          className="settings-section"
          data-settings-section="notifications"
          ref={setFocusTarget('notifications')}
          tabIndex={-1}
        >
          <h2 className="settings-section__title" id="settings-notifications-title">
            {t('settings.notifications')}
          </h2>
          <div className="card">
            <ActionRow
              detail={t('notifications.title')}
              icon={Bell}
              label={t('settings.notifications')}
              onClick={onOpenNotifications}
            />
          </div>
          <NotificationPreferences onChange={() => onShowToast(t('toast.settingsSaved'))} />
        </section>

        <section
          aria-labelledby="settings-language-title"
          className="settings-section"
          data-settings-section="language"
          ref={setFocusTarget('language')}
          tabIndex={-1}
        >
          <h2 className="settings-section__title" id="settings-language-title">
            {t('settings.language')}
          </h2>
          <div
            aria-label={t('settings.language')}
            className="segmented-control"
            role="radiogroup"
            style={{ gridTemplateColumns: 'repeat(2, minmax(0, 1fr))' }}
          >
            <button
              aria-checked={locale === 'ru'}
              aria-selected={locale === 'ru'}
              onClick={() => saveLocale('ru')}
              role="radio"
              type="button"
            >
              {t('settings.language.ru')}
            </button>
            <button
              aria-checked={locale === 'uk'}
              aria-selected={locale === 'uk'}
              onClick={() => saveLocale('uk')}
              role="radio"
              type="button"
            >
              {t('settings.language.uk')}
            </button>
          </div>
        </section>

        <section
          aria-labelledby="settings-currency-title"
          className="settings-section"
          data-settings-section="currency"
          ref={setFocusTarget('currency')}
          tabIndex={-1}
        >
          <h2 className="settings-section__title" id="settings-currency-title">
            {t('settings.currency')}
          </h2>
          <div className="card">
            <ActionRow
              detail={t('common.currencyUah')}
              disabled
              icon={Coins}
              label={t('settings.currency')}
              onClick={() => undefined}
            />
          </div>
        </section>

        <section
          aria-labelledby="settings-theme-title"
          className="settings-section"
          data-settings-section="theme"
          ref={setFocusTarget('theme')}
          tabIndex={-1}
        >
          <h2 className="settings-section__title" id="settings-theme-title">
            {t('settings.theme')}
          </h2>
          <div
            aria-describedby="settings-theme-hint"
            aria-label={t('settings.theme')}
            className="segmented-control theme-selector"
            role="radiogroup"
          >
            {themeOptions.map(({ icon: Icon, label, value }) => (
              <button
                aria-checked={state.settings.theme === value}
                aria-selected={state.settings.theme === value}
                key={value}
                onClick={() => saveTheme(value)}
                role="radio"
                type="button"
              >
                <Icon aria-hidden="true" size={18} />
                <span>{label}</span>
              </button>
            ))}
          </div>
          <p className="theme-selector__hint" id="settings-theme-hint">
            {t('settings.theme.systemDescription')}
          </p>
        </section>

        <section
          aria-labelledby="settings-units-title"
          className="settings-section"
          data-settings-section="units"
          ref={setFocusTarget('units')}
          tabIndex={-1}
        >
          <h2 className="settings-section__title" id="settings-units-title">
            {t('settings.units')}
          </h2>
          <div className="card card--padded">
            <label className="field">
              <span className="field__label">{t('settings.defaultUnit')}</span>
              <select
                onChange={(event) => saveUnit(event.currentTarget.value as ProductUnit)}
                value={state.settings.defaultUnit}
              >
                {PRODUCT_UNITS.map((unit) => (
                  <option key={unit} value={unit}>
                    {t(`units.${unit}` as TranslationKey)}
                  </option>
                ))}
              </select>
            </label>
          </div>
        </section>

        <section
          aria-labelledby="settings-data-title"
          className="settings-section"
          data-settings-section="sync"
        >
          <h2 className="settings-section__title" id="settings-data-title">
            {t('profile.data')}
          </h2>
          <div className="card">
            <button
              aria-checked={state.settings.syncEnabled}
              className="settings-row"
              onClick={() => {
                const syncEnabled = !state.settings.syncEnabled
                dispatch(appActions.updateSettings({ syncEnabled }))
                runMock('sync', t('toast.settingsSaved'))
              }}
              role="switch"
              ref={setFocusTarget('sync')}
              type="button"
            >
              <span className="settings-row__icon" aria-hidden="true">
                <Cloud size={19} />
              </span>
              <span className="settings-row__copy">
                <strong>{t('settings.sync')}</strong>
                <span>{t('settings.sync.localOnly')}</span>
              </span>
              <span className={state.settings.syncEnabled ? 'badge' : 'badge badge--quiet'}>
                {state.settings.syncEnabled ? t('common.enabled') : t('common.disabled')}
              </span>
            </button>
            <ActionRow
              detail={t('settings.backupDescription')}
              icon={DatabaseBackup}
              label={t('settings.backup')}
              elementRef={setFocusTarget('backup')}
              onClick={() => runMock('backup', t('state.success'))}
            />
            <ActionRow
              detail={t('settings.exportDescription')}
              icon={Download}
              label={t('settings.export')}
              elementRef={setFocusTarget('export')}
              onClick={() => runMock('export', t('toast.exportReady'))}
            />
            <ActionRow
              danger
              detail={
                state.purchaseHistory.length === 0
                  ? t('empty.history.title')
                  : t('common.productsCount', { count: state.purchaseHistory.length })
              }
              disabled={state.purchaseHistory.length === 0}
              icon={Trash2}
              label={t('settings.clearHistory')}
              elementRef={setFocusTarget('clearHistory')}
              onClick={() => setClearHistoryOpen(true)}
            />
          </div>
        </section>

        <section
          aria-labelledby="settings-support-title"
          className="settings-section"
          data-settings-section="support"
          ref={setFocusTarget('support')}
          tabIndex={-1}
        >
          <h2 className="settings-section__title" id="settings-support-title">
            {t('profile.support')}
          </h2>
          <div className="card">
            <ActionRow
              detail={t('mock.featureComingSoon')}
              icon={CircleHelp}
              label={t('settings.help')}
              onClick={() => runMock('help', t('mock.featureComingSoon'))}
            />
            <ActionRow
              detail={t('mock.featureComingSoon')}
              icon={MessageSquareText}
              label={t('settings.feedback')}
              onClick={() => runMock('feedback', t('mock.featureComingSoon'))}
            />
            <ActionRow
              detail={t('settings.version', { version: '0.1.0' })}
              icon={Info}
              label={t('settings.about')}
              onClick={() => setAboutOpen(true)}
            />
          </div>
        </section>
      </div>

      <ConfirmationDialog
        cancelLabel={t('common.cancel')}
        confirmLabel={t('common.clear')}
        description={t('confirm.clearHistory.description')}
        isOpen={clearHistoryOpen}
        onCancel={() => setClearHistoryOpen(false)}
        onConfirm={clearHistory}
        title={t('confirm.clearHistory.title')}
        tone="danger"
      />

      <BottomSheet
        closeLabel={t('common.close')}
        isOpen={aboutOpen}
        onClose={() => setAboutOpen(false)}
        title={t('settings.about')}
      >
        <div className="section-stack">
          <p>{t('settings.aboutDescription')}</p>
          <p className="quiet">{t('settings.version', { version: '0.1.0' })}</p>
          <p className="quiet">{t('mock.noStoreApis')}</p>
        </div>
      </BottomSheet>
    </main>
  )
}
