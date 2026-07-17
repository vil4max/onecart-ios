import { useState, type CSSProperties, type FormEvent } from 'react'
import {
  Check,
  ChevronRight,
  ExternalLink,
  MapPin,
  Palette,
  Pencil,
  Pin,
  PinOff,
  Plus,
  Store as StoreIcon,
  Trash2,
} from 'lucide-react'
import type { Store } from '../../domain/models'
import {
  BottomSheet,
  ConfirmationDialog,
  EmptyState,
  IconButton,
  PrimaryButton,
  SecondaryButton,
  StoreCard,
} from '../../ui'
import {
  LOCALE_TAGS,
  createTranslator,
  formatEstimatedMoney,
} from '../../localization'
import { appActions } from '../../store/appReducer'
import { useAppDispatch, useAppSelector } from '../../store/AppStateProvider'
import {
  selectLocale,
  selectStoreOverviews,
  type StoreListOverview,
} from '../../store/selectors'
import { StoreLocationFields } from './StoreLocationFields'
import { formatStoreLocation } from './storeLocation'
import './Stores.css'

export interface StoresScreenProps {
  onOpenStore: (storeId: string) => void
  onOpenCatalog: () => void
  onToast: (message: string) => void
}

type StoreSheetMode = 'actions' | 'rename' | 'location' | 'color'

const STORE_COLORS = [
  '#34785B',
  '#4F6D8A',
  '#9A6547',
  '#8B5D75',
  '#6D628A',
  '#58746D',
] as const

function overviewStatusLabel(
  overview: StoreListOverview,
  t: ReturnType<typeof createTranslator>,
): string {
  switch (overview.status) {
    case 'active':
      return t('stores.status.active')
    case 'completed':
      return t('stores.status.completed')
    case 'empty':
      return t('stores.status.empty')
  }
}

export function StoresScreen({ onOpenCatalog, onOpenStore, onToast }: StoresScreenProps) {
  const dispatch = useAppDispatch()
  const locale = useAppSelector(selectLocale)
  const storeOverviews = useAppSelector(selectStoreOverviews)
  const [activeStoreId, setActiveStoreId] = useState<string | null>(null)
  const [sheetMode, setSheetMode] = useState<StoreSheetMode>('actions')
  const [renameValue, setRenameValue] = useState('')
  const [renameAttempted, setRenameAttempted] = useState(false)
  const [locationCity, setLocationCity] = useState('')
  const [locationAddress, setLocationAddress] = useState('')
  const [locationLatitude, setLocationLatitude] = useState<number | null>(null)
  const [locationLongitude, setLocationLongitude] = useState<number | null>(null)
  const [pendingDelete, setPendingDelete] = useState<Store | null>(null)
  const t = createTranslator(locale)
  const localeTag = LOCALE_TAGS[locale]
  const activeOverview =
    storeOverviews.find((overview) => overview.store.id === activeStoreId) ?? null
  const activeStore = activeOverview?.store ?? null

  const closeSheet = () => {
    setActiveStoreId(null)
    setSheetMode('actions')
    setRenameAttempted(false)
  }

  const openStoreActions = (store: Store) => {
    setRenameValue(store.name)
    setLocationCity(store.city ?? '')
    setLocationAddress(store.address ?? '')
    setLocationLatitude(store.latitude ?? null)
    setLocationLongitude(store.longitude ?? null)
    setRenameAttempted(false)
    setSheetMode('actions')
    setActiveStoreId(store.id)
  }

  const saveRename = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setRenameAttempted(true)
    const name = renameValue.trim()
    if (!activeStore || !name) return

    dispatch(appActions.updateStore(activeStore.id, { name }))
    onToast(t('toast.storeUpdated'))
    closeSheet()
  }

  const applyColor = (color: string) => {
    if (!activeStore) return
    dispatch(appActions.updateStore(activeStore.id, { color }))
    onToast(t('toast.storeUpdated'))
  }

  const saveLocation = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (!activeStore) return
    dispatch(
      appActions.updateStore(activeStore.id, {
        city: locationCity.trim() || null,
        address: locationAddress.trim() || null,
        latitude: locationLatitude,
        longitude: locationLongitude,
      }),
    )
    onToast(t('toast.storeUpdated'))
    closeSheet()
  }

  const togglePinned = () => {
    if (!activeStore) return
    dispatch(appActions.setStorePinned(activeStore.id, !activeStore.isPinned))
    onToast(t('toast.storeUpdated'))
    closeSheet()
  }

  const openExternalApp = () => {
    if (!activeStore?.externalAppUrl || typeof window === 'undefined') {
      onToast(t('stores.externalAppUnavailable'))
      return
    }

    try {
      const url = new URL(activeStore.externalAppUrl)
      if (url.protocol !== 'https:' && url.protocol !== 'http:') {
        throw new Error('Unsupported external store URL')
      }
      window.open(url.toString(), '_blank', 'noopener,noreferrer')
      closeSheet()
    } catch {
      onToast(t('stores.externalAppUnavailable'))
    }
  }

  const requestDelete = () => {
    if (!activeStore) return
    setPendingDelete(activeStore)
    closeSheet()
  }

  const confirmDelete = () => {
    if (!pendingDelete) return
    dispatch(appActions.deleteStore(pendingDelete.id))
    onToast(t('toast.storeDeleted'))
    setPendingDelete(null)
  }

  const sheetTitle =
    sheetMode === 'rename'
      ? t('stores.menu.rename')
      : sheetMode === 'location'
        ? t('stores.menu.changeLocation')
        : sheetMode === 'color'
          ? t('stores.menu.changeColor')
          : activeStore?.name ?? t('stores.title')

  return (
    <main className="screen stores-screen">
      <header className="app-topbar">
        <div className="app-topbar__title">
          <h1>{t('stores.title')}</h1>
        </div>
        <IconButton icon={Plus} label={t('stores.add')} onClick={onOpenCatalog} />
      </header>

      {storeOverviews.length > 0 ? (
        <div className="store-grid">
          {storeOverviews.map((overview) => {
            const progressLabel = t('a11y.progress', {
              purchased: overview.summary.purchasedCount,
              total: overview.summary.itemCount,
            })
            return (
              <StoreCard
                color={overview.store.color}
                estimatedTotal={overview.summary.estimatedTotal}
                estimatedTotalLabel={formatEstimatedMoney(
                  overview.summary.estimatedTotal,
                  locale,
                )}
                icon={overview.store.icon}
                isPinned={overview.store.isPinned}
                itemCountLabel={t('common.productsCount', {
                  count: overview.summary.itemCount,
                })}
                key={overview.store.id}
                locale={localeTag}
                locationLabel={formatStoreLocation(overview.store) ?? undefined}
                moreLabel={`${t('a11y.openMoreMenu')}: ${overview.store.name}`}
                name={overview.store.name}
                onMore={() => openStoreActions(overview.store)}
                onOpen={() => onOpenStore(overview.store.id)}
                openLabel={t('stores.openList')}
                pinnedLabel={t('common.pin')}
                progress={overview.summary.progress}
                progressLabel={progressLabel}
                statusLabel={overviewStatusLabel(overview, t)}
                storeId={overview.store.id}
              />
            )
          })}
        </div>
      ) : (
        <EmptyState
          actionLabel={t('stores.add')}
          description={t('empty.stores.description')}
          icon={StoreIcon}
          onAction={onOpenCatalog}
          title={t('empty.stores.title')}
        />
      )}

      {storeOverviews.length > 0 ? (
        <button
          className="stores-screen__add-card card card--interactive"
          onClick={onOpenCatalog}
          type="button"
        >
          <span aria-hidden="true" className="stores-screen__add-icon">
            <Plus size={22} />
          </span>
          <span>
            <strong>{t('stores.add')}</strong>
            <small>{t('storeCatalog.popular')}</small>
          </span>
          <ChevronRight aria-hidden="true" size={20} />
        </button>
      ) : null}

      <BottomSheet
        className="stores-screen__sheet"
        closeLabel={t('a11y.closeSheet')}
        description={activeStore ? (formatStoreLocation(activeStore) ?? undefined) : undefined}
        dismissOnBackdrop={sheetMode === 'actions'}
        isOpen={activeStore !== null}
        onClose={closeSheet}
        title={sheetTitle}
      >
        {activeStore && sheetMode === 'actions' ? (
          <div className="action-list">
            <button
              className="action-list__item"
              onClick={() => {
                setRenameValue(activeStore.name)
                setRenameAttempted(false)
                setSheetMode('rename')
              }}
              type="button"
            >
              <span aria-hidden="true" className="action-list__icon">
                <Pencil size={19} />
              </span>
              <span className="action-list__copy">
                <strong>{t('stores.menu.rename')}</strong>
                <span>{activeStore.name}</span>
              </span>
              <ChevronRight aria-hidden="true" size={18} />
            </button>

            <button
              className="action-list__item"
              onClick={() => setSheetMode('location')}
              type="button"
            >
              <span aria-hidden="true" className="action-list__icon">
                <MapPin size={19} />
              </span>
              <span className="action-list__copy">
                <strong>{t('stores.menu.changeLocation')}</strong>
                <span>
                  {formatStoreLocation(activeStore) ?? t('stores.location.notSpecified')}
                </span>
              </span>
              <ChevronRight aria-hidden="true" size={18} />
            </button>

            <button
              className="action-list__item"
              onClick={() => setSheetMode('color')}
              type="button"
            >
              <span aria-hidden="true" className="action-list__icon">
                <Palette size={19} />
              </span>
              <span className="action-list__copy">
                <strong>{t('stores.menu.changeColor')}</strong>
                <span>{t('storeForm.color')}</span>
              </span>
              <ChevronRight aria-hidden="true" size={18} />
            </button>

            <button className="action-list__item" onClick={togglePinned} type="button">
              <span aria-hidden="true" className="action-list__icon">
                {activeStore.isPinned ? <PinOff size={19} /> : <Pin size={19} />}
              </span>
              <span className="action-list__copy">
                <strong>
                  {activeStore.isPinned ? t('stores.menu.unpin') : t('stores.menu.pin')}
                </strong>
                <span>{t('home.storeLists')}</span>
              </span>
            </button>

            <button className="action-list__item" onClick={openExternalApp} type="button">
              <span aria-hidden="true" className="action-list__icon">
                <ExternalLink size={19} />
              </span>
              <span className="action-list__copy">
                <strong>{t('stores.menu.openOfficialApp')}</strong>
                <span>
                  {activeStore.externalAppUrl
                    ? t('common.open')
                    : t('stores.externalAppUnavailable')}
                </span>
              </span>
            </button>

            <button
              className="action-list__item stores-screen__danger-action"
              onClick={requestDelete}
              type="button"
            >
              <span aria-hidden="true" className="action-list__icon">
                <Trash2 size={19} />
              </span>
              <span className="action-list__copy">
                <strong>{t('stores.menu.delete')}</strong>
                <span>{t('confirm.deleteStore.description')}</span>
              </span>
            </button>
          </div>
        ) : null}

        {activeStore && sheetMode === 'rename' ? (
          <form className="form-stack" onSubmit={saveRename}>
            <label className="field">
              <span className="field__label">{t('storeForm.name')}</span>
              <input
                aria-invalid={renameAttempted && !renameValue.trim() ? true : undefined}
                autoFocus
                maxLength={60}
                onChange={(event) => setRenameValue(event.currentTarget.value)}
                value={renameValue}
              />
              {renameAttempted && !renameValue.trim() ? (
                <span className="field__error" role="alert">
                  {t('validation.nameRequired')}
                </span>
              ) : null}
            </label>
            <div className="stores-screen__sheet-actions">
              <SecondaryButton onClick={() => setSheetMode('actions')}>
                {t('common.back')}
              </SecondaryButton>
              <PrimaryButton disabled={!renameValue.trim()} type="submit">
                {t('common.save')}
              </PrimaryButton>
            </div>
          </form>
        ) : null}

        {activeStore && sheetMode === 'color' ? (
          <div className="form-stack">
            <div aria-label={t('storeForm.color')} className="color-options" role="group">
              {STORE_COLORS.map((color) => (
                <button
                  aria-label={`${t('storeForm.color')} ${color}`}
                  aria-pressed={activeStore.color.toLowerCase() === color.toLowerCase()}
                  className="color-option"
                  key={color}
                  onClick={() => applyColor(color)}
                  style={{ '--option-color': color } as CSSProperties}
                  type="button"
                >
                  {activeStore.color.toLowerCase() === color.toLowerCase() ? (
                    <Check aria-hidden="true" size={18} />
                  ) : null}
                </button>
              ))}
            </div>
            <SecondaryButton onClick={() => setSheetMode('actions')}>
              {t('common.back')}
            </SecondaryButton>
          </div>
        ) : null}

        {activeStore && sheetMode === 'location' ? (
          <form className="form-stack" onSubmit={saveLocation}>
            <StoreLocationFields
              address={locationAddress}
              city={locationCity}
              latitude={locationLatitude}
              longitude={locationLongitude}
              onAddressChange={setLocationAddress}
              onCityChange={setLocationCity}
              onCoordinatesChange={(latitude, longitude) => {
                setLocationLatitude(latitude)
                setLocationLongitude(longitude)
              }}
              t={t}
            />
            <div className="stores-screen__sheet-actions">
              <SecondaryButton onClick={() => setSheetMode('actions')}>
                {t('common.back')}
              </SecondaryButton>
              <PrimaryButton type="submit">{t('common.save')}</PrimaryButton>
            </div>
          </form>
        ) : null}
      </BottomSheet>

      <ConfirmationDialog
        cancelLabel={t('common.cancel')}
        confirmLabel={t('common.delete')}
        description={t('confirm.deleteStore.description')}
        isOpen={pendingDelete !== null}
        onCancel={() => setPendingDelete(null)}
        onConfirm={confirmDelete}
        title={t('confirm.deleteStore.title')}
        tone="danger"
      />
    </main>
  )
}
