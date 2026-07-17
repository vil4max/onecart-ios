import { useId, useRef, type ReactNode, type RefObject } from 'react'
import { createPortal } from 'react-dom'
import { X } from 'lucide-react'
import { IconButton, useDialogFocus } from '../../ui'

export interface AccessibleSheetProps {
  isOpen: boolean
  title: string
  closeLabel: string
  onClose: () => void
  children: ReactNode
  description?: string
  footer?: ReactNode
  initialFocusRef?: RefObject<HTMLElement | null>
  dismissOnBackdrop?: boolean
}

export function AccessibleSheet({
  children,
  closeLabel,
  description,
  dismissOnBackdrop = true,
  footer,
  initialFocusRef,
  isOpen,
  onClose,
  title,
}: AccessibleSheetProps) {
  const containerRef = useRef<HTMLElement>(null)
  const titleId = useId()
  const descriptionId = useId()

  useDialogFocus({ isOpen, containerRef, initialFocusRef, onClose })

  if (!isOpen || typeof document === 'undefined') {
    return null
  }

  return createPortal(
    <div
      className="sheet-overlay"
      onClick={(event) => {
        if (dismissOnBackdrop && event.target === event.currentTarget) {
          onClose()
        }
      }}
    >
      <section
        aria-describedby={description ? descriptionId : undefined}
        aria-labelledby={titleId}
        aria-modal="true"
        className="bottom-sheet"
        ref={containerRef}
        role="dialog"
        tabIndex={-1}
      >
        <span aria-hidden="true" className="bottom-sheet__handle" />
        <header className="bottom-sheet__header">
          <div>
            <h2 id={titleId}>{title}</h2>
            {description ? <p id={descriptionId}>{description}</p> : null}
          </div>
          <IconButton className="icon-button" icon={X} label={closeLabel} onClick={onClose} />
        </header>
        {children}
        {footer ? <footer className="bottom-sheet__footer">{footer}</footer> : null}
      </section>
    </div>,
    document.body,
  )
}
