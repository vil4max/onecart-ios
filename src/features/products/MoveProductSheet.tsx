import { useEffect, useId, useState } from 'react'
import { MapPin } from 'lucide-react'
import { createTranslator } from '../../localization'
import { useAppDispatch, useAppState } from '../../store/AppStateProvider'
import { appActions } from '../../store/appReducer'
import { selectProductById, selectSortedStores, selectStoreById } from '../../store/selectors'
import { PrimaryButton, SecondaryButton, StoreMark } from '../../ui'
import { AccessibleSheet } from './AccessibleSheet'
import type { FeatureFeedback } from './types'

const UNASSIGNED_VALUE = '__unassigned__'

export interface MoveProductSheetProps {
  isOpen: boolean
  productId: string | null
  onClose: () => void
  onMoved?: (productId: string, destinationStoreId: string | null) => void
  onFeedback?: (feedback: FeatureFeedback) => void
}

export function MoveProductSheet({
  isOpen,
  onClose,
  onFeedback,
  onMoved,
  productId,
}: MoveProductSheetProps) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const t = createTranslator(state.settings.locale)
  const product = selectProductById(state, productId)
  const stores = selectSortedStores(state)
  const currentStore = selectStoreById(state, product?.storeId ?? null)
  const groupName = useId()
  const [selectedValue, setSelectedValue] = useState(UNASSIGNED_VALUE)

  useEffect(() => {
    if (isOpen) {
      setSelectedValue(product?.storeId ?? UNASSIGNED_VALUE)
    }
  }, [isOpen, product?.storeId])

  const destinationStoreId =
    selectedValue === UNASSIGNED_VALUE ? null : selectedValue
  const isSameDestination = destinationStoreId === (product?.storeId ?? null)

  const moveProduct = () => {
    if (!product || isSameDestination) {
      return
    }
    const destination = selectStoreById(state, destinationStoreId)
    dispatch(appActions.moveProduct(product.id, destinationStoreId))
    onMoved?.(product.id, destinationStoreId)
    onFeedback?.({
      message: t('moveProduct.success', {
        store: destination?.name ?? t('moveProduct.unassigned'),
      }),
      tone: 'success',
      actionLabel: t('common.undo'),
      onAction: () => dispatch(appActions.undoMoveProduct()),
    })
    onClose()
  }

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
        title={t('moveProduct.title')}
      >
        <div aria-live="polite" className="card card--padded">
          <p>{t('common.notAvailable')}</p>
        </div>
      </AccessibleSheet>
    )
  }

  return (
    <AccessibleSheet
      closeLabel={t('common.close')}
      description={product.name}
      footer={
        <>
          <SecondaryButton className="secondary-button" onClick={onClose}>
            {t('common.cancel')}
          </SecondaryButton>
          <PrimaryButton
            className="primary-button"
            disabled={isSameDestination}
            onClick={moveProduct}
          >
            {t('moveProduct.confirm')}
          </PrimaryButton>
        </>
      }
      isOpen={isOpen}
      onClose={onClose}
      title={t('moveProduct.title')}
    >
      <div className="form-stack">
        <section className="card card--padded">
          <p className="eyebrow">{t('moveProduct.currentStore')}</p>
          <div className="cluster">
            <MapPin aria-hidden="true" size={18} />
            <strong>{currentStore?.name ?? t('moveProduct.unassigned')}</strong>
          </div>
        </section>

        <fieldset className="form-stack">
          <legend className="field__label">{t('moveProduct.destination')}</legend>
          <div className="action-list">
            <label className="action-list__item">
              <span aria-hidden="true" className="action-list__icon">
                <MapPin size={20} />
              </span>
              <span className="action-list__copy">
                <strong>{t('moveProduct.unassigned')}</strong>
              </span>
              <input
                checked={selectedValue === UNASSIGNED_VALUE}
                name={groupName}
                onChange={() => setSelectedValue(UNASSIGNED_VALUE)}
                type="radio"
                value={UNASSIGNED_VALUE}
              />
            </label>
            {stores.map((store) => (
              <label className="action-list__item" key={store.id}>
                <StoreMark
                  color={store.color}
                  icon={store.icon}
                  name={store.name}
                  size="compact"
                  storeId={store.id}
                />
                <span className="action-list__copy">
                  <strong>{store.name}</strong>
                  {store.address ? <span>{store.address}</span> : null}
                </span>
                <input
                  checked={selectedValue === store.id}
                  name={groupName}
                  onChange={() => setSelectedValue(store.id)}
                  type="radio"
                  value={store.id}
                />
              </label>
            ))}
          </div>
        </fieldset>

        {isSameDestination ? (
          <p aria-live="polite" className="field__hint">
            {t('moveProduct.sameStore')}
          </p>
        ) : null}
      </div>
    </AccessibleSheet>
  )
}
