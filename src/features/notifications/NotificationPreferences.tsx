import { useMemo } from 'react'
import { Bell, BellRing, VolumeX } from 'lucide-react'
import { createTranslator } from '../../localization'
import { useAppStore } from '../../store/AppStateProvider'
import { appActions } from '../../store/appReducer'
import { FilterChip } from '../../ui'

export interface NotificationPreferencesProps {
  onChange?: () => void
}

export function NotificationPreferences({ onChange }: NotificationPreferencesProps) {
  const { state, dispatch } = useAppStore()
  const locale = state.settings.locale
  const t = useMemo(() => createTranslator(locale), [locale])
  const mutedIds = new Set(state.notificationSettings.mutedListIds)

  const setMode = (mode: 'all' | 'important') => {
    dispatch(appActions.setNotificationMode(mode))
    onChange?.()
  }

  return (
    <div className="section-stack">
      <div className="chip-row" aria-label={t('notifications.settings')}>
        <FilterChip
          icon={BellRing}
          label={t('notifications.mode.all')}
          onSelectedChange={() => setMode('all')}
          selected={state.notificationSettings.mode === 'all'}
        />
        <FilterChip
          icon={Bell}
          label={t('notifications.mode.important')}
          onSelectedChange={() => setMode('important')}
          selected={state.notificationSettings.mode === 'important'}
        />
      </div>

      <div className="card settings-section">
        {state.shoppingLists
          .filter((list) => list.status === 'active')
          .map((list) => {
            const isMuted = mutedIds.has(list.id)
            return (
              <button
                aria-checked={isMuted}
                className="settings-row"
                key={list.id}
                onClick={() => {
                  dispatch(appActions.setListNotificationsMuted(list.id, !isMuted))
                  onChange?.()
                }}
                role="switch"
                type="button"
              >
                <span className="settings-row__icon" aria-hidden="true">
                  <VolumeX size={19} />
                </span>
                <span className="settings-row__copy">
                  <strong>{list.title}</strong>
                  <span>{t('notifications.muteList')}</span>
                </span>
                <span className={isMuted ? 'badge badge--warning' : 'badge badge--quiet'}>
                  {isMuted ? t('common.disabled') : t('common.enabled')}
                </span>
              </button>
            )
          })}
      </div>
    </div>
  )
}
