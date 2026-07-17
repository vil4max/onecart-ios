import type { HTMLAttributes } from 'react'
import { cx } from './utils'

export interface PriceLabelProps extends Omit<HTMLAttributes<HTMLDataElement>, 'value'> {
  value: number
  locale: string
  currency?: string
  approximate?: boolean
  accessibleLabel?: string
  minimumFractionDigits?: number
}

export function PriceLabel({
  accessibleLabel,
  approximate = true,
  className,
  currency = 'UAH',
  locale,
  minimumFractionDigits = 0,
  value,
  ...dataProps
}: PriceLabelProps) {
  const formattedValue = new Intl.NumberFormat(locale, {
    style: 'currency',
    currency,
    minimumFractionDigits,
    maximumFractionDigits: 2,
  }).format(value)

  return (
    <data
      {...dataProps}
      aria-label={accessibleLabel}
      className={cx('ui-price-label', approximate && 'ui-price-label--approximate', className)}
      value={value}
    >
      {approximate ? <span aria-hidden="true">≈&nbsp;</span> : null}
      {formattedValue}
    </data>
  )
}
