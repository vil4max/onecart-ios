import type { ButtonHTMLAttributes, ReactNode } from 'react'
import type { LucideIcon } from 'lucide-react'
import { LoaderCircle } from 'lucide-react'
import { cx } from './utils'

export interface ButtonBaseProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  children: ReactNode
  isLoading?: boolean
  loadingLabel?: string
  leadingIcon?: LucideIcon
  trailingIcon?: LucideIcon
}

interface InternalButtonProps extends ButtonBaseProps {
  variant: 'primary' | 'secondary'
}

export function ButtonBase({
  children,
  className,
  disabled,
  isLoading = false,
  leadingIcon: LeadingIcon,
  loadingLabel,
  trailingIcon: TrailingIcon,
  type = 'button',
  variant,
  ...buttonProps
}: InternalButtonProps) {
  const visibleLabel = isLoading && loadingLabel ? loadingLabel : children

  return (
    <button
      {...buttonProps}
      aria-busy={isLoading || undefined}
      className={cx(
        'ui-button',
        `ui-button--${variant}`,
        isLoading && 'ui-button--loading',
        className,
      )}
      disabled={disabled || isLoading}
      type={type}
    >
      {isLoading ? (
        <LoaderCircle aria-hidden="true" className="ui-button__spinner" size={20} />
      ) : LeadingIcon ? (
        <LeadingIcon aria-hidden="true" className="ui-button__icon" size={20} />
      ) : null}
      <span className="ui-button__label">{visibleLabel}</span>
      {!isLoading && TrailingIcon ? (
        <TrailingIcon aria-hidden="true" className="ui-button__icon" size={20} />
      ) : null}
    </button>
  )
}
