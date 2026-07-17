export type Route =
  | { readonly name: 'home' }
  | { readonly name: 'stores' }
  | { readonly name: 'storeCatalog' }
  | { readonly name: 'generalList' }
  | { readonly name: 'storeList'; readonly storeId: string }
  | { readonly name: 'history' }
  | { readonly name: 'historyDetail'; readonly historyId: string }
  | { readonly name: 'profile' }
  | { readonly name: 'notifications' }
  | { readonly name: 'sharing' }
  | { readonly name: 'settings' }

export const routes = {
  home: (): Route => ({ name: 'home' }),
  stores: (): Route => ({ name: 'stores' }),
  storeCatalog: (): Route => ({ name: 'storeCatalog' }),
  generalList: (): Route => ({ name: 'generalList' }),
  storeList: (storeId: string): Route => ({ name: 'storeList', storeId }),
  history: (): Route => ({ name: 'history' }),
  historyDetail: (historyId: string): Route => ({ name: 'historyDetail', historyId }),
  profile: (): Route => ({ name: 'profile' }),
  notifications: (): Route => ({ name: 'notifications' }),
  sharing: (): Route => ({ name: 'sharing' }),
  settings: (): Route => ({ name: 'settings' }),
} as const

export const HOME_ROUTE: Route = routes.home()

const decodeId = (value: string): string | null => {
  try {
    const decoded = decodeURIComponent(value).trim()
    return decoded.length > 0 ? decoded : null
  } catch {
    return null
  }
}

const pathFromInput = (input: string): string | null => {
  let value = input.trim()

  if (/^[a-z][a-z\d+.-]*:\/\//i.test(value)) {
    try {
      const url = new URL(value)
      value = url.hash.length > 1 ? url.hash.slice(1) : url.pathname
    } catch {
      return null
    }
  } else {
    const hashIndex = value.indexOf('#')
    if (hashIndex >= 0) value = value.slice(hashIndex + 1)
  }

  const queryIndex = value.indexOf('?')
  if (queryIndex >= 0) value = value.slice(0, queryIndex)

  if (value === '' || value === '/') return '/'
  if (!value.startsWith('/')) value = `/${value}`

  const normalized = value.replace(/\/{2,}/g, '/').replace(/\/$/, '')
  return normalized || '/'
}

export const routeToPath = (route: Route): string => {
  switch (route.name) {
    case 'home':
      return '/'
    case 'stores':
      return '/stores'
    case 'storeCatalog':
      return '/stores/catalog'
    case 'generalList':
      return '/lists/general'
    case 'storeList':
      return `/lists/store/${encodeURIComponent(route.storeId)}`
    case 'history':
      return '/history'
    case 'historyDetail':
      return `/history/${encodeURIComponent(route.historyId)}`
    case 'profile':
      return '/profile'
    case 'notifications':
      return '/notifications'
    case 'sharing':
      return '/sharing'
    case 'settings':
      return '/settings'
  }
}

export const routeToHash = (route: Route): string => `#${routeToPath(route)}`

export const tryParseRoute = (input: string): Route | null => {
  const path = pathFromInput(input)
  if (path === null) return null

  switch (path) {
    case '/':
      return routes.home()
    case '/stores':
      return routes.stores()
    case '/stores/catalog':
      return routes.storeCatalog()
    case '/lists/general':
      return routes.generalList()
    case '/history':
      return routes.history()
    case '/profile':
      return routes.profile()
    case '/notifications':
      return routes.notifications()
    case '/sharing':
      return routes.sharing()
    case '/settings':
      return routes.settings()
  }

  const storeListMatch = /^\/lists\/store\/([^/]+)$/.exec(path)
  if (storeListMatch) {
    const storeId = decodeId(storeListMatch[1])
    return storeId ? routes.storeList(storeId) : null
  }

  const historyDetailMatch = /^\/history\/([^/]+)$/.exec(path)
  if (historyDetailMatch) {
    const historyId = decodeId(historyDetailMatch[1])
    return historyId ? routes.historyDetail(historyId) : null
  }

  return null
}

export const parseRoute = (input: string, fallback: Route = HOME_ROUTE): Route =>
  tryParseRoute(input) ?? fallback

export const isSameRoute = (left: Route, right: Route): boolean =>
  routeToPath(left) === routeToPath(right)
