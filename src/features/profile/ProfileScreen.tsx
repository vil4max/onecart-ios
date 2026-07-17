import { useMemo } from 'react'
import {
  ArrowLeft,
  Bell,
  BellPlus,
  ChevronRight,
  CircleHelp,
  Cloud,
  Coins,
  DatabaseBackup,
  Download,
  Info,
  Languages,
  MessageSquareText,
  Paintbrush,
  Ruler,
  ShieldCheck,
  Trash2,
  UserPlus,
  UsersRound,
} from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import type { ThemePreference } from '../../domain/models'
import { createTranslator } from '../../localization'
import type { TranslationKey } from '../../localization'
import type { ShowToastOptions } from '../../shared/hooks/useAppToast'
import { useAppState } from '../../store/AppStateProvider'
import { selectCurrentUser } from '../../store/selectors'
import { IconButton, MemberAvatar } from '../../ui'

export type ProfileSharingDestination = 'members' | 'invitations' | 'permissions'
export type ProfileSettingsDestination =
  | 'language'
  | 'currency'
  | 'theme'
  | 'units'
  | 'sync'
  | 'backup'
  | 'export'
  | 'clearHistory'
export type ProfilePrototypeAction = 'help' | 'feedback' | 'about'

export interface ProfileScreenProps {
  onBack?: () => void
  onOpenNotifications: () => void
  onOpenSharing: (destination: ProfileSharingDestination) => void
  onOpenSettings: (destination: ProfileSettingsDestination) => void
  onPrototypeAction?: (action: ProfilePrototypeAction) => void
  onShowToast: (message: string, options?: ShowToastOptions) => void
}

interface ProfileRow {
  id: string
  label: string
  detail?: string
  icon: LucideIcon
  onClick: () => void
  danger?: boolean
}

interface ProfileSectionProps {
  title: string
  rows: ProfileRow[]
}

function ProfileSection({ rows, title }: ProfileSectionProps) {
  return (
    <section className="settings-section">
      <h2 className="settings-section__title">{title}</h2>
      <div className="card">
        {rows.map(({ danger, detail, icon: Icon, id, label, onClick }) => (
          <button className="settings-row" key={id} onClick={onClick} type="button">
            <span className="settings-row__icon" aria-hidden="true">
              <Icon color={danger ? 'var(--color-danger)' : undefined} size={19} />
            </span>
            <span className="settings-row__copy">
              <strong>{label}</strong>
              {detail ? <span>{detail}</span> : null}
            </span>
            <ChevronRight aria-hidden="true" size={18} />
          </button>
        ))}
      </div>
    </section>
  )
}

export function ProfileScreen({
  onBack,
  onOpenNotifications,
  onOpenSettings,
  onOpenSharing,
  onPrototypeAction,
  onShowToast,
}: ProfileScreenProps) {
  const state = useAppState()
  const locale = state.settings.locale
  const t = useMemo(() => createTranslator(locale), [locale])
  const user = selectCurrentUser(state)
  const unitKey = `units.${state.settings.defaultUnit}` as TranslationKey
  const themeKeys: Record<ThemePreference, TranslationKey> = {
    light: 'settings.theme.light',
    dark: 'settings.theme.dark',
    system: 'settings.theme.system',
  }

  const runPrototypeAction = (action: ProfilePrototypeAction) => {
    onPrototypeAction?.(action)
    onShowToast(t('mock.featureComingSoon'))
  }

  const familyRows: ProfileRow[] = [
    {
      id: 'members',
      label: t('profile.family.members'),
      detail: t('sharing.participants'),
      icon: UsersRound,
      onClick: () => onOpenSharing('members'),
    },
    {
      id: 'invitations',
      label: t('profile.family.invitations'),
      detail: t('sharing.invite'),
      icon: UserPlus,
      onClick: () => onOpenSharing('invitations'),
    },
    {
      id: 'permissions',
      label: t('profile.family.permissions'),
      detail: t('sharing.accessRights'),
      icon: ShieldCheck,
      onClick: () => onOpenSharing('permissions'),
    },
  ]

  const applicationRows: ProfileRow[] = [
    {
      id: 'notifications',
      label: t('settings.notifications'),
      detail: t('notifications.mode.all'),
      icon: Bell,
      onClick: onOpenNotifications,
    },
    {
      id: 'language',
      label: t('settings.language'),
      detail: t(locale === 'ru' ? 'settings.language.ru' : 'settings.language.uk'),
      icon: Languages,
      onClick: () => onOpenSettings('language'),
    },
    {
      id: 'currency',
      label: t('settings.currency'),
      detail: t('common.currencyUah'),
      icon: Coins,
      onClick: () => onOpenSettings('currency'),
    },
    {
      id: 'theme',
      label: t('settings.theme'),
      detail: t(themeKeys[state.settings.theme]),
      icon: Paintbrush,
      onClick: () => onOpenSettings('theme'),
    },
    {
      id: 'units',
      label: t('settings.units'),
      detail: t(unitKey),
      icon: Ruler,
      onClick: () => onOpenSettings('units'),
    },
  ]

  const dataRows: ProfileRow[] = [
    {
      id: 'sync',
      label: t('settings.sync'),
      detail: state.settings.syncEnabled ? t('common.enabled') : t('common.disabled'),
      icon: Cloud,
      onClick: () => onOpenSettings('sync'),
    },
    {
      id: 'backup',
      label: t('settings.backup'),
      detail: t('settings.backupDescription'),
      icon: DatabaseBackup,
      onClick: () => onOpenSettings('backup'),
    },
    {
      id: 'export',
      label: t('settings.export'),
      detail: t('settings.exportDescription'),
      icon: Download,
      onClick: () => onOpenSettings('export'),
    },
    {
      id: 'clear-history',
      label: t('settings.clearHistory'),
      detail: t('common.productsCount', { count: state.purchaseHistory.length }),
      icon: Trash2,
      danger: true,
      onClick: () => onOpenSettings('clearHistory'),
    },
  ]

  const supportRows: ProfileRow[] = [
    {
      id: 'help',
      label: t('settings.help'),
      icon: CircleHelp,
      onClick: () => runPrototypeAction('help'),
    },
    {
      id: 'feedback',
      label: t('settings.feedback'),
      icon: MessageSquareText,
      onClick: () => runPrototypeAction('feedback'),
    },
    {
      id: 'about',
      label: t('settings.about'),
      detail: t('settings.version', { version: '0.1.0' }),
      icon: Info,
      onClick: () => runPrototypeAction('about'),
    },
  ]

  return (
    <main className="screen">
      <header className="app-topbar">
        {onBack ? <IconButton icon={ArrowLeft} label={t('common.back')} onClick={onBack} /> : null}
        <div className="app-topbar__title">
          <h1>{t('profile.title')}</h1>
        </div>
        <IconButton icon={BellPlus} label={t('a11y.openNotifications')} onClick={onOpenNotifications} />
      </header>

      <div className="screen-content">
        <section className="profile-hero" aria-label={t('profile.title')}>
          <MemberAvatar
            avatarUrl={user?.avatar}
            name={user?.name ?? t('common.notSpecified')}
            size="large"
          />
          <h2>{user?.name ?? t('common.notSpecified')}</h2>
          <p>{user?.email ?? t('common.notSpecified')}</p>
          <span className="badge">{t('sharing.owner')}</span>
        </section>

        <ProfileSection rows={familyRows} title={t('profile.family')} />
        <ProfileSection rows={applicationRows} title={t('profile.application')} />
        <ProfileSection rows={dataRows} title={t('profile.data')} />
        <ProfileSection rows={supportRows} title={t('profile.support')} />
      </div>
    </main>
  )
}
