import { ArrowLeft, ListChecks, Plus } from 'lucide-react'
import { createTranslator } from '../../localization'
import { useAppDispatch, useAppState } from '../../store/AppStateProvider'
import { appActions } from '../../store/appReducer'
import {
  selectActiveProducts,
  selectGeneralList,
  selectProductsGroupedByStore,
  selectUnassignedProducts,
} from '../../store/selectors'
import { PrimaryButton, SecondaryButton } from '../../ui'
import type { FeatureFeedback, ProductEditorContext } from '../products/types'
import { ShoppingProductRow } from './ShoppingProductRow'

export interface GeneralListScreenProps {
  onBack: () => void
  onAddProduct: (context: ProductEditorContext) => void
  onOpenProduct: (productId: string) => void
  onMoveProduct: (productId: string) => void
  onOpenDistribution: () => void
  onFeedback?: (feedback: FeatureFeedback) => void
  onProductPurchaseChanged?: (productId: string, isPurchased: boolean) => void
}

export function GeneralListScreen({
  onAddProduct,
  onBack,
  onFeedback,
  onMoveProduct,
  onOpenDistribution,
  onOpenProduct,
  onProductPurchaseChanged,
}: GeneralListScreenProps) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const t = createTranslator(state.settings.locale)
  const generalList = selectGeneralList(state)
  const products = selectActiveProducts(state)
  const unassigned = selectUnassignedProducts(state)
  const storeGroups = selectProductsGroupedByStore(state).filter((group) => group.store !== null)

  const togglePurchased = (productId: string) => {
    const product = state.products.find((item) => item.id === productId)
    if (!product) {
      return
    }
    const willBePurchased = !product.isPurchased
    dispatch(appActions.toggleProductPurchased(productId))
    onProductPurchaseChanged?.(productId, willBePurchased)
    onFeedback?.({
      message: willBePurchased ? t('toast.productPurchased') : t('toast.productReturned'),
      tone: 'success',
      actionLabel: t('common.undo'),
      onAction: () => dispatch(appActions.toggleProductPurchased(productId)),
    })
  }

  const deleteProduct = (productId: string) => {
    dispatch(appActions.deleteProduct(productId))
    onFeedback?.({
      message: t('toast.productDeleted'),
      tone: 'success',
      actionLabel: t('common.undo'),
      onAction: () => dispatch(appActions.undoDeleteProduct()),
    })
  }

  const addProduct = () => {
    if (!generalList) {
      return
    }
    onAddProduct({ listId: generalList.id, storeId: null })
  }

  return (
    <main className="screen" id="main-content">
      <header className="app-topbar">
        <button aria-label={t('common.back')} className="back-button" onClick={onBack} type="button">
          <ArrowLeft aria-hidden="true" size={22} />
        </button>
        <div className="app-topbar__title">
          <h1>{t('lists.generalTitle')}</h1>
          <p>{t('common.productsCount', { count: products.length })}</p>
        </div>
      </header>

      {products.length === 0 ? (
        <section className="empty-state">
          <div className="empty-state__inner">
            <span aria-hidden="true" className="empty-state__icon">
              <ListChecks size={28} />
            </span>
            <h2>{t('empty.products.title')}</h2>
            <p>{t('empty.products.description')}</p>
            <PrimaryButton
              className="primary-button"
              disabled={!generalList}
              leadingIcon={Plus}
              onClick={addProduct}
            >
              {t('empty.products.action')}
            </PrimaryButton>
            {!generalList ? <p className="field__hint">{t('common.notAvailable')}</p> : null}
          </div>
        </section>
      ) : (
        <div className="screen-content">
          <section aria-labelledby="unassigned-products-title" className="product-group">
            <header className="section-header">
              <div className="section-header__copy">
                <h2 id="unassigned-products-title">{t('lists.unassigned')}</h2>
                <p>{t('common.productsCount', { count: unassigned.length })}</p>
              </div>
              {unassigned.length > 0 ? (
                <button className="text-button" onClick={onOpenDistribution} type="button">
                  {t('lists.bulkDistribution')}
                </button>
              ) : null}
            </header>
            {unassigned.length > 0 ? (
              <div className="card-stack">
                {unassigned.map((product) => (
                  <ShoppingProductRow
                    key={product.id}
                    onDelete={deleteProduct}
                    onMore={onMoveProduct}
                    onOpen={onOpenProduct}
                    onTogglePurchased={togglePurchased}
                    product={product}
                  />
                ))}
              </div>
            ) : (
              <p className="quiet">{t('home.allPurchased')}</p>
            )}
          </section>

          <section aria-labelledby="distributed-products-title" className="section-stack">
            <header className="section-header">
              <div className="section-header__copy">
                <h2 id="distributed-products-title">{t('lists.distributed')}</h2>
                <p>
                  {t('common.productsCount', {
                    count: storeGroups.reduce((count, group) => count + group.products.length, 0),
                  })}
                </p>
              </div>
            </header>
            {storeGroups.length > 0 ? (
              storeGroups.map((group) => (
                <section className="product-group" key={group.storeId}>
                  <header className="product-group__header">
                    <strong>{group.store?.name}</strong>
                    <span>{t('common.productsCount', { count: group.products.length })}</span>
                  </header>
                  <div className="card-stack">
                    {group.products.map((product) => (
                      <ShoppingProductRow
                        key={product.id}
                        onDelete={deleteProduct}
                        onMore={onMoveProduct}
                        onOpen={onOpenProduct}
                        onTogglePurchased={togglePurchased}
                        product={product}
                      />
                    ))}
                  </div>
                </section>
              ))
            ) : (
              <p className="quiet">{t('distribution.description')}</p>
            )}
          </section>
        </div>
      )}

      <div className="sticky-action">
        {unassigned.length > 0 ? (
          <SecondaryButton
            className="secondary-button"
            leadingIcon={ListChecks}
            onClick={onOpenDistribution}
          >
            {t('lists.bulkDistribution')}
          </SecondaryButton>
        ) : null}
        <PrimaryButton
          className="primary-button"
          disabled={!generalList}
          leadingIcon={Plus}
          onClick={addProduct}
        >
          {t('lists.addProduct')}
        </PrimaryButton>
      </div>
    </main>
  )
}
