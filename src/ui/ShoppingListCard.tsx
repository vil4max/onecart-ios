import { ChevronRight, ShoppingBasket } from 'lucide-react'
import { PriceLabel } from './PriceLabel'
import { PrimaryButton } from './PrimaryButton'
import { ProgressBar } from './ProgressBar'
import { cx } from './utils'

export interface ShoppingListCardProps {
  title: string
  description?: string
  itemCountLabel: string
  purchasedCountLabel: string
  estimatedTotal: number
  estimatedTotalLabel: string
  locale: string
  currency?: string
  progress: number
  progressLabel: string
  openLabel: string
  onOpen: () => void
  className?: string
}

export function ShoppingListCard({
  className,
  currency,
  description,
  estimatedTotal,
  estimatedTotalLabel,
  itemCountLabel,
  locale,
  onOpen,
  openLabel,
  progress,
  progressLabel,
  purchasedCountLabel,
  title,
}: ShoppingListCardProps) {
  return (
    <article className={cx('ui-shopping-list-card', className)}>
      <header className="ui-shopping-list-card__header">
        <span aria-hidden="true" className="ui-shopping-list-card__icon">
          <ShoppingBasket size={24} />
        </span>
        <div>
          <h2 className="ui-shopping-list-card__title">{title}</h2>
          {description ? <p className="ui-shopping-list-card__description">{description}</p> : null}
        </div>
      </header>

      <div className="ui-shopping-list-card__metrics">
        <div>
          <strong>{itemCountLabel}</strong>
          <span>{purchasedCountLabel}</span>
        </div>
        <PriceLabel
          accessibleLabel={estimatedTotalLabel}
          currency={currency}
          locale={locale}
          value={estimatedTotal}
        />
      </div>

      <ProgressBar label={progressLabel} value={progress} valueText={progressLabel} />

      <PrimaryButton onClick={onOpen} trailingIcon={ChevronRight}>
        {openLabel}
      </PrimaryButton>
    </article>
  )
}
