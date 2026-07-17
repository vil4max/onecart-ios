import type {
  AppNotification,
  FrequentProduct,
  Product,
  ProductCategory,
  PurchaseHistory,
  ShoppingList,
  Store,
  User,
} from '../domain/models'
import type { AppState } from './appReducer'

export interface ShoppingSummary {
  itemCount: number
  purchasedCount: number
  remainingCount: number
  estimatedTotal: number
  purchasedTotal: number
  progress: number
}

export interface StoreProductGroup {
  storeId: string | null
  store: Store | null
  products: Product[]
  summary: ShoppingSummary
}

export interface StoreListOverview {
  store: Store
  list: ShoppingList | null
  summary: ShoppingSummary
  status: 'empty' | 'active' | 'completed'
}

export interface HistoryDateGroup {
  date: string
  entries: PurchaseHistory[]
}

const categoryOrder: Record<ProductCategory, number> = {
  produce: 0,
  dairy: 1,
  meat: 2,
  drinks: 3,
  household: 4,
  other: 5,
}

function roundCurrency(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100
}

export function sortProductsForShopping(products: Product[]): Product[] {
  return [...products].sort((left, right) => {
    if (left.isPurchased !== right.isPurchased) {
      return left.isPurchased ? 1 : -1
    }
    const categoryDifference = categoryOrder[left.category] - categoryOrder[right.category]
    if (categoryDifference !== 0) {
      return categoryDifference
    }
    return left.createdAt.localeCompare(right.createdAt)
  })
}

export function summarizeProducts(products: Product[]): ShoppingSummary {
  const itemCount = products.length
  const purchased = products.filter((product) => product.isPurchased)
  const purchasedCount = purchased.length
  return {
    itemCount,
    purchasedCount,
    remainingCount: itemCount - purchasedCount,
    estimatedTotal: roundCurrency(
      products.reduce((total, product) => total + Math.max(0, product.estimatedPrice), 0),
    ),
    purchasedTotal: roundCurrency(
      purchased.reduce((total, product) => total + Math.max(0, product.estimatedPrice), 0),
    ),
    progress: itemCount === 0 ? 0 : Math.round((purchasedCount / itemCount) * 100),
  }
}

function activeListIds(state: AppState): Set<string> {
  return new Set(
    state.shoppingLists.filter((list) => list.status === 'active').map((list) => list.id),
  )
}

function activeProducts(state: AppState): Product[] {
  const ids = activeListIds(state)
  return state.products.filter((product) => ids.has(product.listId))
}

export const selectHasCompletedOnboarding = (state: AppState): boolean =>
  state.hasCompletedOnboarding
export const selectUsers = (state: AppState): User[] => state.users
export const selectStores = (state: AppState): Store[] => state.stores
export const selectShoppingLists = (state: AppState): ShoppingList[] => state.shoppingLists
export const selectProducts = (state: AppState): Product[] => state.products
export const selectPurchaseHistory = (state: AppState): PurchaseHistory[] => state.purchaseHistory
export const selectNotifications = (state: AppState): AppNotification[] => state.notifications
export const selectSettings = (state: AppState) => state.settings
export const selectNotificationSettings = (state: AppState) => state.notificationSettings
export const selectLocale = (state: AppState) => state.settings.locale
export const selectCurrency = (state: AppState) => state.settings.currency

export function selectCurrentUser(state: AppState): User | null {
  return state.users.find((user) => user.id === state.currentUserId) ?? null
}

export function selectUserById(state: AppState, userId: string | null): User | null {
  if (!userId) {
    return null
  }
  return state.users.find((user) => user.id === userId) ?? null
}

export function selectStoreById(state: AppState, storeId: string | null): Store | null {
  if (!storeId) {
    return null
  }
  return state.stores.find((store) => store.id === storeId) ?? null
}

export function selectSortedStores(state: AppState): Store[] {
  const locale = state.settings.locale === 'uk' ? 'uk-UA' : 'ru-RU'
  return [...state.stores].sort((left, right) => {
    if (left.isPinned !== right.isPinned) {
      return left.isPinned ? -1 : 1
    }
    return left.name.localeCompare(right.name, locale)
  })
}

export function selectPinnedStores(state: AppState): Store[] {
  return selectSortedStores(state).filter((store) => store.isPinned)
}

export function selectListById(state: AppState, listId: string | null): ShoppingList | null {
  if (!listId) {
    return null
  }
  return state.shoppingLists.find((list) => list.id === listId) ?? null
}

export function selectActiveLists(state: AppState): ShoppingList[] {
  return state.shoppingLists.filter((list) => list.status === 'active')
}

export function selectCompletedLists(state: AppState): ShoppingList[] {
  return state.shoppingLists.filter((list) => list.status === 'completed')
}

export function selectGeneralList(state: AppState): ShoppingList | null {
  return (
    state.shoppingLists.find((list) => list.status === 'active' && list.storeId === null) ?? null
  )
}

export function selectActiveListForStore(
  state: AppState,
  storeId: string | null,
): ShoppingList | null {
  return (
    state.shoppingLists.find(
      (list) => list.status === 'active' && list.storeId === storeId,
    ) ?? null
  )
}

export function selectMembersForList(state: AppState, listId: string): User[] {
  const list = selectListById(state, listId)
  if (!list) {
    return []
  }
  const memberIds = new Set(list.members)
  return state.users.filter((user) => memberIds.has(user.id))
}

export function selectProductById(state: AppState, productId: string | null): Product | null {
  if (!productId) {
    return null
  }
  return state.products.find((product) => product.id === productId) ?? null
}

export function selectActiveProducts(state: AppState): Product[] {
  return sortProductsForShopping(activeProducts(state))
}

export function selectProductsForList(state: AppState, listId: string): Product[] {
  return sortProductsForShopping(state.products.filter((product) => product.listId === listId))
}

export function selectProductsForStore(state: AppState, storeId: string): Product[] {
  return sortProductsForShopping(
    activeProducts(state).filter((product) => product.storeId === storeId),
  )
}

export function selectUnassignedProducts(state: AppState): Product[] {
  return sortProductsForShopping(
    activeProducts(state).filter((product) => product.storeId === null),
  )
}

export function selectAssignedProducts(state: AppState): Product[] {
  return sortProductsForShopping(
    activeProducts(state).filter((product) => product.storeId !== null),
  )
}

export function selectRemainingProducts(state: AppState): Product[] {
  return activeProducts(state).filter((product) => !product.isPurchased)
}

export function selectPurchasedProducts(state: AppState): Product[] {
  return activeProducts(state).filter((product) => product.isPurchased)
}

export function selectProductsByCategory(
  state: AppState,
  options: { listId?: string; storeId?: string | null } = {},
): Record<ProductCategory, Product[]> {
  let products = activeProducts(state)
  if (options.listId) {
    products = products.filter((product) => product.listId === options.listId)
  }
  if ('storeId' in options) {
    products = products.filter((product) => product.storeId === options.storeId)
  }
  const grouped: Record<ProductCategory, Product[]> = {
    produce: [],
    dairy: [],
    meat: [],
    drinks: [],
    household: [],
    other: [],
  }
  sortProductsForShopping(products).forEach((product) => grouped[product.category].push(product))
  return grouped
}

export function selectProductsGroupedByStore(state: AppState): StoreProductGroup[] {
  const products = activeProducts(state)
  const groups: StoreProductGroup[] = []
  const unassigned = sortProductsForShopping(
    products.filter((product) => product.storeId === null),
  )
  if (unassigned.length > 0) {
    groups.push({
      storeId: null,
      store: null,
      products: unassigned,
      summary: summarizeProducts(unassigned),
    })
  }
  selectSortedStores(state).forEach((store) => {
    const storeProducts = sortProductsForShopping(
      products.filter((product) => product.storeId === store.id),
    )
    if (storeProducts.length > 0) {
      groups.push({
        storeId: store.id,
        store,
        products: storeProducts,
        summary: summarizeProducts(storeProducts),
      })
    }
  })
  return groups
}

export function selectOverallSummary(state: AppState): ShoppingSummary {
  return summarizeProducts(activeProducts(state))
}

export function selectListSummary(state: AppState, listId: string): ShoppingSummary {
  return summarizeProducts(state.products.filter((product) => product.listId === listId))
}

export function selectStoreSummary(state: AppState, storeId: string): ShoppingSummary {
  return summarizeProducts(activeProducts(state).filter((product) => product.storeId === storeId))
}

export function selectStoreOverviews(state: AppState): StoreListOverview[] {
  return selectSortedStores(state).map((store) => {
    const list = selectActiveListForStore(state, store.id)
    const summary = selectStoreSummary(state, store.id)
    const hasCompletedList = state.shoppingLists.some(
      (item) => item.storeId === store.id && item.status === 'completed',
    )
    return {
      store,
      list,
      summary,
      status:
        summary.itemCount > 0 ? 'active' : hasCompletedList && !list ? 'completed' : 'empty',
    }
  })
}

export function selectHistoryEntryById(
  state: AppState,
  historyId: string | null,
): PurchaseHistory | null {
  if (!historyId) {
    return null
  }
  return state.purchaseHistory.find((entry) => entry.id === historyId) ?? null
}

export function selectSortedHistory(state: AppState): PurchaseHistory[] {
  return [...state.purchaseHistory].sort((left, right) => right.date.localeCompare(left.date))
}

export function selectHistoryGroupedByDate(state: AppState): HistoryDateGroup[] {
  const grouped = new Map<string, PurchaseHistory[]>()
  selectSortedHistory(state).forEach((entry) => {
    const date = entry.date.slice(0, 10)
    grouped.set(date, [...(grouped.get(date) ?? []), entry])
  })
  return Array.from(grouped, ([date, entries]) => ({ date, entries }))
}

export function selectSortedNotifications(state: AppState): AppNotification[] {
  return [...state.notifications].sort((left, right) =>
    right.createdAt.localeCompare(left.createdAt),
  )
}

export function selectVisibleNotifications(state: AppState): AppNotification[] {
  const muted = new Set(state.notificationSettings.mutedListIds)
  return selectSortedNotifications(state).filter(
    (notification) => !notification.listId || !muted.has(notification.listId),
  )
}

export function selectUnreadNotifications(state: AppState): AppNotification[] {
  return selectVisibleNotifications(state).filter((notification) => !notification.isRead)
}

export function selectUnreadNotificationCount(state: AppState): number {
  return selectUnreadNotifications(state).length
}

export function selectFrequentProducts(state: AppState): FrequentProduct[] {
  return [...state.frequentProducts].sort((left, right) => {
    if (left.timesAdded !== right.timesAdded) {
      return right.timesAdded - left.timesAdded
    }
    return right.lastAddedAt.localeCompare(left.lastAddedAt)
  })
}

export function selectFrequentProductById(
  state: AppState,
  frequentProductId: string | null,
): FrequentProduct | null {
  if (!frequentProductId) {
    return null
  }
  return state.frequentProducts.find((item) => item.id === frequentProductId) ?? null
}

export function selectIsProductFrequent(state: AppState, productId: string): boolean {
  const product = selectProductById(state, productId)
  if (!product) {
    return false
  }
  const normalizedName = product.name.trim().toLocaleLowerCase()
  return state.frequentProducts.some(
    (item) =>
      item.sourceProductId === product.id || item.name.trim().toLocaleLowerCase() === normalizedName,
  )
}

export const selectCanUndoProductDelete = (state: AppState): boolean =>
  state.undo.deletedProduct !== null
export const selectCanUndoProductMove = (state: AppState): boolean =>
  state.undo.productMove !== null
