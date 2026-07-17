import { useState } from 'react'
import {
  ArrowLeft,
  ChevronDown,
  ChevronRight,
  ExternalLink,
  MapPin,
  MoreHorizontal,
  Pin,
  PinOff,
  Plus,
  Settings2,
  ShoppingBasket,
  UsersRound,
} from 'lucide-react'
import { PRODUCT_CATEGORIES, type ProductCategory } from '../../domain/models'
import { createTranslator, formatEstimatedMoney } from '../../localization'
import { useAppDispatch, useAppState } from '../../store/AppStateProvider'
import { appActions } from '../../store/appReducer'
import {
  selectActiveListForStore,
  selectProductsByCategory,
  selectProductsForStore,
  selectStoreById,
  selectStoreSummary,
} from '../../store/selectors'
import { BottomSheet, IconButton, PrimaryButton, SecondaryButton } from '../../ui'
import { CATEGORY_TRANSLATION_KEYS } from '../products/productPresentation'
import type { FeatureFeedback, ProductEditorContext } from '../products/types'
import { formatStoreLocation } from '../stores/storeLocation'
import { ShoppingProductRow } from './ShoppingProductRow'

export interface StoreListScreenProps {
  storeId: string
  onBack: () => void
  onCreateList: (storeId: string) => void
  onAddProduct: (context: ProductEditorContext) => void
  onOpenProduct: (productId: string) => void
  onMoveProduct: (productId: string) => void
  onShare: (listId: string) => void
  onOpenMore: (storeId: string) => void
  onCompleted?: (listId: string) => void
  onFeedback?: (feedback: FeatureFeedback) => void
  onProductPurchaseChanged?: (productId: string, isPurchased: boolean) => void
}

export function StoreListScreen({
  onAddProduct,
  onBack,
  onCompleted,
  onCreateList,
  onFeedback,
  onMoveProduct,
  onOpenMore,
  onOpenProduct,
  onProductPurchaseChanged,
  onShare,
  storeId,
}: StoreListScreenProps) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const t = createTranslator(state.settings.locale)
  const store = selectStoreById(state, storeId)
  const storeLocation = store ? formatStoreLocation(store) : null
  const list = selectActiveListForStore(state, storeId)
  const products = selectProductsForStore(state, storeId)
  const summary = selectStoreSummary(state, storeId)
  const productsByCategory = selectProductsByCategory(state, { storeId })
  const remaining = products.filter((product) => !product.isPurchased)
  const purchased = products.filter((product) => product.isPurchased)
  const [collapsedCategories, setCollapsedCategories] = useState<Set<ProductCategory>>(
    () => new Set(),
  )
  const [storeMenuOpen, setStoreMenuOpen] = useState(false)

  const toggleCategory = (category: ProductCategory) => {
    setCollapsedCategories((current) => {
      const next = new Set(current)
      if (next.has(category)) {
        next.delete(category)
      } else {
        next.add(category)
      }
      return next
    })
  }

  const togglePurchased = (productId: string) => {
    const product = state.products.find((item) => item.id === productId)
    if (!product) {
      return
    }
    const willBePurchased = !product.isPurchased
    dispatch(appActions.toggleProductPurchased(product.id))
    onProductPurchaseChanged?.(product.id, willBePurchased)
    onFeedback?.({
      message: willBePurchased ? t('toast.productPurchased') : t('toast.productReturned'),
      tone: 'success',
      actionLabel: t('common.undo'),
      onAction: () => dispatch(appActions.toggleProductPurchased(product.id)),
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

  const completeList = () => {
    if (!list || products.length === 0 || remaining.length > 0) {
      return
    }
    dispatch(appActions.completeList(list.id))
    onCompleted?.(list.id)
    onFeedback?.({ message: t('toast.listCompleted'), tone: 'success' })
  }

  const addProduct = () => {
    if (list) {
      onAddProduct({ listId: list.id, storeId })
    }
  }

  const togglePinned = () => {
    if (!store) return
    dispatch(appActions.setStorePinned(storeId, !store.isPinned))
    setStoreMenuOpen(false)
    onFeedback?.({ message: t('toast.storeUpdated'), tone: 'success' })
  }

  const openOfficialApp = () => {
    if (!store?.externalAppUrl) {
      onFeedback?.({ message: t('stores.externalAppUnavailable'), tone: 'info' })
      return
    }
    try {
      const url = new URL(store.externalAppUrl)
      if (url.protocol !== 'http:' && url.protocol !== 'https:') throw new Error('Invalid URL')
      window.open(url.toString(), '_blank', 'noopener,noreferrer')
      setStoreMenuOpen(false)
    } catch {
      onFeedback?.({ message: t('stores.externalAppUnavailable'), tone: 'error' })
    }
  }

  if (!store) {
    return (
      <main className="screen" id="main-content">
        <header className="app-topbar">
          <button aria-label={t('common.back')} className="back-button" onClick={onBack} type="button">
            <ArrowLeft aria-hidden="true" size={22} />
          </button>
          <div className="app-topbar__title">
            <h1>{t('stores.title')}</h1>
          </div>
        </header>
        <section className="empty-state">
          <div className="empty-state__inner">
            <span aria-hidden="true" className="empty-state__icon">
              <ShoppingBasket size={28} />
            </span>
            <h2>{t('common.notAvailable')}</h2>
            <SecondaryButton className="secondary-button" onClick={onBack}>
              {t('common.back')}
            </SecondaryButton>
          </div>
        </section>
      </main>
    )
  }

  return (
    <main className="screen" id="main-content">
      <header className="app-topbar">
        <button aria-label={t('common.back')} className="back-button" onClick={onBack} type="button">
          <ArrowLeft aria-hidden="true" size={22} />
        </button>
        <div className="app-topbar__title">
          <h1>{store.name}</h1>
          <p>
            {t('common.productsCount', { count: products.length })} ·{' '}
            {formatEstimatedMoney(summary.estimatedTotal, state.settings.locale)}
          </p>
          {storeLocation ? (
            <p className="store-list-screen__location">
              <MapPin aria-hidden="true" size={13} />
              <span>{storeLocation}</span>
            </p>
          ) : null}
        </div>
        <IconButton
          className="icon-button"
          disabled={!list}
          icon={UsersRound}
          label={t('lists.sharedAccess')}
          onClick={() => list && onShare(list.id)}
        />
        <IconButton
          className="icon-button"
          icon={MoreHorizontal}
          label={t('a11y.openMoreMenu')}
          onClick={() => setStoreMenuOpen(true)}
        />
      </header>

      {products.length === 0 ? (
        <section className="empty-state">
          <div className="empty-state__inner">
            <span aria-hidden="true" className="empty-state__icon">
              <ShoppingBasket size={28} />
            </span>
            <h2>{t('empty.products.title')}</h2>
            <p>{t('empty.products.description')}</p>
            <PrimaryButton
              className="primary-button"
              leadingIcon={Plus}
              onClick={() => (list ? addProduct() : onCreateList(store.id))}
            >
              {t(list ? 'empty.products.action' : 'lists.create')}
            </PrimaryButton>
          </div>
        </section>
      ) : (
        <div className="screen-content">
          <section aria-labelledby="remaining-products-title" className="section-stack">
            <header className="section-header">
              <div className="section-header__copy">
                <h2 id="remaining-products-title">{t('lists.remaining')}</h2>
                <p>{t('lists.itemsRemaining', { count: remaining.length })}</p>
              </div>
            </header>

            {PRODUCT_CATEGORIES.map((category) => {
              const categoryProducts = productsByCategory[category].filter(
                (product) => !product.isPurchased,
              )
              if (categoryProducts.length === 0) {
                return null
              }
              const isCollapsed = collapsedCategories.has(category)
              const categoryLabel = t(CATEGORY_TRANSLATION_KEYS[category])
              return (
                <section className="product-group" key={category}>
                  <button
                    aria-expanded={!isCollapsed}
                    aria-label={
                      isCollapsed
                        ? t('a11y.expandCategory', { category: categoryLabel })
                        : t('a11y.collapseCategory', { category: categoryLabel })
                    }
                    className="product-group__header"
                    onClick={() => toggleCategory(category)}
                    type="button"
                  >
                    <strong>{categoryLabel}</strong>
                    <span className="cluster">
                      {t('lists.categoryCount', { count: categoryProducts.length })}
                      {isCollapsed ? (
                        <ChevronRight aria-hidden="true" size={18} />
                      ) : (
                        <ChevronDown aria-hidden="true" size={18} />
                      )}
                    </span>
                  </button>
                  {!isCollapsed ? (
                    <div className="card-stack">
                      {categoryProducts.map((product) => (
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
                  ) : null}
                </section>
              )
            })}

            {remaining.length === 0 ? <p className="quiet">{t('home.allPurchased')}</p> : null}
          </section>

          {purchased.length > 0 ? (
            <section aria-labelledby="purchased-products-title" className="product-group">
              <header className="section-header">
                <div className="section-header__copy">
                  <h2 id="purchased-products-title">{t('lists.purchased')}</h2>
                  <p>{t('common.productsCount', { count: purchased.length })}</p>
                </div>
              </header>
              <div className="card-stack">
                {purchased.map((product) => (
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
          ) : null}
        </div>
      )}

      <div className="sticky-action">
        <SecondaryButton
          className="secondary-button"
          leadingIcon={Plus}
          onClick={() => (list ? addProduct() : onCreateList(store.id))}
        >
          {t(list ? 'lists.addProduct' : 'lists.create')}
        </SecondaryButton>
        <PrimaryButton
          className="primary-button"
          disabled={!list || products.length === 0 || remaining.length > 0}
          onClick={completeList}
        >
          {t('lists.completePurchase')}
        </PrimaryButton>
      </div>
      {products.length > 0 && remaining.length > 0 ? (
        <p className="field__hint">{t('lists.completeUnavailable')}</p>
      ) : null}

      <BottomSheet
        closeLabel={t('common.close')}
        description={storeLocation ?? undefined}
        isOpen={storeMenuOpen}
        onClose={() => setStoreMenuOpen(false)}
        title={store.name}
      >
        <div className="action-list">
          <button className="action-list__item" onClick={togglePinned} type="button">
            <span aria-hidden="true" className="action-list__icon">
              {store.isPinned ? <PinOff size={19} /> : <Pin size={19} />}
            </span>
            <span className="action-list__copy">
              <strong>{t(store.isPinned ? 'stores.menu.unpin' : 'stores.menu.pin')}</strong>
              <span>{t('home.storeLists')}</span>
            </span>
          </button>
          <button className="action-list__item" onClick={openOfficialApp} type="button">
            <span aria-hidden="true" className="action-list__icon">
              <ExternalLink size={19} />
            </span>
            <span className="action-list__copy">
              <strong>{t('stores.menu.openOfficialApp')}</strong>
              <span>{store.externalAppUrl ? t('common.open') : t('stores.externalAppUnavailable')}</span>
            </span>
          </button>
          <button
            className="action-list__item"
            onClick={() => {
              setStoreMenuOpen(false)
              onOpenMore(store.id)
            }}
            type="button"
          >
            <span aria-hidden="true" className="action-list__icon">
              <Settings2 size={19} />
            </span>
            <span className="action-list__copy">
              <strong>{t('stores.title')}</strong>
              <span>{t('stores.menu.rename')}</span>
            </span>
          </button>
        </div>
      </BottomSheet>
    </main>
  )
}
