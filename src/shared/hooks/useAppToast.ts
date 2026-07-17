import { useCallback, useEffect, useRef, useState } from 'react'

export interface AppToastMessage {
  id: number
  message: string
  tone: 'success' | 'error' | 'info'
  actionLabel?: string
  onAction?: () => void
  isDismissing?: boolean
}

export interface ShowToastOptions {
  tone?: 'success' | 'error' | 'info'
  actionLabel?: string
  onAction?: () => void
  duration?: number
}

export function useAppToast() {
  const [toast, setToast] = useState<AppToastMessage | null>(null)
  const nextId = useRef(0)
  const timer = useRef<number | null>(null)
  const dismissTimer = useRef<number | null>(null)

  const clearTimers = useCallback(() => {
    if (timer.current !== null) {
      window.clearTimeout(timer.current)
      timer.current = null
    }
    if (dismissTimer.current !== null) {
      window.clearTimeout(dismissTimer.current)
      dismissTimer.current = null
    }
  }, [])

  const dismissToast = useCallback(
    (expectedId?: number) => {
      clearTimers()
      setToast((current) => {
        if (!current || (expectedId !== undefined && current.id !== expectedId)) {
          return current
        }

        const id = current.id
        dismissTimer.current = window.setTimeout(() => {
          setToast((latest) => (latest?.id === id ? null : latest))
          dismissTimer.current = null
        }, 190)
        return { ...current, isDismissing: true }
      })
    },
    [clearTimers],
  )

  const showToast = useCallback(
    (message: string, options: ShowToastOptions = {}) => {
      clearTimers()
      const id = ++nextId.current
      setToast({
        id,
        message,
        tone: options.tone ?? 'info',
        actionLabel: options.actionLabel,
        onAction: options.onAction,
        isDismissing: false,
      })
      timer.current = window.setTimeout(() => {
        dismissToast(id)
      }, options.duration ?? 4500)
    },
    [clearTimers, dismissToast],
  )

  const runToastAction = useCallback(() => {
    const action = toast?.onAction
    dismissToast()
    action?.()
  }, [dismissToast, toast])

  useEffect(() => clearTimers, [clearTimers])

  return { toast, showToast, dismissToast, runToastAction }
}
