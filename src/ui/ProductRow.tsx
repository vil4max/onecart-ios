import { MapPin, MoreHorizontal, StickyNote } from 'lucide-react'
import { IconButton } from './IconButton'
import { PriceLabel } from './PriceLabel'
import { ProductThumbnail } from './ProductThumbnail'
import { cx } from './utils'

export interface ProductRowProps {
  name: string
  quantityLabel: string
  imageUrl?: string | null
  imageAlt?: string
  isPurchased: boolean
  checkboxLabel: string
  onCheckedChange: (checked: boolean) => void
  checked?: boolean
  estimatedPrice?: number
  estimatedPriceLabel?: string
  locale: string
  currency?: string
  storeLabel?: string
  note?: string
  noteLabel?: string
  addedByLabel?: string
  openLabel?: string
  moreLabel?: string
  onOpen?: () => void
  onMore?: () => void
  disabled?: boolean
  className?: string
}

export function ProductRow({
  addedByLabel,
  checkboxLabel,
  checked,
  className,
  currency,
  disabled = false,
  estimatedPrice,
  estimatedPriceLabel,
  imageAlt,
  imageUrl,
  isPurchased,
  locale,
  moreLabel,
  name,
  note,
  noteLabel,
  onCheckedChange,
  onMore,
  onOpen,
  openLabel,
  quantityLabel,
  storeLabel,
}: ProductRowProps) {
  const isChecked = checked ?? isPurchased

  return (
    <article
      aria-disabled={disabled || undefined}
      className={cx(
        'ui-product-row',
        isPurchased && 'ui-product-row--purchased',
        disabled && 'ui-product-row--disabled',
        className,
      )}
      data-purchased={isPurchased}
    >
      <label className="ui-product-row__check">
        <input
          aria-label={checkboxLabel}
          checked={isChecked}
          disabled={disabled}
          onChange={(event) => onCheckedChange(event.currentTarget.checked)}
          type="checkbox"
        />
        <span aria-hidden="true" className="ui-product-row__checkmark" />
      </label>

      <ProductThumbnail alt={imageAlt ?? name} src={imageUrl} />

      <div className="ui-product-row__content">
        {onOpen ? (
          <button
            aria-label={openLabel}
            className="ui-product-row__name-button"
            disabled={disabled}
            onClick={onOpen}
            type="button"
          >
            {name}
          </button>
        ) : (
          <h3 className="ui-product-row__name">{name}</h3>
        )}

        <div className="ui-product-row__metadata">
          <span>{quantityLabel}</span>
          {storeLabel ? (
            <span className="ui-product-row__store">
              <MapPin aria-hidden="true" size={14} />
              {storeLabel}
            </span>
          ) : null}
          {addedByLabel ? <span>{addedByLabel}</span> : null}
        </div>

        {note ? (
          <p aria-label={noteLabel} className="ui-product-row__note">
            <StickyNote aria-hidden="true" size={14} />
            {note}
          </p>
        ) : null}
      </div>

      <div className="ui-product-row__aside">
        {estimatedPrice !== undefined ? (
          <PriceLabel
            accessibleLabel={estimatedPriceLabel}
            currency={currency}
            locale={locale}
            value={estimatedPrice}
          />
        ) : null}
        {onMore && moreLabel ? (
          <IconButton disabled={disabled} icon={MoreHorizontal} label={moreLabel} onClick={onMore} />
        ) : null}
      </div>
    </article>
  )
}
