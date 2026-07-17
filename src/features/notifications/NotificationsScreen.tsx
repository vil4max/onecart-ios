import { useMemo, useState } from 'react'
import {
  ArrowLeft,
  BellRing,
  CheckCheck,
  CheckCircle2,
  ChevronRight,
  ListChecks,
  PackagePlus,
  Settings2,
  UserPlus,
} from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import type { AppNotification, NotificationType } from '../../domain/models'
import { createTranslator, formatDateTime } from '../../localization'
import type { ShowToastOptions } from '../../shared/hooks/useAppToast'
import { useAppStore } from '../../store/AppStateProvider'
import { appActions } from '../../store/appReducer'
import { selectSortedNotifications, selectUnreadNotificationCount } from '../../store/selectors'
import { BottomSheet, EmptyState, IconButton } from '../../ui'
import { NotificationPreferences } from './NotificationPreferences'

const NOTIFICATION_ICONS: Record<NotificationType, LucideIcon> = {
  productAdded: PackagePlus,
  productPurchased: CheckCircle2,
  listChanged: ListChecks,
  memberJoined: UserPlus,
  listCompleted: CheckCheck,
}

export interface NotificationsScreenProps {
  onBack: () => void
  onOpenList: (listId: string) => void
  onOpenHistory: () => void
  onShowToast: (message: string, options?: ShowToastOptions) => void
}

function quotedValue(message: string): string | null {
  return /[«“"]([^»”"]+)[»”"]/.exec(message)?.[1] ?? null
}

export function NotificationsScreen({
  onBack,
  onOpenHistory,
  onOpenList,
  onShowToast,
}: NotificationsScreenProps) {
  const { state, dispatch } = useAppStore()
  const [settingsOpen, setSettingsOpen] = useState(false)
  const locale = state.settings.locale
  const t = useMemo(() => createTranslator(locale), [locale])
  const notifications = selectSortedNotifications(state)
  const unreadCount = selectUnreadNotificationCount(state)

  const localizedCopy = (notification: AppNotification): { title: string; message: string } => {
    const actor =
      state.users.find((user) => user.id === notification.actorId)?.name ?? t('common.notSpecified')
    const list = state.shoppingLists.find((item) => item.id === notification.listId)
    const product =
      quotedValue(notification.message) ??
      state.products.find((item) => notification.message.includes(item.name))?.name ??
      t('common.notSpecified')
    switch (notification.type) {
      case 'productAdded':
        return {
          title: t('notifications.productAdded.title'),
          message: t('notifications.productAdded.message', { actor, product }),
        }
      case 'productPurchased':
        return {
          title: t('notifications.productPurchased.title'),
          message: t('notifications.productPurchased.message', { actor, product }),
        }
      case 'listChanged':
        return {
          title: t('notifications.listChanged.title'),
          message: t('notifications.listChanged.message', {
            actor,
            list: list?.title ?? t('common.notSpecified'),
          }),
        }
      case 'memberJoined':
        return {
          title: t('notifications.memberJoined.title'),
          message: t('notifications.memberJoined.message', { member: actor }),
        }
      case 'listCompleted': {
        const store = state.stores.find((item) => notification.message.includes(item.name))
        return {
          title: t('notifications.listCompleted.title'),
          message: t('notifications.listCompleted.message', {
            store: store?.name ?? t('common.notSpecified'),
          }),
        }
      }
    }
  }

  const openNotification = (notification: AppNotification) => {
    if (!notification.isRead) dispatch(appActions.markNotificationRead(notification.id))
    if (notification.listId) onOpenList(notification.listId)
    else onOpenHistory()
  }

  return (
    <main className="screen">
      <header className="app-topbar">
        <IconButton icon={ArrowLeft} label={t('common.back')} onClick={onBack} />
        <div className="app-topbar__title">
          <h1>{t('notifications.title')}</h1>
          <p>{t('notifications.unreadCount', { count: unreadCount })}</p>
        </div>
        <IconButton
          icon={Settings2}
          label={t('notifications.settings')}
          onClick={() => setSettingsOpen(true)}
        />
      </header>

      <div className="screen-content">
        <button
          className="secondary-button button--full"
          disabled={unreadCount === 0}
          onClick={() => {
            dispatch(appActions.markAllNotificationsRead())
            onShowToast(t('state.success'))
          }}
          title={unreadCount === 0 ? t('empty.notifications.title') : undefined}
          type="button"
        >
          <CheckCheck aria-hidden="true" size={19} />
          {t('notifications.markAllRead')}
        </button>

        {notifications.length === 0 ? (
          <EmptyState
            description={t('empty.notifications.description')}
            icon={BellRing}
            title={t('empty.notifications.title')}
          />
        ) : (
          <section className="card settings-section" aria-label={t('notifications.title')}>
            {notifications.map((notification) => {
              const Icon = NOTIFICATION_ICONS[notification.type]
              const copy = localizedCopy(notification)
              return (
                <button
                  className={`notification-row${notification.isRead ? '' : ' notification-row--unread'}`}
                  key={notification.id}
                  onClick={() => openNotification(notification)}
                  type="button"
                >
                  <span className="notification-row__icon" aria-hidden="true">
                    <Icon size={19} />
                  </span>
                  <span className="notification-row__copy">
                    <strong>{copy.title}</strong>
                    <span>{copy.message}</span>
                    <span>{formatDateTime(notification.createdAt, locale)}</span>
                  </span>
                  {notification.isRead ? (
                    <ChevronRight aria-hidden="true" size={18} />
                  ) : (
                    <span aria-label={t('notifications.title')} className="notification-row__dot" />
                  )}
                </button>
              )
            })}
          </section>
        )}
      </div>

      <BottomSheet
        closeLabel={t('common.close')}
        isOpen={settingsOpen}
        onClose={() => setSettingsOpen(false)}
        title={t('notifications.settings')}
      >
        <NotificationPreferences onChange={() => onShowToast(t('toast.settingsSaved'))} />
      </BottomSheet>
    </main>
  )
}
