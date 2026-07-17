import { useEffect, useRef } from 'react'
import type { RefObject } from 'react'

const FOCUSABLE_SELECTOR = [
  'a[href]',
  'button:not([disabled])',
  'input:not([disabled])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])',
].join(',')

export interface UseDialogFocusOptions {
  isOpen: boolean
  containerRef: RefObject<HTMLElement | null>
  onClose: () => void
  initialFocusRef?: RefObject<HTMLElement | null>
  closeOnEscape?: boolean
  lockBodyScroll?: boolean
}

function getFocusableElements(container: HTMLElement): HTMLElement[] {
  return Array.from(container.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR)).filter(
    (element) => !element.hidden && element.getAttribute('aria-hidden') !== 'true',
  )
}

export function useDialogFocus({
  closeOnEscape = true,
  containerRef,
  initialFocusRef,
  isOpen,
  lockBodyScroll = true,
  onClose,
}: UseDialogFocusOptions): void {
  const onCloseRef = useRef(onClose)
  const initialFocusTargetRef = useRef(initialFocusRef)
  onCloseRef.current = onClose
  initialFocusTargetRef.current = initialFocusRef

  useEffect(() => {
    if (!isOpen || typeof document === 'undefined') {
      return undefined
    }

    const container = containerRef.current
    if (!container) {
      return undefined
    }

    const previouslyFocused = document.activeElement instanceof HTMLElement ? document.activeElement : null
    const previousOverflow = document.body.style.overflow
    const focusFrame = window.requestAnimationFrame(() => {
      const requestedFocus = initialFocusTargetRef.current?.current
      const firstFocusable = getFocusableElements(container)[0]
      ;(requestedFocus ?? firstFocusable ?? container).focus()
    })

    if (lockBodyScroll) {
      document.body.style.overflow = 'hidden'
    }

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && closeOnEscape) {
        event.preventDefault()
        onCloseRef.current()
        return
      }

      if (event.key !== 'Tab') {
        return
      }

      const focusableElements = getFocusableElements(container)
      if (focusableElements.length === 0) {
        event.preventDefault()
        container.focus()
        return
      }

      const firstElement = focusableElements[0]
      const lastElement = focusableElements[focusableElements.length - 1]
      const activeElement = document.activeElement

      if (event.shiftKey && activeElement === firstElement) {
        event.preventDefault()
        lastElement.focus()
      } else if (!event.shiftKey && activeElement === lastElement) {
        event.preventDefault()
        firstElement.focus()
      }
    }

    document.addEventListener('keydown', handleKeyDown)

    return () => {
      window.cancelAnimationFrame(focusFrame)
      document.removeEventListener('keydown', handleKeyDown)
      if (lockBodyScroll) {
        document.body.style.overflow = previousOverflow
      }
      if (previouslyFocused?.isConnected) {
        previouslyFocused.focus()
      }
    }
  }, [closeOnEscape, containerRef, isOpen, lockBodyScroll])
}
