import { ChevronRight, MapPin, MoreHorizontal, Pin } from 'lucide-react'
import { IconButton } from './IconButton'
import { PriceLabel } from './PriceLabel'
import { ProgressBar } from './ProgressBar'
import { SecondaryButton } from './SecondaryButton'
import { StoreMark } from './StoreMark'
import { cx } from './utils'

export interface StoreCardProps {
  name: string
  storeId?: string
  icon?: string
  color?: string
  itemCountLabel: string
  estimatedTotal: number
  estimatedTotalLabel: string
  locale: string
  currency?: string
  statusLabel: string
  locationLabel?: string
  progress: number
  progressLabel: string
  openLabel: string
  moreLabel: string
  isPinned?: boolean
  pinnedLabel?: string
  onOpen: () => void
  onMore?: () => void
  className?: string
}

export function StoreCard({
  className,
  color,
  currency,
  estimatedTotal,
  estimatedTotalLabel,
  icon,
  isPinned = false,
  itemCountLabel,
  locale,
  locationLabel,
  moreLabel,
  name,
  onMore,
  onOpen,
  openLabel,
  pinnedLabel,
  progress,
  progressLabel,
  statusLabel,
  storeId,
}: StoreCardProps) {
  return (
    <article className={cx('ui-store-card', className)}>
      <header className="ui-store-card__header">
        <StoreMark
          className="ui-store-card__mark"
          color={color}
          icon={icon}
          name={name}
          storeId={storeId}
        />
        <div className="ui-store-card__identity">
          <div className="ui-store-card__title-line">
            <h3 className="ui-store-card__title">{name}</h3>
            {isPinned ? (
              <span aria-label={pinnedLabel} className="ui-store-card__pinned" role="img">
                <Pin aria-hidden="true" size={15} />
              </span>
            ) : null}
          </div>
          <p className="ui-store-card__status">{statusLabel}</p>
          {locationLabel ? (
            <p className="ui-store-card__location">
              <MapPin aria-hidden="true" size={14} />
              <span>{locationLabel}</span>
            </p>
          ) : null}
        </div>
        {onMore ? <IconButton icon={MoreHorizontal} label={moreLabel} onClick={onMore} /> : null}
      </header>

      <div className="ui-store-card__metrics">
        <span>{itemCountLabel}</span>
        <PriceLabel
          accessibleLabel={estimatedTotalLabel}
          currency={currency}
          locale={locale}
          value={estimatedTotal}
        />
      </div>

      <ProgressBar label={progressLabel} value={progress} valueText={progressLabel} />

      <SecondaryButton onClick={onOpen} trailingIcon={ChevronRight}>
        {openLabel}
      </SecondaryButton>
    </article>
  )
}
