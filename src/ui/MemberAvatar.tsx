import type { CSSProperties, HTMLAttributes } from 'react'
import { cx } from './utils'

export interface MemberAvatarProps extends Omit<HTMLAttributes<HTMLSpanElement>, 'children'> {
  name: string
  avatarUrl?: string | null
  accessibleLabel?: string
  statusLabel?: string
  color?: string
  size?: 'small' | 'medium' | 'large'
}

function getInitials(name: string): string {
  return name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0] ?? '')
    .join('')
    .toLocaleUpperCase()
}

export function MemberAvatar({
  accessibleLabel,
  avatarUrl,
  className,
  color,
  name,
  size = 'medium',
  statusLabel,
  ...spanProps
}: MemberAvatarProps) {
  const avatarStyle = color ? ({ '--ui-avatar-color': color } as CSSProperties) : undefined

  return (
    <span
      {...spanProps}
      aria-label={accessibleLabel ?? name}
      className={cx('ui-member-avatar', `ui-member-avatar--${size}`, className)}
      role="img"
      style={avatarStyle}
    >
      {avatarUrl ? (
        <img alt="" className="ui-member-avatar__image" src={avatarUrl} />
      ) : (
        <span aria-hidden="true" className="ui-member-avatar__initials">
          {getInitials(name)}
        </span>
      )}
      {statusLabel ? (
        <>
          <span aria-hidden="true" className="ui-member-avatar__status" />
          <span className="ui-visually-hidden">{statusLabel}</span>
        </>
      ) : null}
    </span>
  )
}
