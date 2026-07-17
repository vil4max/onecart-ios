import { useId, useRef } from 'react'
import { createPortal } from 'react-dom'
import { AlertTriangle, LoaderCircle } from 'lucide-react'
import { useDialogFocus } from './useDialogFocus'
import { cx } from './utils'

export interface ConfirmationDialogProps {
  isOpen: boolean
  title: string
  description: string
  confirmLabel: string
  cancelLabel: string
  onConfirm: () => void
  onCancel: () => void
  tone?: 'default' | 'danger'
  isLoading?: boolean
  loadingLabel?: string
  dismissOnBackdrop?: boolean
  className?: string
}

export function ConfirmationDialog({
  cancelLabel,
  className,
  confirmLabel,
  description,
  dismissOnBackdrop = true,
  isLoading = false,
  isOpen,
  loadingLabel,
  onCancel,
  onConfirm,
  title,
  tone = 'default',
}: ConfirmationDialogProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const cancelRef = useRef<HTMLButtonElement>(null)
  const titleId = useId()
  const descriptionId = useId()

  useDialogFocus({
    isOpen,
    containerRef,
    onClose: onCancel,
    initialFocusRef: cancelRef,
    closeOnEscape: !isLoading,
  })

  if (!isOpen || typeof document === 'undefined') {
    return null
  }

  return createPortal(
    <div
      className="ui-dialog__backdrop"
      onClick={(event) => {
        if (dismissOnBackdrop && !isLoading && event.target === event.currentTarget) {
          onCancel()
        }
      }}
    >
      <div
        aria-busy={isLoading || undefined}
        aria-describedby={descriptionId}
        aria-labelledby={titleId}
        aria-modal="true"
        className={cx('ui-dialog', `ui-dialog--${tone}`, className)}
        ref={containerRef}
        role="alertdialog"
        tabIndex={-1}
      >
        {tone === 'danger' ? (
          <span aria-hidden="true" className="ui-dialog__icon">
            <AlertTriangle size={24} />
          </span>
        ) : null}
        <h2 className="ui-dialog__title" id={titleId}>
          {title}
        </h2>
        <p className="ui-dialog__description" id={descriptionId}>
          {description}
        </p>
        <div className="ui-dialog__actions">
          <button
            className="ui-button ui-button--secondary"
            disabled={isLoading}
            onClick={onCancel}
            ref={cancelRef}
            type="button"
          >
            {cancelLabel}
          </button>
          <button
            aria-busy={isLoading || undefined}
            className={cx('ui-button', 'ui-button--confirm', tone === 'danger' && 'ui-button--danger')}
            disabled={isLoading}
            onClick={onConfirm}
            type="button"
          >
            {isLoading ? (
              <LoaderCircle aria-hidden="true" className="ui-button__spinner" size={20} />
            ) : null}
            <span>{isLoading && loadingLabel ? loadingLabel : confirmLabel}</span>
          </button>
        </div>
      </div>
    </div>,
    document.body,
  )
}
