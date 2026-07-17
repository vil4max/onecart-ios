import { useMemo, useState } from 'react'
import { ArrowLeft, CheckCircle2, RefreshCw, Trash2 } from 'lucide-react'
import { LOCALE_TAGS, createTranslator, formatDate, formatEstimatedMoney } from '../../localization'
import type { TranslationKey } from '../../localization'
import type { ShowToastOptions } from '../../shared/hooks/useAppToast'
import { useAppStore } from '../../store/AppStateProvider'
import { appActions } from '../../store/appReducer'
import {
  selectHistoryEntryById,
  selectStoreById,
  selectUserById,
} from '../../store/selectors'
import {
  ConfirmationDialog,
  EmptyState,
  IconButton,
  MemberAvatar,
  PriceLabel,
} from '../../ui'
import { addHistoryProductAgain, repeatHistoryEntry } from './historyActions'

export interface HistoryDetailScreenProps {
  historyId: string
  onBack: () => void
  onOpenList: (listId: string, storeId: string | null) => void
  onShowToast: (message: string, options?: ShowToastOptions) => void
}

export function HistoryDetailScreen({
  historyId,
  onBack,
  onOpenList,
  onShowToast,
}: HistoryDetailScreenProps) {
  const { state, dispatch } = useAppStore()
  const [deleteOpen, setDeleteOpen] = useState(false)
  const locale = state.settings.locale
  const localeTag = LOCALE_TAGS[locale]
  const t = useMemo(() => createTranslator(locale), [locale])
  const entry = selectHistoryEntryById(state, historyId)

  if (!entry) {
    return (
      <main className="screen">
        <header className="app-topbar">
          <IconButton icon={ArrowLeft} label={t('common.back')} onClick={onBack} />
          <div className="app-topbar__title">
            <h1>{t('history.detailsTitle')}</h1>
          </div>
        </header>
        <EmptyState
          actionLabel={t('common.back')}
          description={t('error.notFound')}
          onAction={onBack}
          title={t('state.error.title')}
        />
      </main>
    )
  }

  const store = selectStoreById(state, entry.storeId)
  const storeName = store?.name ?? t('lists.noStore')
  const members = entry.members
    .map((memberId) => selectUserById(state, memberId))
    .filter((member) => member !== null)

  const repeatAll = () => {
    const newListId = repeatHistoryEntry(
      state,
      dispatch,
      entry,
      `${t('history.repeatList')} — ${storeName}`,
    )
    onShowToast(t('history.repeatSuccess'), {
      actionLabel: t('common.open'),
      onAction: () => onOpenList(newListId, entry.storeId),
    })
  }

  const addAgain = (productId: string) => {
    const product = entry.products.find((item) => item.id === productId)
    if (!product) return
    const listId = addHistoryProductAgain(
      state,
      dispatch,
      product,
      `${t('history.repeatList')} — ${storeName}`,
    )
    onShowToast(t('toast.productAdded'), {
      actionLabel: t('common.open'),
      onAction: () => onOpenList(listId, product.storeId),
    })
  }

  const deleteEntry = () => {
    dispatch(appActions.deleteHistory(entry.id))
    setDeleteOpen(false)
    onShowToast(t('toast.historyDeleted'))
    onBack()
  }

  return (
    <main className="screen">
      <header className="app-topbar">
        <IconButton icon={ArrowLeft} label={t('common.back')} onClick={onBack} />
        <div className="app-topbar__title">
          <p>{t('history.detailsTitle')}</p>
          <h1>{storeName}</h1>
        </div>
      </header>

      <div className="screen-content">
        <section className="card card--padded section-stack" aria-label={t('history.detailsTitle')}>
          <div className="split-row">
            <div>
              <p className="eyebrow">{t('history.date')}</p>
              <strong>{formatDate(entry.date, locale)}</strong>
            </div>
            <div style={{ textAlign: 'right' }}>
              <p className="eyebrow">{t('history.total')}</p>
              <PriceLabel
                accessibleLabel={formatEstimatedMoney(entry.total, locale)}
                approximate={false}
                locale={localeTag}
                value={entry.total}
              />
            </div>
          </div>
          <div>
            <p className="eyebrow">{t('history.members')}</p>
            <div className="cluster" style={{ marginTop: 8 }}>
              {members.map((member) => (
                <div className="cluster" key={member.id}>
                  <MemberAvatar avatarUrl={member.avatar} name={member.name} size="small" />
                  <span>{member.name}</span>
                </div>
              ))}
            </div>
          </div>
        </section>

        <section className="section-stack" aria-label={t('common.productsCount', { count: entry.products.length })}>
          {entry.products.map((product) => {
            const unitKey = `units.${product.unit}` as TranslationKey
            return (
              <article className="product-row" key={product.id}>
                <CheckCircle2 aria-hidden="true" color="var(--color-primary)" size={28} />
                <div className="product-row__body">
                  <strong className="product-row__name">{product.name}</strong>
                  <span className="product-row__meta">
                    {product.quantity} {t(unitKey)}
                  </span>
                </div>
                <div style={{ display: 'grid', justifyItems: 'end', gap: 4 }}>
                  <PriceLabel
                    accessibleLabel={formatEstimatedMoney(product.estimatedPrice, locale)}
                    locale={localeTag}
                    value={product.estimatedPrice}
                  />
                  <button className="text-button" onClick={() => addAgain(product.id)} type="button">
                    {t('history.addAgain')}
                  </button>
                </div>
              </article>
            )
          })}
        </section>

        <div className="section-stack">
          <button className="primary-button button--full" onClick={repeatAll} type="button">
            <RefreshCw aria-hidden="true" size={19} />
            {t('history.repeatList')}
          </button>
          <button
            className="danger-button button--full"
            onClick={() => setDeleteOpen(true)}
            type="button"
          >
            <Trash2 aria-hidden="true" size={19} />
            {t('history.deleteEntry')}
          </button>
        </div>
      </div>

      <ConfirmationDialog
        cancelLabel={t('common.cancel')}
        confirmLabel={t('common.delete')}
        description={t('confirm.deleteHistory.description')}
        isOpen={deleteOpen}
        onCancel={() => setDeleteOpen(false)}
        onConfirm={deleteEntry}
        title={t('confirm.deleteHistory.title')}
        tone="danger"
      />
    </main>
  )
}
