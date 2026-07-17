import { useId, useRef } from 'react'
import type { ReactNode, RefObject } from 'react'
import { createPortal } from 'react-dom'
import { X } from 'lucide-react'
import { IconButton } from './IconButton'
import { useDialogFocus } from './useDialogFocus'
import { cx } from './utils'

export interface BottomSheetProps {
  isOpen: boolean
  title: string
  closeLabel: string
  onClose: () => void
  children: ReactNode
  description?: string
  footer?: ReactNode
  initialFocusRef?: RefObject<HTMLElement | null>
  dismissOnBackdrop?: boolean
  className?: string
}

export function BottomSheet({
  children,
  className,
  closeLabel,
  description,
  dismissOnBackdrop = true,
  footer,
  initialFocusRef,
  isOpen,
  onClose,
  title,
}: BottomSheetProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const titleId = useId()
  const descriptionId = useId()

  useDialogFocus({ isOpen, containerRef, onClose, initialFocusRef })

  if (!isOpen || typeof document === 'undefined') {
    return null
  }

  return createPortal(
    <div
      className="ui-bottom-sheet__backdrop"
      onClick={(event) => {
        if (dismissOnBackdrop && event.target === event.currentTarget) {
          onClose()
        }
      }}
    >
      <div
        aria-describedby={description ? descriptionId : undefined}
        aria-labelledby={titleId}
        aria-modal="true"
        className={cx('ui-bottom-sheet', className)}
        ref={containerRef}
        role="dialog"
        tabIndex={-1}
      >
        <span aria-hidden="true" className="ui-bottom-sheet__handle" />
        <header className="ui-bottom-sheet__header">
          <div>
            <h2 className="ui-bottom-sheet__title" id={titleId}>
              {title}
            </h2>
            {description ? (
              <p className="ui-bottom-sheet__description" id={descriptionId}>
                {description}
              </p>
            ) : null}
          </div>
          <IconButton icon={X} label={closeLabel} onClick={onClose} />
        </header>
        <div className="ui-bottom-sheet__content">{children}</div>
        {footer ? <footer className="ui-bottom-sheet__footer">{footer}</footer> : null}
      </div>
    </div>,
    document.body,
  )
}
