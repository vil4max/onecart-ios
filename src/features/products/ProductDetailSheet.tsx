import { useState } from 'react'
import {
  CalendarClock,
  CheckCircle2,
  CircleDollarSign,
  ExternalLink,
  Heart,
  MapPin,
  PackageOpen,
  Pencil,
  Scale,
  Shapes,
  StickyNote,
  Trash2,
} from 'lucide-react'
import { createTranslator, formatDateTime, formatEstimatedMoney } from '../../localization'
import { useAppDispatch, useAppState } from '../../store/AppStateProvider'
import { appActions } from '../../store/appReducer'
import {
  selectIsProductFrequent,
  selectProductById,
  selectStoreById,
  selectUserById,
} from '../../store/selectors'
import { PrimaryButton, ProductThumbnail, SecondaryButton } from '../../ui'
import { AccessibleSheet } from './AccessibleSheet'
import {
  CATEGORY_TRANSLATION_KEYS,
  formatProductQuantity,
} from './productPresentation'
import type { FeatureFeedback } from './types'

export interface ProductDetailSheetProps {
  isOpen: boolean
  productId: string | null
  onClose: () => void
  onEdit: (productId: string) => void
  onMove: (productId: string) => void
  onDeleted?: (productId: string) => void
  onFeedback?: (feedback: FeatureFeedback) => void
}

interface DetailRowProps {
  icon: typeof PackageOpen
  label: string
  value: string
}

function DetailRow({ icon: Icon, label, value }: DetailRowProps) {
  return (
    <div className="settings-row">
      <span aria-hidden="true" className="settings-row__icon">
        <Icon size={19} />
      </span>
      <div className="settings-row__copy">
        <strong>{label}</strong>
        <span>{value}</span>
      </div>
    </div>
  )
}

export function ProductDetailSheet({
  isOpen,
  onClose,
  onDeleted,
  onEdit,
  onFeedback,
  onMove,
  productId,
}: ProductDetailSheetProps) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const t = createTranslator(state.settings.locale)
  const product = selectProductById(state, productId)
  const [isConfirmingDelete, setIsConfirmingDelete] = useState(false)

  if (!product) {
    return (
      <AccessibleSheet
        closeLabel={t('common.close')}
        footer={
          <PrimaryButton className="primary-button button--full" onClick={onClose}>
            {t('common.close')}
          </PrimaryButton>
        }
        isOpen={isOpen}
        onClose={onClose}
        title={t('products.detailsTitle')}
      >
        <div aria-live="polite" className="card card--padded">
          <p>{t('common.notAvailable')}</p>
        </div>
      </AccessibleSheet>
    )
  }

  const store = selectStoreById(state, product.storeId)
  const addedBy = selectUserById(state, product.addedBy)
  const isFrequent = selectIsProductFrequent(state, product.id)
  const quantityLabel = formatProductQuantity(product, state.settings.locale, t)
  const priceLabel = formatEstimatedMoney(product.estimatedPrice, state.settings.locale)

  const togglePurchased = () => {
    const willBePurchased = !product.isPurchased
    dispatch(appActions.toggleProductPurchased(product.id))
    onFeedback?.({
      message: willBePurchased ? t('toast.productPurchased') : t('toast.productReturned'),
      tone: 'success',
      actionLabel: t('common.undo'),
      onAction: () => dispatch(appActions.toggleProductPurchased(product.id)),
    })
  }

  const toggleFrequent = () => {
    dispatch(appActions.toggleProductFrequent(product.id))
    onFeedback?.({
      message: isFrequent ? t('products.removeFromFrequent') : t('products.addToFrequent'),
      tone: 'success',
    })
  }

  const deleteProduct = () => {
    dispatch(appActions.deleteProduct(product.id))
    setIsConfirmingDelete(false)
    onDeleted?.(product.id)
    onFeedback?.({
      message: t('toast.productDeleted'),
      tone: 'success',
      actionLabel: t('common.undo'),
      onAction: () => dispatch(appActions.undoDeleteProduct()),
    })
    onClose()
  }

  return (
    <AccessibleSheet
      closeLabel={t('common.close')}
      footer={
        <>
          <SecondaryButton className="secondary-button" onClick={onClose}>
            {t('common.close')}
          </SecondaryButton>
          <PrimaryButton
            className="primary-button"
            leadingIcon={Pencil}
            onClick={() => onEdit(product.id)}
          >
            {t('common.edit')}
          </PrimaryButton>
        </>
      }
      isOpen={isOpen}
      onClose={() => {
        setIsConfirmingDelete(false)
        onClose()
      }}
      title={product.name}
    >
      <div className="form-stack">
        <figure className="product-detail-media">
          <ProductThumbnail
            alt={t('products.photoAlt', { product: product.name })}
            size="detail"
            src={product.imageUrl}
          />
          {product.imageSourceUrl && product.imageSourceLabel ? (
            <figcaption>
              <a
                href={product.imageSourceUrl}
                rel="noreferrer"
                target="_blank"
              >
                <span>
                  {t('products.photoSource', { source: product.imageSourceLabel })}
                </span>
                <ExternalLink aria-hidden="true" size={15} />
              </a>
            </figcaption>
          ) : null}
        </figure>

        <section aria-label={t('products.detailsTitle')} className="settings-section card">
          <DetailRow icon={Scale} label={t('products.quantity')} value={quantityLabel} />
          <DetailRow
            icon={MapPin}
            label={t('products.store')}
            value={store?.name ?? t('lists.noStore')}
          />
          <DetailRow
            icon={Shapes}
            label={t('products.category')}
            value={t(CATEGORY_TRANSLATION_KEYS[product.category])}
          />
          <DetailRow
            icon={CircleDollarSign}
            label={t('products.estimatedPrice')}
            value={priceLabel}
          />
          <DetailRow
            icon={StickyNote}
            label={t('products.note')}
            value={product.note || t('common.notSpecified')}
          />
          <DetailRow
            icon={CalendarClock}
            label={t('products.addedAt', {
              date: formatDateTime(product.createdAt, state.settings.locale),
            })}
            value={t('products.addedBy', {
              name: addedBy?.name ?? t('common.notSpecified'),
            })}
          />
        </section>

        <section aria-label={t('common.more')} className="action-list">
          <button className="action-list__item" onClick={togglePurchased} type="button">
            <span aria-hidden="true" className="action-list__icon">
              <CheckCircle2 size={20} />
            </span>
            <span className="action-list__copy">
              <strong>
                {product.isPurchased
                  ? t('products.markNotPurchased')
                  : t('products.markPurchased')}
              </strong>
            </span>
          </button>
          <button className="action-list__item" onClick={() => onMove(product.id)} type="button">
            <span aria-hidden="true" className="action-list__icon">
              <MapPin size={20} />
            </span>
            <span className="action-list__copy">
              <strong>{t('products.changeStore')}</strong>
            </span>
          </button>
          <button className="action-list__item" onClick={toggleFrequent} type="button">
            <span aria-hidden="true" className="action-list__icon">
              <Heart size={20} />
            </span>
            <span className="action-list__copy">
              <strong>
                {isFrequent ? t('products.removeFromFrequent') : t('products.addToFrequent')}
              </strong>
            </span>
          </button>
          <button
            aria-expanded={isConfirmingDelete}
            className="action-list__item"
            onClick={() => setIsConfirmingDelete(true)}
            type="button"
          >
            <span aria-hidden="true" className="action-list__icon">
              <Trash2 size={20} />
            </span>
            <span className="action-list__copy">
              <strong>{t('products.delete')}</strong>
            </span>
          </button>
        </section>

        {isConfirmingDelete ? (
          <section aria-live="assertive" className="card card--padded form-stack" role="alert">
            <div>
              <h3>{t('products.delete')}</h3>
              <p className="muted">{product.name}</p>
            </div>
            <div className="split-row">
              <SecondaryButton
                className="secondary-button"
                onClick={() => setIsConfirmingDelete(false)}
              >
                {t('common.cancel')}
              </SecondaryButton>
              <button className="danger-button" onClick={deleteProduct} type="button">
                {t('common.delete')}
              </button>
            </div>
          </section>
        ) : null}
      </div>
    </AccessibleSheet>
  )
}
