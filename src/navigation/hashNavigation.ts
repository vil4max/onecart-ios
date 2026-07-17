import {
  HOME_ROUTE,
  isSameRoute,
  parseRoute,
  routeToHash,
  routeToPath,
  tryParseRoute,
  type Route,
} from './routes'

export interface NavigateOptions {
  readonly replace?: boolean
}

const NAVIGATION_EVENT = 'onecart:hash-navigation'
const NAVIGATION_STATE_KEY = '__onecartHashNavigation'

interface NavigationMarker {
  readonly depth: number
}

const isBrowser = (): boolean => typeof window !== 'undefined'

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value)

const readMarker = (): NavigationMarker | null => {
  if (!isBrowser() || !isRecord(window.history.state)) return null

  const marker = window.history.state[NAVIGATION_STATE_KEY]
  if (!isRecord(marker) || typeof marker.depth !== 'number' || marker.depth < 0) return null

  return { depth: marker.depth }
}

const stateWithMarker = (depth: number): Record<string, unknown> => {
  const currentState = isBrowser() && isRecord(window.history.state) ? window.history.state : {}
  return {
    ...currentState,
    [NAVIGATION_STATE_KEY]: { depth } satisfies NavigationMarker,
  }
}

const urlForRoute = (route: Route): string => {
  const url = new URL(window.location.href)
  url.hash = routeToPath(route)
  return url.toString()
}

const notifyNavigation = (): void => {
  if (isBrowser()) window.dispatchEvent(new Event(NAVIGATION_EVENT))
}

export const getHashSnapshot = (): string => {
  if (!isBrowser()) return routeToHash(HOME_ROUTE)
  return window.location.hash || routeToHash(HOME_ROUTE)
}

export const getCurrentRoute = (): Route => parseRoute(getHashSnapshot())

export const initializeHashNavigation = (fallback: Route = HOME_ROUTE): void => {
  if (!isBrowser()) return

  const parsedRoute = tryParseRoute(window.location.hash)
  const route = parsedRoute ?? fallback
  const canonicalHash = routeToHash(route)
  const marker = readMarker()
  const needsCanonicalUrl = window.location.hash !== canonicalHash

  if (marker === null || needsCanonicalUrl) {
    window.history.replaceState(stateWithMarker(marker?.depth ?? 0), '', urlForRoute(route))
    notifyNavigation()
  }
}

export const navigateHash = (route: Route, options: NavigateOptions = {}): void => {
  if (!isBrowser()) return

  initializeHashNavigation()

  const currentRoute = getCurrentRoute()
  const currentDepth = readMarker()?.depth ?? 0
  const shouldReplace = options.replace === true || isSameRoute(currentRoute, route)
  const nextState = stateWithMarker(shouldReplace ? currentDepth : currentDepth + 1)

  if (shouldReplace) {
    window.history.replaceState(nextState, '', urlForRoute(route))
  } else {
    window.history.pushState(nextState, '', urlForRoute(route))
  }

  notifyNavigation()
}

export const canGoBackHash = (fallback: Route = HOME_ROUTE): boolean => {
  if (!isBrowser()) return false
  const depth = readMarker()?.depth ?? 0
  return depth > 0 || !isSameRoute(getCurrentRoute(), fallback)
}

export const backHash = (fallback: Route = HOME_ROUTE): void => {
  if (!isBrowser()) return

  initializeHashNavigation(fallback)
  const depth = readMarker()?.depth ?? 0

  if (depth > 0) {
    window.history.back()
    return
  }

  if (!isSameRoute(getCurrentRoute(), fallback)) {
    navigateHash(fallback, { replace: true })
  }
}

export const subscribeToHashNavigation = (listener: () => void): (() => void) => {
  if (!isBrowser()) return () => undefined

  window.addEventListener('hashchange', listener)
  window.addEventListener('popstate', listener)
  window.addEventListener(NAVIGATION_EVENT, listener)

  return () => {
    window.removeEventListener('hashchange', listener)
    window.removeEventListener('popstate', listener)
    window.removeEventListener(NAVIGATION_EVENT, listener)
  }
}
