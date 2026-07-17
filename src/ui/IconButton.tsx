import type { ButtonHTMLAttributes } from 'react'
import type { LucideIcon } from 'lucide-react'
import { LoaderCircle } from 'lucide-react'
import { cx } from './utils'

export interface IconButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'children'> {
  icon: LucideIcon
  label: string
  isLoading?: boolean
  pressed?: boolean
}

export function IconButton({
  className,
  disabled,
  icon: Icon,
  isLoading = false,
  label,
  pressed,
  title,
  type = 'button',
  ...buttonProps
}: IconButtonProps) {
  return (
    <button
      {...buttonProps}
      aria-busy={isLoading || undefined}
      aria-label={label}
      aria-pressed={pressed}
      className={cx('ui-icon-button', isLoading && 'ui-icon-button--loading', className)}
      disabled={disabled || isLoading}
      title={title ?? label}
      type={type}
    >
      {isLoading ? (
        <LoaderCircle aria-hidden="true" className="ui-icon-button__spinner" size={22} />
      ) : (
        <Icon aria-hidden="true" size={22} />
      )}
    </button>
  )
}
