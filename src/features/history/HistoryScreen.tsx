import { useMemo, useState } from 'react'
import {
  ArrowLeft,
  CalendarDays,
  ChevronRight,
  Clock3,
  Plus,
  RefreshCw,
  Trash2,
} from 'lucide-react'
import { LOCALE_TAGS, createTranslator, formatEstimatedMoney, formatShortDate } from '../../localization'
import type { TranslationKey } from '../../localization'
import type { ShowToastOptions } from '../../shared/hooks/useAppToast'
import { useAppStore } from '../../store/AppStateProvider'
import { appActions } from '../../store/appReducer'
import { selectFrequentProducts, selectSortedHistory, selectStoreById } from '../../store/selectors'
import {
  ConfirmationDialog,
  EmptyState,
  IconButton,
  MemberAvatar,
  PriceLabel,
  StoreMark,
} from '../../ui'
import {
  addFrequentProductToGeneralList,
  repeatHistoryEntry,
} from './historyActions'
import './History.css'

type HistoryTab = 'purchases' | 'frequent'

export interface HistoryScreenProps {
  onBack?: () => void
  onOpenEntry: (historyId: string) => void
  onOpenList: (listId: string, storeId: string | null) => void
  onShowToast: (message: string, options?: ShowToastOptions) => void
}

export function HistoryScreen({
  onBack,
  onOpenEntry,
  onOpenList,
  onShowToast,
}: HistoryScreenProps) {
  const { state, dispatch } = useAppStore()
  const [activeTab, setActiveTab] = useState<HistoryTab>('purchases')
  const [pendingDeleteId, setPendingDeleteId] = useState<string | null>(null)
  const locale = state.settings.locale
  const localeTag = LOCALE_TAGS[locale]
  const t = useMemo(() => createTranslator(locale), [locale])
  const history = selectSortedHistory(state)
  const frequentProducts = selectFrequentProducts(state)
  const pendingDelete = history.find((entry) => entry.id === pendingDeleteId) ?? null

  const repeatEntry = (historyId: string) => {
    const entry = history.find((item) => item.id === historyId)
    if (!entry) return
    const store = selectStoreById(state, entry.storeId)
    const repeatedTitle = `${t('history.repeatList')} — ${store?.name ?? t('lists.noStore')}`
    const newListId = repeatHistoryEntry(state, dispatch, entry, repeatedTitle)
    onShowToast(t('history.repeatSuccess'), {
      actionLabel: t('common.open'),
      onAction: () => onOpenList(newListId, entry.storeId),
    })
  }

  const confirmDelete = () => {
    if (!pendingDelete) return
    dispatch(appActions.deleteHistory(pendingDelete.id))
    setPendingDeleteId(null)
    onShowToast(t('toast.historyDeleted'))
  }

  const addFrequent = (frequentProductId: string) => {
    const product = frequentProducts.find((item) => item.id === frequentProductId)
    if (!product) return
    const listId = addFrequentProductToGeneralList(
      state,
      dispatch,
      product.id,
      t('home.generalList'),
    )
    if (!listId) return
    onShowToast(t('home.addedToList', { product: product.name, list: t('home.generalList') }), {
      actionLabel: t('common.open'),
      onAction: () => onOpenList(listId, null),
    })
  }

  return (
    <main className="screen">
      <header className="app-topbar">
        {onBack ? <IconButton icon={ArrowLeft} label={t('common.back')} onClick={onBack} /> : null}
        <div className="app-topbar__title">
          <h1>{t('history.title')}</h1>
        </div>
      </header>

      <div className="screen-content">
        <div
          aria-label={t('history.title')}
          className="segmented-control"
          role="tablist"
          style={{ gridTemplateColumns: 'repeat(2, minmax(0, 1fr))' }}
        >
          <button
            aria-controls="history-purchases-panel"
            aria-selected={activeTab === 'purchases'}
            id="history-purchases-tab"
            onClick={() => setActiveTab('purchases')}
            role="tab"
            type="button"
          >
            {t('history.purchasesTab')}
          </button>
          <button
            aria-controls="history-frequent-panel"
            aria-selected={activeTab === 'frequent'}
            id="history-frequent-tab"
            onClick={() => setActiveTab('frequent')}
            role="tab"
            type="button"
          >
            {t('history.frequentTab')}
          </button>
        </div>

        {activeTab === 'purchases' ? (
          <section
            aria-labelledby="history-purchases-tab"
            className="card-stack"
            id="history-purchases-panel"
            role="tabpanel"
          >
            {history.length === 0 ? (
              <EmptyState
                description={t('empty.history.description')}
                icon={Clock3}
                title={t('empty.history.title')}
              />
            ) : (
              history.map((entry) => {
                const store = selectStoreById(state, entry.storeId)
                const storeName = store?.name ?? t('lists.noStore')
                const members = state.users.filter((user) => entry.members.includes(user.id))
                return (
                  <article className="card card--padded history-entry-card" key={entry.id}>
                    <div className="history-entry-card__top">
                      <time className="history-card__date" dateTime={entry.date}>
                        <CalendarDays aria-hidden="true" size={15} />
                        <span>{formatShortDate(entry.date, locale)}</span>
                      </time>
                      <IconButton
                        icon={ChevronRight}
                        label={`${t('common.open')}: ${storeName}`}
                        onClick={() => onOpenEntry(entry.id)}
                      />
                    </div>
                    <div className="history-entry-card__identity">
                      <StoreMark
                        color={store?.color}
                        icon={store?.icon}
                        name={storeName}
                        storeId={store?.id}
                      />
                      <div>
                        <h2>{storeName}</h2>
                        <p className="quiet">
                          {t('common.productsCount', { count: entry.products.length })}
                        </p>
                      </div>
                    </div>
                    <div className="split-row history-entry-card__purchase">
                      <div className="cluster" aria-label={t('history.members')}>
                        {members.map((member) => (
                          <MemberAvatar
                            avatarUrl={member.avatar}
                            key={member.id}
                            name={member.name}
                            size="small"
                          />
                        ))}
                      </div>
                      <PriceLabel
                        accessibleLabel={`${t('history.total')}: ${formatEstimatedMoney(entry.total, locale)}`}
                        approximate={false}
                        locale={localeTag}
                        value={entry.total}
                      />
                    </div>
                    <div className="history-entry-card__actions">
                      <button
                        className="secondary-button"
                        onClick={() => repeatEntry(entry.id)}
                        type="button"
                      >
                        <RefreshCw aria-hidden="true" size={18} />
                        {t('history.repeatList')}
                      </button>
                      <button
                        className="text-button text-button--danger"
                        onClick={() => setPendingDeleteId(entry.id)}
                        type="button"
                      >
                        <Trash2 aria-hidden="true" size={18} />
                        {t('history.deleteEntry')}
                      </button>
                    </div>
                  </article>
                )
              })
            )}
          </section>
        ) : (
          <section
            aria-labelledby="history-frequent-tab"
            className="card-stack"
            id="history-frequent-panel"
            role="tabpanel"
          >
            {frequentProducts.length === 0 ? (
              <EmptyState
                description={t('empty.frequent.description')}
                title={t('empty.frequent.title')}
              />
            ) : (
              frequentProducts.map((product) => {
                const unitKey = `units.${product.unit}` as TranslationKey
                return (
                  <article className="card card--padded section-stack" key={product.id}>
                    <div className="split-row">
                      <div>
                        <h2>{product.name}</h2>
                        <p className="quiet">
                          {t(unitKey)} · {t('common.productsCount', { count: product.timesAdded })}
                        </p>
                      </div>
                      <PriceLabel
                        accessibleLabel={formatEstimatedMoney(product.estimatedPrice, locale)}
                        locale={localeTag}
                        value={product.estimatedPrice}
                      />
                    </div>
                    <div className="split-row" style={{ flexWrap: 'wrap' }}>
                      <button
                        className="secondary-button"
                        onClick={() => addFrequent(product.id)}
                        type="button"
                      >
                        <Plus aria-hidden="true" size={18} />
                        {t('history.addAgain')}
                      </button>
                      <button
                        className="text-button text-button--danger"
                        onClick={() => {
                          dispatch(appActions.removeFrequentProduct(product.id))
                          onShowToast(t('state.success'))
                        }}
                        type="button"
                      >
                        <Trash2 aria-hidden="true" size={18} />
                        {t('common.remove')}
                      </button>
                    </div>
                  </article>
                )
              })
            )}
          </section>
        )}
      </div>

      <ConfirmationDialog
        cancelLabel={t('common.cancel')}
        confirmLabel={t('common.delete')}
        description={t('confirm.deleteHistory.description')}
        isOpen={pendingDelete !== null}
        onCancel={() => setPendingDeleteId(null)}
        onConfirm={confirmDelete}
        title={t('confirm.deleteHistory.title')}
        tone="danger"
      />
    </main>
  )
}
