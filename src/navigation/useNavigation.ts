import { useCallback, useEffect, useMemo, useSyncExternalStore } from 'react'
import {
  backHash,
  canGoBackHash,
  getHashSnapshot,
  initializeHashNavigation,
  navigateHash,
  subscribeToHashNavigation,
  type NavigateOptions,
} from './hashNavigation'
import { HOME_ROUTE, parseRoute, routeToHash, type Route } from './routes'
import { markMotionTransition, runMotionTransition } from '../shared/motion'

export interface NavigationController {
  readonly route: Route
  readonly canGoBack: boolean
  readonly navigate: (route: Route, options?: NavigateOptions) => void
  readonly back: () => void
}

const getServerSnapshot = (): string => routeToHash(HOME_ROUTE)

export const useNavigation = (): NavigationController => {
  const hash = useSyncExternalStore(
    subscribeToHashNavigation,
    getHashSnapshot,
    getServerSnapshot,
  )

  useEffect(() => {
    initializeHashNavigation()
  }, [])

  const route = useMemo(() => parseRoute(hash), [hash])
  const navigate = useCallback(
    (target: Route, options?: NavigateOptions) =>
      runMotionTransition(() => navigateHash(target, options), 'page'),
    [],
  )
  const back = useCallback(() => {
    markMotionTransition('page')
    backHash()
  }, [])

  return useMemo(
    () => ({
      route,
      canGoBack: canGoBackHash(),
      navigate,
      back,
    }),
    [back, hash, navigate, route],
  )
}
