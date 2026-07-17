import { useState } from 'react'
import { Bell, ListChecks, Plus } from 'lucide-react'
import {
  BottomSheet,
  EmptyState,
  IconButton,
  PriceLabel,
  SectionHeader,
  ShoppingListCard,
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
  selectCurrentUser,
  selectActiveLists,
  selectFrequentProducts,
  selectLocale,
  selectOverallSummary,
  selectStoreOverviews,
  selectUnreadNotificationCount,
  type StoreListOverview,
} from '../../store/selectors'
import { formatStoreLocation } from '../stores/storeLocation'
import './HomeScreen.css'

export interface HomeScreenProps {
  onOpenGeneralList: () => void
  onOpenStore: (storeId: string) => void
  onOpenCatalog: () => void
  onOpenNotifications: () => void
  onToast: (message: string) => void
}

function statusLabel(
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

export function HomeScreen({
  onOpenCatalog,
  onOpenGeneralList,
  onOpenNotifications,
  onOpenStore,
  onToast,
}: HomeScreenProps) {
  const dispatch = useAppDispatch()
  const locale = useAppSelector(selectLocale)
  const currentUser = useAppSelector(selectCurrentUser)
  const activeLists = useAppSelector(selectActiveLists)
  const overallSummary = useAppSelector(selectOverallSummary)
  const storeOverviews = useAppSelector(selectStoreOverviews)
  const frequentProducts = useAppSelector(selectFrequentProducts)
  const unreadCount = useAppSelector(selectUnreadNotificationCount)
  const [pendingFrequentId, setPendingFrequentId] = useState<string | null>(null)
  const t = createTranslator(locale)
  const localeTag = LOCALE_TAGS[locale]
  const progressLabel = t('a11y.progress', {
    purchased: overallSummary.purchasedCount,
    total: overallSummary.itemCount,
  })
  const notificationLabel =
    unreadCount > 0
      ? `${t('a11y.openNotifications')}: ${unreadCount}`
      : t('a11y.openNotifications')
  const canQuickAdd = Boolean(activeLists.length > 0 && currentUser)
  const pendingFrequent = frequentProducts.find((item) => item.id === pendingFrequentId) ?? null

  const addFrequentProduct = (frequentProductId: string, listId: string) => {
    const item = frequentProducts.find((candidate) => candidate.id === frequentProductId)
    const list = activeLists.find((candidate) => candidate.id === listId)
    if (!item || !list || !currentUser) {
      onToast(
        t('state.disabledReason', {
          reason: t('empty.lists.title'),
        }),
      )
      return
    }

    dispatch(
      appActions.addProduct({
        name: item.name,
        quantity: 1,
        unit: item.unit,
        category: item.category,
        estimatedPrice: item.estimatedPrice,
        storeId: list.storeId,
        listId: list.id,
        addedBy: currentUser.id,
      }),
    )
    dispatch(appActions.recordFrequentUse(item.id))
    setPendingFrequentId(null)
    onToast(
      t('home.addedToList', {
        product: item.name,
        list: list.title,
      }),
    )
  }

  return (
    <main className="screen home-screen">
      <header className="app-topbar">
        <div className="app-topbar__title home-screen__heading">
          <p>{t('home.greeting')}</p>
          <h1>{t('home.title')}</h1>
        </div>
        <div className="home-screen__notifications">
          <IconButton icon={Bell} label={notificationLabel} onClick={onOpenNotifications} />
          {unreadCount > 0 ? (
            <span aria-hidden="true" className="home-screen__notification-badge">
              {unreadCount > 99 ? '99+' : unreadCount}
            </span>
          ) : null}
        </div>
      </header>

      <div className="screen-content">
        <ShoppingListCard
          estimatedTotal={overallSummary.estimatedTotal}
          estimatedTotalLabel={formatEstimatedMoney(overallSummary.estimatedTotal, locale)}
          itemCountLabel={t('common.productsCount', { count: overallSummary.itemCount })}
          locale={localeTag}
          onOpen={onOpenGeneralList}
          openLabel={t('home.openGeneralList')}
          progress={overallSummary.progress}
          progressLabel={progressLabel}
          purchasedCountLabel={t('common.purchasedProgress', {
            purchased: overallSummary.purchasedCount,
            total: overallSummary.itemCount,
          })}
          title={t('home.generalList')}
        />

        <section aria-labelledby="home-store-lists" className="section-stack">
          <SectionHeader
            actionIcon={Plus}
            actionLabel={t('stores.add')}
            onAction={onOpenCatalog}
            title={t('home.storeLists')}
          />
          <span className="sr-only" id="home-store-lists">
            {t('home.storeLists')}
          </span>
          {storeOverviews.length > 0 ? (
            <div className="card-stack">
              {storeOverviews.map((overview) => {
                const storeProgressLabel = t('a11y.progress', {
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
                    moreLabel={t('a11y.openMoreMenu')}
                    name={overview.store.name}
                    onOpen={() => onOpenStore(overview.store.id)}
                    openLabel={t('stores.openList')}
                    pinnedLabel={t('common.pin')}
                    progress={overview.summary.progress}
                    progressLabel={storeProgressLabel}
                    statusLabel={statusLabel(overview, t)}
                    storeId={overview.store.id}
                  />
                )
              })}
            </div>
          ) : (
            <EmptyState
              actionLabel={t('stores.add')}
              description={t('empty.stores.description')}
              onAction={onOpenCatalog}
              title={t('empty.stores.title')}
            />
          )}
        </section>

        <section aria-labelledby="home-frequent-products" className="section-stack">
          <SectionHeader title={t('home.frequentProducts')} />
          <span className="sr-only" id="home-frequent-products">
            {t('home.frequentProducts')}
          </span>
          {frequentProducts.length > 0 ? (
            <div className="frequent-rail">
              {frequentProducts.map((item) => (
                <button
                  aria-label={`${t('common.add')}: ${item.name}`}
                  className="frequent-item"
                  disabled={!canQuickAdd}
                  key={item.id}
                  onClick={() => setPendingFrequentId(item.id)}
                  title={
                    canQuickAdd
                      ? `${t('common.add')}: ${item.name}`
                      : t('state.disabledReason', { reason: t('empty.lists.title') })
                  }
                  type="button"
                >
                  <span className="home-screen__frequent-copy">
                    <strong>{item.name}</strong>
                    <PriceLabel
                      accessibleLabel={formatEstimatedMoney(item.estimatedPrice, locale)}
                      locale={localeTag}
                      value={item.estimatedPrice}
                    />
                  </span>
                  <span aria-hidden="true" className="frequent-item__add">
                    <Plus size={17} />
                  </span>
                </button>
              ))}
            </div>
          ) : (
            <p className="muted home-screen__empty-copy">{t('empty.frequent.description')}</p>
          )}
          {!canQuickAdd && frequentProducts.length > 0 ? (
            <p className="quiet" role="status">
              {t('state.disabledReason', { reason: t('empty.lists.title') })}
            </p>
          ) : null}
        </section>
      </div>

      <BottomSheet
        closeLabel={t('common.close')}
        description={pendingFrequent?.name}
        isOpen={pendingFrequent !== null}
        onClose={() => setPendingFrequentId(null)}
        title={t('home.chooseDestination')}
      >
        <div className="action-list">
          {activeLists.map((list) => {
            const store = list.storeId
              ? storeOverviews.find((overview) => overview.store.id === list.storeId)?.store
              : null
            return (
              <button
                className="action-list__item"
                key={list.id}
                onClick={() => pendingFrequent && addFrequentProduct(pendingFrequent.id, list.id)}
                type="button"
              >
                <span aria-hidden="true" className="action-list__icon">
                  <ListChecks size={19} />
                </span>
                <span className="action-list__copy">
                  <strong>{store?.name ?? t('home.generalList')}</strong>
                  <span>{list.title}</span>
                </span>
              </button>
            )
          })}
        </div>
      </BottomSheet>
    </main>
  )
}
