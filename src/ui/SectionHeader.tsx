import type { LucideIcon } from 'lucide-react'
import { SecondaryButton } from './SecondaryButton'
import { cx } from './utils'

export interface SectionHeaderProps {
  title: string
  description?: string
  headingLevel?: 1 | 2 | 3 | 4
  actionLabel?: string
  actionIcon?: LucideIcon
  onAction?: () => void
  className?: string
}

export function SectionHeader({
  actionIcon,
  actionLabel,
  className,
  description,
  headingLevel = 2,
  onAction,
  title,
}: SectionHeaderProps) {
  const Heading = `h${headingLevel}` as const

  return (
    <header className={cx('ui-section-header', className)}>
      <div className="ui-section-header__copy">
        <Heading className="ui-section-header__title">{title}</Heading>
        {description ? <p className="ui-section-header__description">{description}</p> : null}
      </div>
      {actionLabel && onAction ? (
        <SecondaryButton leadingIcon={actionIcon} onClick={onAction}>
          {actionLabel}
        </SecondaryButton>
      ) : null}
    </header>
  )
}
