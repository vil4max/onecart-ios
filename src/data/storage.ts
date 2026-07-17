import type {
  AppNotification,
  AppSettings,
  FrequentProduct,
  NotificationSettings,
  Product,
  PurchaseHistory,
  ShoppingList,
  Store,
  User,
} from '../domain/models'
import {
  APP_STATE_VERSION,
  createInitialAppState,
  type AppState,
} from '../store/appReducer'
import { resolveProductMedia } from './productMedia'

export const APP_STORAGE_KEY = 'onecart.app-state'

export interface StorageAdapter {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
  removeItem(key: string): void
}

export type PersistedAppState = Omit<AppState, 'undo'>

interface PersistedEnvelope {
  version: number
  savedAt: string
  state: PersistedAppState
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function isString(value: unknown): value is string {
  return typeof value === 'string'
}

function isNullableString(value: unknown): value is string | null {
  return value === null || isString(value)
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value)
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every(isString)
}

function isUser(value: unknown): value is User {
  return (
    isRecord(value) &&
    isString(value.id) &&
    isString(value.name) &&
    isString(value.email) &&
    isNullableString(value.avatar) &&
    (value.role === 'owner' || value.role === 'editor' || value.role === 'viewer')
  )
}

function isStore(value: unknown): value is Store {
  return (
    isRecord(value) &&
    isString(value.id) &&
    isString(value.name) &&
    isString(value.icon) &&
    isString(value.color) &&
    (!('city' in value) || isNullableString(value.city)) &&
    isNullableString(value.address) &&
    (!('latitude' in value) || value.latitude === null || isFiniteNumber(value.latitude)) &&
    (!('longitude' in value) || value.longitude === null || isFiniteNumber(value.longitude)) &&
    isNullableString(value.externalAppUrl) &&
    typeof value.isPinned === 'boolean'
  )
}

function isShoppingList(value: unknown): value is ShoppingList {
  return (
    isRecord(value) &&
    isString(value.id) &&
    isString(value.title) &&
    isNullableString(value.storeId) &&
    isString(value.ownerId) &&
    isStringArray(value.members) &&
    isString(value.createdAt) &&
    isString(value.updatedAt) &&
    (value.status === 'active' || value.status === 'completed' || value.status === 'archived')
  )
}

function isProduct(value: unknown): value is Product {
  return (
    isRecord(value) &&
    isString(value.id) &&
    isString(value.name) &&
    isFiniteNumber(value.quantity) &&
    (value.unit === 'piece' ||
      value.unit === 'kg' ||
      value.unit === 'g' ||
      value.unit === 'l' ||
      value.unit === 'ml' ||
      value.unit === 'pack') &&
    (value.category === 'produce' ||
      value.category === 'dairy' ||
      value.category === 'meat' ||
      value.category === 'drinks' ||
      value.category === 'household' ||
      value.category === 'other') &&
    isFiniteNumber(value.estimatedPrice) &&
    isString(value.note) &&
    isNullableString(value.storeId) &&
    isString(value.listId) &&
    isString(value.addedBy) &&
    typeof value.isPurchased === 'boolean' &&
    isString(value.createdAt) &&
    isNullableString(value.purchasedAt) &&
    (!('imageUrl' in value) || isNullableString(value.imageUrl)) &&
    (!('imageSourceUrl' in value) || isNullableString(value.imageSourceUrl)) &&
    (!('imageSourceLabel' in value) || isNullableString(value.imageSourceLabel))
  )
}

function isPurchaseHistory(value: unknown): value is PurchaseHistory {
  return (
    isRecord(value) &&
    isString(value.id) &&
    isNullableString(value.storeId) &&
    Array.isArray(value.products) &&
    value.products.every(isProduct) &&
    isFiniteNumber(value.total) &&
    isString(value.date) &&
    isStringArray(value.members)
  )
}

function isNotification(value: unknown): value is AppNotification {
  return (
    isRecord(value) &&
    isString(value.id) &&
    (value.type === 'productAdded' ||
      value.type === 'productPurchased' ||
      value.type === 'listChanged' ||
      value.type === 'memberJoined' ||
      value.type === 'listCompleted') &&
    isString(value.title) &&
    isString(value.message) &&
    isString(value.createdAt) &&
    typeof value.isRead === 'boolean' &&
    isNullableString(value.listId) &&
    isNullableString(value.actorId)
  )
}

function isFrequentProduct(value: unknown): value is FrequentProduct {
  return (
    isRecord(value) &&
    isString(value.id) &&
    isNullableString(value.sourceProductId) &&
    isString(value.name) &&
    (value.unit === 'piece' ||
      value.unit === 'kg' ||
      value.unit === 'g' ||
      value.unit === 'l' ||
      value.unit === 'ml' ||
      value.unit === 'pack') &&
    (value.category === 'produce' ||
      value.category === 'dairy' ||
      value.category === 'meat' ||
      value.category === 'drinks' ||
      value.category === 'household' ||
      value.category === 'other') &&
    isFiniteNumber(value.estimatedPrice) &&
    isFiniteNumber(value.timesAdded) &&
    isString(value.lastAddedAt)
  )
}

function validArray<T>(value: unknown, guard: (item: unknown) => item is T, fallback: T[]): T[] {
  return Array.isArray(value) ? value.filter(guard) : fallback
}

function hydrateSettings(value: unknown, fallback: AppSettings): AppSettings {
  if (!isRecord(value)) {
    return fallback
  }
  return {
    locale: value.locale === 'ru' || value.locale === 'uk' ? value.locale : fallback.locale,
    currency: value.currency === 'UAH' ? value.currency : fallback.currency,
    theme:
      value.theme === 'light' || value.theme === 'dark' || value.theme === 'system'
        ? value.theme
        : fallback.theme,
    defaultUnit:
      value.defaultUnit === 'piece' ||
      value.defaultUnit === 'kg' ||
      value.defaultUnit === 'g' ||
      value.defaultUnit === 'l' ||
      value.defaultUnit === 'ml' ||
      value.defaultUnit === 'pack'
        ? value.defaultUnit
        : fallback.defaultUnit,
    syncEnabled:
      typeof value.syncEnabled === 'boolean' ? value.syncEnabled : fallback.syncEnabled,
  }
}

function hydrateNotificationSettings(
  value: unknown,
  fallback: NotificationSettings,
): NotificationSettings {
  if (!isRecord(value)) {
    return fallback
  }
  return {
    mode: value.mode === 'all' || value.mode === 'important' ? value.mode : fallback.mode,
    mutedListIds: isStringArray(value.mutedListIds)
      ? Array.from(new Set(value.mutedListIds))
      : fallback.mutedListIds,
  }
}

function normalizeRelationships(state: AppState): AppState {
  const userIds = new Set(state.users.map((user) => user.id))
  const storeIds = new Set(state.stores.map((store) => store.id))
  const currentUserId = userIds.has(state.currentUserId)
    ? state.currentUserId
    : (state.users[0]?.id ?? state.currentUserId)

  const shoppingLists = state.shoppingLists.map((list) => {
    const ownerId = userIds.has(list.ownerId) ? list.ownerId : currentUserId
    const members = Array.from(
      new Set([ownerId, ...list.members.filter((memberId) => userIds.has(memberId))]),
    )
    return {
      ...list,
      storeId: list.storeId && storeIds.has(list.storeId) ? list.storeId : null,
      ownerId,
      members,
    }
  })

  const listIds = new Set(shoppingLists.map((list) => list.id))
  const fallbackListId =
    shoppingLists.find((list) => list.status === 'active' && list.storeId === null)?.id ??
    shoppingLists.find((list) => list.status === 'active')?.id ??
    shoppingLists[0]?.id

  const products = state.products
    .filter((product) => listIds.has(product.listId) || Boolean(fallbackListId))
    .map((product) => {
      const storeId = product.storeId && storeIds.has(product.storeId) ? product.storeId : null
      const media = resolveProductMedia(product.name, storeId ?? '')
      return {
        ...product,
        storeId,
        listId: listIds.has(product.listId) ? product.listId : (fallbackListId as string),
        addedBy: userIds.has(product.addedBy) ? product.addedBy : currentUserId,
        imageUrl: product.imageUrl ?? media?.imageUrl ?? null,
        imageSourceUrl: product.imageSourceUrl ?? media?.sourceUrl ?? null,
        imageSourceLabel: product.imageSourceLabel ?? media?.sourceLabel ?? null,
      }
    })

  const purchaseHistory = state.purchaseHistory.map((entry) => ({
    ...entry,
    storeId: entry.storeId && storeIds.has(entry.storeId) ? entry.storeId : null,
    members: entry.members.filter((memberId) => userIds.has(memberId)),
    products: entry.products.map((product) => {
      const storeId = product.storeId && storeIds.has(product.storeId) ? product.storeId : null
      const media = resolveProductMedia(product.name, storeId ?? '')
      return {
        ...product,
        storeId,
        addedBy: userIds.has(product.addedBy) ? product.addedBy : currentUserId,
        imageUrl: product.imageUrl ?? media?.imageUrl ?? null,
        imageSourceUrl: product.imageSourceUrl ?? media?.sourceUrl ?? null,
        imageSourceLabel: product.imageSourceLabel ?? media?.sourceLabel ?? null,
      }
    }),
  }))

  const notifications = state.notifications.map((notification) => ({
    ...notification,
    listId:
      notification.listId && listIds.has(notification.listId) ? notification.listId : null,
    actorId:
      notification.actorId && userIds.has(notification.actorId) ? notification.actorId : null,
  }))

  return {
    ...state,
    currentUserId,
    shoppingLists,
    products,
    purchaseHistory,
    notifications,
    notificationSettings: {
      ...state.notificationSettings,
      mutedListIds: state.notificationSettings.mutedListIds.filter((id) => listIds.has(id)),
    },
  }
}

export function hydrateAppState(
  value: unknown,
  fallback: AppState = createInitialAppState(),
): AppState {
  if (!isRecord(value)) {
    return fallback
  }

  const users = validArray(value.users, isUser, fallback.users)
  const stores = validArray(value.stores, isStore, fallback.stores)
  const shoppingLists = validArray(value.shoppingLists, isShoppingList, fallback.shoppingLists)
  const products = validArray(value.products, isProduct, fallback.products)
  const purchaseHistory = validArray(
    value.purchaseHistory,
    isPurchaseHistory,
    fallback.purchaseHistory,
  )
  const notifications = validArray(value.notifications, isNotification, fallback.notifications)
  const frequentProducts = validArray(
    value.frequentProducts,
    isFrequentProduct,
    fallback.frequentProducts,
  )

  return normalizeRelationships({
    schemaVersion: APP_STATE_VERSION,
    hasCompletedOnboarding:
      typeof value.hasCompletedOnboarding === 'boolean'
        ? value.hasCompletedOnboarding
        : fallback.hasCompletedOnboarding,
    users,
    currentUserId: isString(value.currentUserId) ? value.currentUserId : fallback.currentUserId,
    stores,
    shoppingLists,
    products,
    purchaseHistory,
    notifications,
    settings: hydrateSettings(value.settings, fallback.settings),
    notificationSettings: hydrateNotificationSettings(
      value.notificationSettings,
      fallback.notificationSettings,
    ),
    frequentProducts,
    undo: { deletedProduct: null, productMove: null },
  })
}

function getBrowserStorage(): StorageAdapter | null {
  if (typeof window === 'undefined') {
    return null
  }
  try {
    return window.localStorage
  } catch {
    return null
  }
}

function persistentState(state: AppState): PersistedAppState {
  const { undo: _undo, ...persisted } = state
  return persisted
}

export function serializeAppState(state: AppState): string {
  const envelope: PersistedEnvelope = {
    version: APP_STATE_VERSION,
    savedAt: new Date().toISOString(),
    state: persistentState(state),
  }
  return JSON.stringify(envelope)
}

export function deserializeAppState(
  serialized: string,
  fallback: AppState = createInitialAppState(),
): AppState {
  try {
    const parsed: unknown = JSON.parse(serialized)
    if (!isRecord(parsed)) {
      return fallback
    }

    if ('version' in parsed && isFiniteNumber(parsed.version) && parsed.version > APP_STATE_VERSION) {
      return fallback
    }

    const candidate = 'state' in parsed ? parsed.state : parsed
    return hydrateAppState(candidate, fallback)
  } catch {
    return fallback
  }
}

export function loadAppState(
  fallback: AppState = createInitialAppState(),
  storage: StorageAdapter | null = getBrowserStorage(),
): AppState {
  if (!storage) {
    return fallback
  }
  try {
    const serialized = storage.getItem(APP_STORAGE_KEY)
    return serialized ? deserializeAppState(serialized, fallback) : fallback
  } catch {
    return fallback
  }
}

export function saveAppState(
  state: AppState,
  storage: StorageAdapter | null = getBrowserStorage(),
): boolean {
  if (!storage) {
    return false
  }
  try {
    storage.setItem(APP_STORAGE_KEY, serializeAppState(state))
    return true
  } catch {
    return false
  }
}

export function clearStoredAppState(storage: StorageAdapter | null = getBrowserStorage()): boolean {
  if (!storage) {
    return false
  }
  try {
    storage.removeItem(APP_STORAGE_KEY)
    return true
  } catch {
    return false
  }
}
