import { useEffect, useId, useState } from 'react'
import { ListChecks } from 'lucide-react'
import { createTranslator, LOCALE_TAGS } from '../../localization'
import { useAppDispatch, useAppState } from '../../store/AppStateProvider'
import { appActions } from '../../store/appReducer'
import { selectSortedStores, selectUnassignedProducts } from '../../store/selectors'
import { PrimaryButton, ProductRow, SecondaryButton } from '../../ui'
import { AccessibleSheet } from '../products/AccessibleSheet'
import { formatProductQuantity } from '../products/productPresentation'
import type { FeatureFeedback } from '../products/types'

export interface DistributionSheetProps {
  isOpen: boolean
  onClose: () => void
  onDistributed?: (productIds: string[], storeId: string) => void
  onFeedback?: (feedback: FeatureFeedback) => void
}

export function DistributionSheet({
  isOpen,
  onClose,
  onDistributed,
  onFeedback,
}: DistributionSheetProps) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const t = createTranslator(state.settings.locale)
  const unassignedProducts = selectUnassignedProducts(state)
  const stores = selectSortedStores(state)
  const selectId = useId()
  const [selectedIds, setSelectedIds] = useState<Set<string>>(() => new Set())
  const [storeId, setStoreId] = useState('')

  useEffect(() => {
    if (isOpen) {
      setSelectedIds(new Set())
      setStoreId('')
    }
  }, [isOpen])

  const toggleProduct = (productId: string, selected: boolean) => {
    setSelectedIds((current) => {
      const next = new Set(current)
      if (selected) {
        next.add(productId)
      } else {
        next.delete(productId)
      }
      return next
    })
  }

  const toggleAll = () => {
    setSelectedIds((current) =>
      current.size === unassignedProducts.length
        ? new Set()
        : new Set(unassignedProducts.map((product) => product.id)),
    )
  }

  const distribute = () => {
    if (!storeId || selectedIds.size === 0) {
      return
    }
    const productIds = Array.from(selectedIds)
    const changedAt = new Date().toISOString()
    productIds.forEach((productId) => {
      dispatch(appActions.moveProduct(productId, storeId, undefined, changedAt))
    })
    onDistributed?.(productIds, storeId)
    onFeedback?.({
      message: t('distribution.success', { count: productIds.length }),
      tone: 'success',
    })
    onClose()
  }

  const footer = (
    <>
      <SecondaryButton className="secondary-button" onClick={onClose}>
        {t('common.cancel')}
      </SecondaryButton>
      <PrimaryButton
        className="primary-button"
        disabled={!storeId || selectedIds.size === 0}
        onClick={distribute}
      >
        {t('distribution.confirm')}
      </PrimaryButton>
    </>
  )

  return (
    <AccessibleSheet
      closeLabel={t('common.close')}
      description={t('distribution.description')}
      footer={footer}
      isOpen={isOpen}
      onClose={onClose}
      title={t('distribution.title')}
    >
      {unassignedProducts.length === 0 ? (
        <section className="empty-state">
          <div className="empty-state__inner">
            <span aria-hidden="true" className="empty-state__icon">
              <ListChecks size={28} />
            </span>
            <h3>{t('empty.products.title')}</h3>
            <p>{t('common.notAvailable')}</p>
          </div>
        </section>
      ) : (
        <div className="form-stack">
          <div className="split-row">
            <strong>{t('common.selected', { count: selectedIds.size })}</strong>
            <button className="text-button" onClick={toggleAll} type="button">
              {selectedIds.size === unassignedProducts.length
                ? t('distribution.clearSelection')
                : t('distribution.selectAll')}
            </button>
          </div>

          <div className="card-stack">
            {unassignedProducts.map((product) => (
              <ProductRow
                checked={selectedIds.has(product.id)}
                checkboxLabel={`${t('common.select')}: ${product.name}`}
                className={
                  selectedIds.has(product.id) ? 'product-row product-row--selected' : 'product-row'
                }
                currency={state.settings.currency}
                estimatedPrice={product.estimatedPrice}
                estimatedPriceLabel={t('products.estimatedPrice')}
                imageAlt={t('products.photoAlt', { product: product.name })}
                imageUrl={product.imageUrl}
                isPurchased={false}
                key={product.id}
                locale={LOCALE_TAGS[state.settings.locale]}
                name={product.name}
                note={product.note}
                noteLabel={t('products.note')}
                onCheckedChange={(selected) => toggleProduct(product.id, selected)}
                quantityLabel={formatProductQuantity(product, state.settings.locale, t)}
              />
            ))}
          </div>

          <div className="field">
            <label className="field__label" htmlFor={selectId}>
              {t('distribution.chooseStore')}
            </label>
            <select
              id={selectId}
              onChange={(event) => setStoreId(event.target.value)}
              required
              value={storeId}
            >
              <option disabled value="">
                {t('distribution.chooseStore')}
              </option>
              {stores.map((store) => (
                <option key={store.id} value={store.id}>
                  {store.name}
                </option>
              ))}
            </select>
            {stores.length === 0 ? (
              <span className="field__error" role="alert">
                {t('empty.stores.description')}
              </span>
            ) : null}
          </div>
        </div>
      )}
    </AccessibleSheet>
  )
}
