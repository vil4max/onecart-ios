import { ShoppingBasket } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import { useId } from 'react'
import { PrimaryButton } from './PrimaryButton'
import { SecondaryButton } from './SecondaryButton'
import { cx } from './utils'

export interface EmptyStateProps {
  title: string
  description: string
  icon?: LucideIcon
  actionLabel?: string
  onAction?: () => void
  secondaryActionLabel?: string
  onSecondaryAction?: () => void
  className?: string
}

export function EmptyState({
  actionLabel,
  className,
  description,
  icon: Icon = ShoppingBasket,
  onAction,
  onSecondaryAction,
  secondaryActionLabel,
  title,
}: EmptyStateProps) {
  const titleId = useId()

  return (
    <section aria-labelledby={titleId} className={cx('ui-empty-state', className)}>
      <span aria-hidden="true" className="ui-empty-state__icon">
        <Icon size={28} />
      </span>
      <h2 className="ui-empty-state__title" id={titleId}>
        {title}
      </h2>
      <p className="ui-empty-state__description">{description}</p>
      {actionLabel && onAction ? (
        <PrimaryButton onClick={onAction}>{actionLabel}</PrimaryButton>
      ) : null}
      {secondaryActionLabel && onSecondaryAction ? (
        <SecondaryButton onClick={onSecondaryAction}>{secondaryActionLabel}</SecondaryButton>
      ) : null}
    </section>
  )
}
