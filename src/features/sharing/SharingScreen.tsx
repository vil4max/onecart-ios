import { useEffect, useMemo, useState } from 'react'
import { ArrowLeft, RefreshCw, Trash2, UserPlus, UsersRound } from 'lucide-react'
import type { UserRole } from '../../domain/models'
import { createTranslator } from '../../localization'
import type { ShowToastOptions } from '../../shared/hooks/useAppToast'
import { useAppStore } from '../../store/AppStateProvider'
import { appActions } from '../../store/appReducer'
import { ConfirmationDialog, FilterChip, IconButton, MemberAvatar } from '../../ui'

type SharingScope = 'store' | 'general' | 'family'

interface LocalParticipant {
  id: string
  name: string
  email: string
  avatar: string | null
  role: UserRole
  pending: boolean
}

export interface SharingScreenProps {
  onBack: () => void
  onOpenList: (listId: string, storeId: string | null) => void
  onShowToast: (message: string, options?: ShowToastOptions) => void
  initialScope?: SharingScope
  initialListId?: string | null
}

export function SharingScreen({
  initialListId = null,
  initialScope = 'family',
  onBack,
  onOpenList,
  onShowToast,
}: SharingScreenProps) {
  const { state, dispatch } = useAppStore()
  const [scope, setScope] = useState<SharingScope>(initialScope)
  const [selectedStoreListId, setSelectedStoreListId] = useState(initialListId ?? '')
  const [inviteValue, setInviteValue] = useState('')
  const [inviteAttempted, setInviteAttempted] = useState(false)
  const [pendingRemoval, setPendingRemoval] = useState<LocalParticipant | null>(null)
  const locale = state.settings.locale
  const t = useMemo(() => createTranslator(locale), [locale])

  const activeLists = state.shoppingLists.filter((list) => list.status === 'active')
  const generalList = activeLists.find((list) => list.storeId === null) ?? null
  const storeLists = activeLists.filter((list) => list.storeId !== null)
  const selectedStoreListExists = storeLists.some((list) => list.id === selectedStoreListId)
  const firstStoreListId = storeLists[0]?.id ?? ''
  const selectedStoreList =
    storeLists.find((list) => list.id === selectedStoreListId) ?? storeLists[0] ?? null
  const targetList = scope === 'general' ? generalList : scope === 'store' ? selectedStoreList : null
  const targetLists = scope === 'family' ? activeLists : targetList ? [targetList] : []

  useEffect(() => {
    if (!selectedStoreListExists) {
      setSelectedStoreListId(firstStoreListId)
    }
  }, [firstStoreListId, selectedStoreListExists])

  const visibleMemberIds =
    scope === 'family' ? null : new Set(targetList?.members ?? [])
  const participants: LocalParticipant[] = state.users
    .filter((user) => visibleMemberIds === null || visibleMemberIds.has(user.id))
    .map((user) => ({
      id: user.id,
      name: user.name,
      email: user.email,
      avatar: user.avatar,
      role: user.role,
      pending: user.id.startsWith('invite-'),
    }))

  const alex = state.users.find((user) => user.name === 'Алекс')
  const syncList = scope === 'family' ? generalList ?? activeLists[0] ?? null : targetList
  const canSimulateSync = Boolean(
    alex?.role === 'editor' && syncList?.members.includes(alex.id),
  )
  const inviteIsValid = inviteValue.trim().length >= 2

  const inviteParticipant = () => {
    setInviteAttempted(true)
    if (!inviteIsValid || targetLists.length === 0) return
    const value = inviteValue.trim()
    const name = value.includes('@') ? value.split('@')[0] : value
    const email = value.includes('@') ? value : `${value.toLocaleLowerCase()}@onecart.local`
    const existingUser = state.users.find(
      (user) => user.email.toLocaleLowerCase() === email.toLocaleLowerCase(),
    )
    const action = existingUser
      ? null
      : appActions.addUser({
          id: `invite-${Date.now().toString(36)}`,
          name,
          email,
          role: 'viewer',
        })
    const userId = existingUser?.id ?? (action?.type === 'user/add' ? action.payload.id : null)
    if (!userId) return
    if (action) dispatch(action)
    targetLists.forEach((list) => dispatch(appActions.setListMember(list.id, userId, true)))
    setInviteValue('')
    setInviteAttempted(false)
    onShowToast(t('toast.memberInvited'))
  }

  const simulateSync = () => {
    if (!alex || !syncList || !canSimulateSync) return
    const listId = syncList.id
    const storeId = syncList.storeId

    const sequence =
      state.products.filter((product) => product.id.startsWith('product-sync-alex-')).length + 1
    dispatch(
      appActions.addProduct({
        id: `product-sync-alex-${sequence}`,
        name: 'Йогурт',
        quantity: 1,
        unit: 'pack',
        category: 'dairy',
        estimatedPrice: 48,
        note: '',
        storeId,
        listId,
        addedBy: alex.id,
      }),
    )
    onShowToast(t('sharing.simulatedChange', { name: alex.name }), {
      actionLabel: t('common.open'),
      onAction: () => onOpenList(listId, storeId),
    })
  }

  const removeParticipant = () => {
    if (!pendingRemoval) return
    if (scope === 'family') {
      dispatch(appActions.removeUser(pendingRemoval.id))
    } else if (targetList) {
      dispatch(appActions.setListMember(targetList.id, pendingRemoval.id, false))
    }
    setPendingRemoval(null)
    onShowToast(t('state.success'))
  }

  return (
    <main className="screen">
      <header className="app-topbar">
        <IconButton icon={ArrowLeft} label={t('common.back')} onClick={onBack} />
        <div className="app-topbar__title">
          <h1>{t('sharing.title')}</h1>
          <p>{t('mock.localData')}</p>
        </div>
      </header>

      <div className="screen-content">
        <section className="section-stack">
          <h2>{t('common.share')}</h2>
          <div className="chip-row" aria-label={t('common.share')}>
            <FilterChip
              label={t('sharing.shareStore')}
              onSelectedChange={() => setScope('store')}
              selected={scope === 'store'}
            />
            <FilterChip
              label={t('sharing.shareGeneralList')}
              onSelectedChange={() => setScope('general')}
              selected={scope === 'general'}
            />
            <FilterChip
              label={t('sharing.shareFamily')}
              onSelectedChange={() => setScope('family')}
              selected={scope === 'family'}
            />
          </div>
          {scope === 'store' ? (
            <label className="field">
              <span className="field__label">{t('lists.store')}</span>
              <select
                disabled={storeLists.length === 0}
                onChange={(event) => setSelectedStoreListId(event.currentTarget.value)}
                value={selectedStoreList?.id ?? ''}
              >
                {storeLists.length === 0 ? (
                  <option value="">{t('common.notAvailable')}</option>
                ) : null}
                {storeLists.map((list) => {
                  const store = state.stores.find((item) => item.id === list.storeId)
                  return (
                    <option key={list.id} value={list.id}>
                      {store?.name ?? list.title}
                    </option>
                  )
                })}
              </select>
            </label>
          ) : null}
        </section>

        <section className="settings-section">
          <h2 className="settings-section__title">{t('sharing.participants')}</h2>
          <div className="card">
            {participants.map((participant) => {
              const isOwner = participant.role === 'owner'
              return (
                <div className="member-row" key={participant.id}>
                  <MemberAvatar
                    avatarUrl={participant.avatar}
                    name={participant.name}
                    size="medium"
                    statusLabel={
                      participant.pending
                        ? t('sharing.status.pending')
                        : t('sharing.status.active')
                    }
                  />
                  <div className="settings-row__copy">
                    <strong>{participant.name}</strong>
                    <span>{participant.email}</span>
                    <span>
                      {participant.pending
                        ? t('sharing.status.pending')
                        : t('sharing.status.active')}
                    </span>
                  </div>
                  <div style={{ display: 'grid', justifyItems: 'end', gap: 4 }}>
                    {isOwner ? (
                      <span className="badge">{t('sharing.owner')}</span>
                    ) : (
                      <select
                        aria-label={`${t('sharing.accessRights')}: ${participant.name}`}
                        onChange={(event) =>
                          dispatch(
                            appActions.setUserRole(
                              participant.id,
                              event.currentTarget.value as UserRole,
                            ),
                          )
                        }
                        value={participant.role}
                      >
                        <option value="editor">{t('sharing.editor')}</option>
                        <option value="viewer">{t('sharing.viewer')}</option>
                      </select>
                    )}
                    {!isOwner ? (
                      <button
                        aria-label={`${t('sharing.removeMember')}: ${participant.name}`}
                        className="text-button text-button--danger"
                        onClick={() => setPendingRemoval(participant)}
                        type="button"
                      >
                        <Trash2 aria-hidden="true" size={17} />
                      </button>
                    ) : null}
                  </div>
                </div>
              )
            })}
          </div>
        </section>

        <section className="card card--padded section-stack">
          <div className="cluster">
            <UserPlus aria-hidden="true" size={20} />
            <h2>{t('sharing.invite')}</h2>
          </div>
          <label className="field">
            <span className="field__label">{t('sharing.invitePlaceholder')}</span>
            <input
              aria-invalid={inviteAttempted && !inviteIsValid}
              onChange={(event) => setInviteValue(event.currentTarget.value)}
              placeholder={t('sharing.invitePlaceholder')}
              value={inviteValue}
            />
            {inviteAttempted && !inviteIsValid ? (
              <span className="field__error" role="alert">
                {t('validation.required')}
              </span>
            ) : null}
          </label>
          <button className="secondary-button button--full" onClick={inviteParticipant} type="button">
            <UserPlus aria-hidden="true" size={18} />
            {t('sharing.invite')}
          </button>
        </section>

        <section className="card card--padded section-stack">
          <div className="cluster">
            <UsersRound aria-hidden="true" size={20} />
            <div>
              <h2>{t('sharing.simulateChange')}</h2>
              <p className="quiet">{t('mock.localData')}</p>
            </div>
          </div>
          <button
            className="primary-button button--full"
            disabled={!canSimulateSync}
            onClick={simulateSync}
            type="button"
          >
            <RefreshCw aria-hidden="true" size={18} />
            {t('sharing.simulateChange')}
          </button>
        </section>
      </div>

      <ConfirmationDialog
        cancelLabel={t('common.cancel')}
        confirmLabel={t('common.remove')}
        description={t('confirm.removeMember.description', {
          name: pendingRemoval?.name ?? '',
        })}
        isOpen={pendingRemoval !== null}
        onCancel={() => setPendingRemoval(null)}
        onConfirm={removeParticipant}
        title={t('confirm.removeMember.title')}
        tone="danger"
      />
    </main>
  )
}
