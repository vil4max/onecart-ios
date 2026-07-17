import { useEffect, useState } from 'react'
import type { FormEvent } from 'react'
import type { Translator } from '../../localization'
import { appActions } from '../../store/appReducer'
import { useAppDispatch, useAppState } from '../../store/AppStateProvider'
import { BottomSheet, PrimaryButton, SecondaryButton } from '../../ui'

interface CreateListSheetProps {
  isOpen: boolean
  initialStoreId?: string | null
  t: Translator
  onClose: () => void
  onCreated: (result: {
    title: string
    listId: string
    storeId: string | null
    created: boolean
  }) => void
}

export function CreateListSheet({
  initialStoreId = null,
  isOpen,
  onClose,
  onCreated,
  t,
}: CreateListSheetProps) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const [title, setTitle] = useState('')
  const [storeId, setStoreId] = useState('')
  const [showError, setShowError] = useState(false)
  const selectedStoreId = storeId || null
  const existingList = state.shoppingLists.find(
    (list) => list.status === 'active' && list.storeId === selectedStoreId,
  )

  useEffect(() => {
    if (!isOpen) return
    setTitle('')
    setStoreId(initialStoreId ?? '')
    setShowError(false)
  }, [initialStoreId, isOpen])

  const handleSubmit = (event: FormEvent) => {
    event.preventDefault()
    if (existingList) {
      onCreated({
        title: existingList.title,
        listId: existingList.id,
        storeId: existingList.storeId,
        created: false,
      })
      onClose()
      return
    }

    const normalizedTitle = title.trim()
    if (!normalizedTitle) {
      setShowError(true)
      return
    }
    const action = appActions.createList({
      title: normalizedTitle,
      storeId: selectedStoreId,
      ownerId: state.currentUserId,
      members: state.users.map((user) => user.id),
    })
    if (action.type !== 'list/create') return
    dispatch(action)
    onCreated({
      title: action.payload.title,
      listId: action.payload.id,
      storeId: action.payload.storeId,
      created: true,
    })
    onClose()
  }

  return (
    <BottomSheet
      isOpen={isOpen}
      title={t('lists.createTitle')}
      closeLabel={t('common.close')}
      onClose={onClose}
      dismissOnBackdrop={!title.trim()}
      footer={
        <>
          <SecondaryButton onClick={onClose}>{t('common.cancel')}</SecondaryButton>
          <PrimaryButton form="create-list-form" type="submit">
            {t(existingList ? 'common.open' : 'common.create')}
          </PrimaryButton>
        </>
      }
    >
      <form id="create-list-form" className="form-stack" onSubmit={handleSubmit}>
        <label className="field">
          <span className="field__label">{t('lists.name')}</span>
          <input
            autoFocus
            disabled={Boolean(existingList)}
            value={existingList?.title ?? title}
            aria-invalid={showError && !title.trim()}
            onChange={(event) => {
              setTitle(event.target.value)
              if (showError) setShowError(false)
            }}
          />
          {showError && !title.trim() ? (
            <span className="field__error" role="alert">
              {t('validation.required')}
            </span>
          ) : null}
          {existingList ? <span className="field__hint">{t('lists.activeExists')}</span> : null}
        </label>
        <label className="field">
          <span className="field__label">{t('lists.store')}</span>
          <select
            value={storeId}
            onChange={(event) => {
              setStoreId(event.target.value)
              setShowError(false)
            }}
          >
            <option value="">{t('lists.noStore')}</option>
            {state.stores.map((store) => (
              <option key={store.id} value={store.id}>
                {store.name}
              </option>
            ))}
          </select>
        </label>
      </form>
    </BottomSheet>
  )
}
