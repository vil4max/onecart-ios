export type MotionTransitionKind = 'page' | 'theme' | 'language'

interface BrowserViewTransition {
  finished: Promise<void>
}

type ViewTransitionDocument = Document & {
  startViewTransition?: (
    update: () => void | Promise<void>,
  ) => BrowserViewTransition
}

let transitionVersion = 0
let fallbackCleanupTimer: number | undefined

function prefersReducedMotion(): boolean {
  return (
    typeof window !== 'undefined' &&
    window.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true
  )
}

function beginTransition(kind: MotionTransitionKind): () => void {
  if (typeof document === 'undefined') return () => undefined

  const version = ++transitionVersion
  const root = document.documentElement
  root.dataset.motionTransition = kind

  if (fallbackCleanupTimer !== undefined) {
    window.clearTimeout(fallbackCleanupTimer)
  }

  const cleanup = () => {
    if (transitionVersion !== version) return
    delete root.dataset.motionTransition
  }

  fallbackCleanupTimer = window.setTimeout(cleanup, 520)
  return cleanup
}

export function markMotionTransition(kind: MotionTransitionKind): void {
  if (typeof window === 'undefined' || prefersReducedMotion()) return
  beginTransition(kind)
}

export function runMotionTransition(
  update: () => void,
  kind: MotionTransitionKind,
): void {
  if (typeof document === 'undefined' || prefersReducedMotion()) {
    update()
    return
  }

  const cleanup = beginTransition(kind)
  const transitionDocument = document as ViewTransitionDocument

  if (typeof transitionDocument.startViewTransition !== 'function') {
    update()
    return
  }

  let didRunUpdate = false
  try {
    const transition = transitionDocument.startViewTransition(() => {
      didRunUpdate = true
      update()
    })
    void transition.finished.finally(cleanup)
  } catch {
    if (!didRunUpdate) update()
    cleanup()
  }
}
