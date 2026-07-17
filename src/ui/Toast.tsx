import { AlertCircle, CheckCircle2, Info, X } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import { IconButton } from './IconButton'
import { cx } from './utils'

export type ToastTone = 'success' | 'error' | 'info'

export interface ToastProps {
  message: string
  tone?: ToastTone
  actionLabel?: string
  onAction?: () => void
  dismissLabel?: string
  onDismiss?: () => void
  className?: string
}

const TOAST_ICONS: Record<ToastTone, LucideIcon> = {
  success: CheckCircle2,
  error: AlertCircle,
  info: Info,
}

export function Toast({
  actionLabel,
  className,
  dismissLabel,
  message,
  onAction,
  onDismiss,
  tone = 'info',
}: ToastProps) {
  const ToneIcon = TOAST_ICONS[tone]
  const liveMode = tone === 'error' ? 'assertive' : 'polite'

  return (
    <aside
      aria-atomic="true"
      aria-live={liveMode}
      className={cx('ui-toast', `ui-toast--${tone}`, className)}
      role={tone === 'error' ? 'alert' : 'status'}
    >
      <ToneIcon aria-hidden="true" className="ui-toast__icon" size={20} />
      <p className="ui-toast__message">{message}</p>
      {actionLabel && onAction ? (
        <button className="ui-toast__action" onClick={onAction} type="button">
          {actionLabel}
        </button>
      ) : null}
      {dismissLabel && onDismiss ? (
        <IconButton icon={X} label={dismissLabel} onClick={onDismiss} />
      ) : null}
    </aside>
  )
}
