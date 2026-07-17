import {
  useEffect,
  useId,
  useRef,
  useState,
  type CSSProperties,
  type FocusEvent,
  type PointerEvent,
} from 'react'
import { CheckCircle2, RotateCcw, Trash2 } from 'lucide-react'
import type { Product } from '../../domain/models'
import { createTranslator, LOCALE_TAGS } from '../../localization'
import { useAppDispatch, useAppState } from '../../store/AppStateProvider'
import { appActions } from '../../store/appReducer'
import { selectStoreById, selectUserById } from '../../store/selectors'
import { ProductRow } from '../../ui'
import { formatProductQuantity } from '../products/productPresentation'

type SwipeDirection = 'purchase' | 'delete'
type SwipeAction = 'purchase' | 'return' | 'delete'

interface SwipeGesture {
  pointerId: number
  startX: number
  startY: number
  lastX: number
  originOffset: number
  axis: 'horizontal' | 'vertical' | null
}

const ACTION_WIDTH = 88
const AXIS_THRESHOLD = 7
const REVEAL_THRESHOLD = 30
const TRIGGER_THRESHOLD = 76
const MAX_DRAG = 112

export interface ShoppingProductRowProps {
  product: Product
  showStore?: boolean
  onOpen: (productId: string) => void
  onMore?: (productId: string) => void
  onTogglePurchased: (productId: string) => void
  onDelete?: (productId: string) => void
  onSwipeAction?: (action: SwipeAction, productId: string) => void
}

export function ShoppingProductRow({
  onDelete,
  onMore,
  onOpen,
  onSwipeAction,
  onTogglePurchased,
  product,
  showStore = false,
}: ShoppingProductRowProps) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const t = createTranslator(state.settings.locale)
  const store = selectStoreById(state, product.storeId)
  const addedBy = selectUserById(state, product.addedBy)
  const instructionsId = useId()
  const gestureRef = useRef<SwipeGesture | null>(null)
  const suppressClickRef = useRef(false)
  const surfaceRef = useRef<HTMLDivElement>(null)
  const [offset, setOffset] = useState(0)
  const [openDirection, setOpenDirection] = useState<SwipeDirection | null>(null)
  const [isDragging, setIsDragging] = useState(false)

  useEffect(() => {
    setOffset(0)
    setOpenDirection(null)
    setIsDragging(false)
    gestureRef.current = null
  }, [product.id])

  const closeActions = () => {
    setOffset(0)
    setOpenDirection(null)
    setIsDragging(false)
  }

  const revealAction = (direction: SwipeDirection) => {
    setOpenDirection(direction)
    setOffset(direction === 'purchase' ? ACTION_WIDTH : -ACTION_WIDTH)
  }

  const focusSurfaceControl = () => {
    window.requestAnimationFrame(() => {
      surfaceRef.current
        ?.querySelector<HTMLElement>('input:not([disabled]), button:not([disabled])')
        ?.focus()
    })
  }

  const runPurchaseAction = (restoreKeyboardFocus = false) => {
    const action: SwipeAction = product.isPurchased ? 'return' : 'purchase'
    closeActions()
    onTogglePurchased(product.id)
    onSwipeAction?.(action, product.id)
    if (restoreKeyboardFocus) {
      focusSurfaceControl()
    }
  }

  const runDeleteAction = () => {
    closeActions()
    if (onDelete) {
      onDelete(product.id)
    } else {
      dispatch(appActions.deleteProduct(product.id))
    }
    onSwipeAction?.('delete', product.id)
  }

  const handlePointerDown = (event: PointerEvent<HTMLDivElement>) => {
    if (!event.isPrimary || (event.pointerType === 'mouse' && event.button !== 0)) {
      return
    }
    gestureRef.current = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      lastX: event.clientX,
      originOffset: offset,
      axis: null,
    }
  }

  const handlePointerMove = (event: PointerEvent<HTMLDivElement>) => {
    const gesture = gestureRef.current
    if (!gesture || gesture.pointerId !== event.pointerId) {
      return
    }

    gesture.lastX = event.clientX
    const deltaX = event.clientX - gesture.startX
    const deltaY = event.clientY - gesture.startY
    if (!gesture.axis && Math.max(Math.abs(deltaX), Math.abs(deltaY)) >= AXIS_THRESHOLD) {
      gesture.axis = Math.abs(deltaX) > Math.abs(deltaY) ? 'horizontal' : 'vertical'
      if (gesture.axis === 'horizontal') {
        event.currentTarget.setPointerCapture(event.pointerId)
        setIsDragging(true)
      }
    }

    if (gesture.axis !== 'horizontal') {
      return
    }

    event.preventDefault()
    const nextOffset = Math.max(
      -MAX_DRAG,
      Math.min(MAX_DRAG, gesture.originOffset + deltaX),
    )
    setOffset(nextOffset)
    setOpenDirection(nextOffset > 0 ? 'purchase' : nextOffset < 0 ? 'delete' : null)
  }

  const finishPointerGesture = (event: PointerEvent<HTMLDivElement>, cancelled = false) => {
    const gesture = gestureRef.current
    if (!gesture || gesture.pointerId !== event.pointerId) {
      return
    }
    gestureRef.current = null
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId)
    }

    if (cancelled) {
      setOffset(gesture.originOffset)
      setOpenDirection(
        gesture.originOffset > 0 ? 'purchase' : gesture.originOffset < 0 ? 'delete' : null,
      )
      setIsDragging(false)
      return
    }

    if (gesture.axis !== 'horizontal') {
      setIsDragging(false)
      return
    }

    suppressClickRef.current = true
    window.setTimeout(() => {
      suppressClickRef.current = false
    }, 0)
    setIsDragging(false)
    const finalOffset = Math.max(
      -MAX_DRAG,
      Math.min(MAX_DRAG, gesture.originOffset + gesture.lastX - gesture.startX),
    )

    if (finalOffset >= TRIGGER_THRESHOLD) {
      runPurchaseAction()
    } else if (finalOffset <= -TRIGGER_THRESHOLD) {
      runDeleteAction()
    } else if (finalOffset >= REVEAL_THRESHOLD) {
      revealAction('purchase')
    } else if (finalOffset <= -REVEAL_THRESHOLD) {
      revealAction('delete')
    } else {
      closeActions()
    }
  }

  const handleBlur = (event: FocusEvent<HTMLDivElement>) => {
    if (!event.currentTarget.contains(event.relatedTarget as Node | null)) {
      closeActions()
    }
  }

  const surfaceStyle = {
    '--swipe-offset': `${offset}px`,
  } as CSSProperties
  const purchaseLabel = product.isPurchased
    ? t('products.markNotPurchased')
    : t('products.markPurchased')
  const PurchaseIcon = product.isPurchased ? RotateCcw : CheckCircle2

  return (
    <div
      aria-describedby={instructionsId}
      aria-label={product.name}
      className="shopping-product-swipe"
      data-dragging={isDragging || undefined}
      data-open={openDirection ?? undefined}
      onBlur={handleBlur}
      onClickCapture={(event) => {
        if (suppressClickRef.current) {
          event.preventDefault()
          event.stopPropagation()
        }
      }}
      onKeyDown={(event) => {
        if (event.key === 'Escape' && openDirection) {
          event.preventDefault()
          closeActions()
          focusSurfaceControl()
        }
      }}
      onPointerCancel={(event) => finishPointerGesture(event, true)}
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={finishPointerGesture}
      role="group"
    >
      <span className="sr-only" id={instructionsId}>
        {t('products.swipePurchase')} {t('products.swipeDelete')}
      </span>
      <div aria-hidden="true" className="shopping-product-swipe__track" />
      <button
        aria-label={`${purchaseLabel}: ${product.name}`}
        className="shopping-product-swipe__action shopping-product-swipe__action--purchase"
        onClick={(event) => runPurchaseAction(event.detail === 0)}
        onFocus={() => revealAction('purchase')}
        type="button"
      >
        <PurchaseIcon aria-hidden="true" size={20} />
        <span>{purchaseLabel}</span>
      </button>
      <button
        aria-label={`${t('products.delete')}: ${product.name}`}
        className="shopping-product-swipe__action shopping-product-swipe__action--delete"
        onClick={runDeleteAction}
        onFocus={() => revealAction('delete')}
        type="button"
      >
        <Trash2 aria-hidden="true" size={20} />
        <span>{t('common.delete')}</span>
      </button>
      <div
        className="shopping-product-swipe__surface"
        onFocusCapture={closeActions}
        ref={surfaceRef}
        style={surfaceStyle}
      >
        <ProductRow
          addedByLabel={
            addedBy ? t('lists.addedBy', { name: addedBy.name }) : undefined
          }
          checkboxLabel={
            product.isPurchased
              ? t('a11y.markNotPurchased', { product: product.name })
              : t('a11y.markPurchased', { product: product.name })
          }
          className="product-row"
          currency={state.settings.currency}
          estimatedPrice={product.estimatedPrice}
          estimatedPriceLabel={t('products.estimatedPrice')}
          imageAlt={t('products.photoAlt', { product: product.name })}
          imageUrl={product.imageUrl}
          isPurchased={product.isPurchased}
          locale={LOCALE_TAGS[state.settings.locale]}
          moreLabel={onMore ? t('a11y.openMoreMenu') : undefined}
          name={product.name}
          note={product.note}
          noteLabel={t('products.note')}
          onCheckedChange={() => onTogglePurchased(product.id)}
          onMore={onMore ? () => onMore(product.id) : undefined}
          onOpen={() => onOpen(product.id)}
          openLabel={`${t('products.detailsTitle')}: ${product.name}`}
          quantityLabel={formatProductQuantity(product, state.settings.locale, t)}
          storeLabel={showStore ? (store?.name ?? t('lists.noStore')) : undefined}
        />
      </div>
    </div>
  )
}
