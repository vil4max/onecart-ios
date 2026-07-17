import type {
  AppNotification,
  AppSettings,
  EntityId,
  FrequentProduct,
  Locale,
  NotificationMode,
  NotificationSettings,
  NotificationType,
  Product,
  ProductCategory,
  ProductUnit,
  PurchaseHistory,
  ShoppingList,
  Store,
  User,
  UserRole,
} from '../domain/models'
import { createMockData } from '../data/mockData'
import { resolveProductMedia } from '../data/productMedia'

export const APP_STATE_VERSION = 1

export interface DeletedProductUndo {
  product: Product
  index: number
}

export interface ProductMoveUndo {
  productId: EntityId
  fromStoreId: EntityId | null
  fromListId: EntityId
  toStoreId: EntityId | null
  toListId: EntityId
}

export interface UndoState {
  deletedProduct: DeletedProductUndo | null
  productMove: ProductMoveUndo | null
}

export interface AppState {
  schemaVersion: number
  hasCompletedOnboarding: boolean
  users: ReturnType<typeof createMockData>['users']
  currentUserId: EntityId
  stores: Store[]
  shoppingLists: ShoppingList[]
  products: Product[]
  purchaseHistory: PurchaseHistory[]
  notifications: AppNotification[]
  settings: AppSettings
  notificationSettings: NotificationSettings
  frequentProducts: FrequentProduct[]
  undo: UndoState
}

export interface NewProductInput {
  id?: EntityId
  name: string
  quantity?: number
  unit?: ProductUnit
  category?: ProductCategory
  estimatedPrice?: number
  note?: string
  storeId?: EntityId | null
  listId: EntityId
  addedBy: EntityId
  isPurchased?: boolean
  createdAt?: string
  purchasedAt?: string | null
  imageUrl?: string | null
  imageSourceUrl?: string | null
  imageSourceLabel?: string | null
}

export interface NewUserInput {
  id?: EntityId
  name: string
  email: string
  avatar?: string | null
  role?: UserRole
}

export interface NewStoreInput {
  id?: EntityId
  name: string
  icon?: string
  color?: string
  city?: string | null
  address?: string | null
  latitude?: number | null
  longitude?: number | null
  externalAppUrl?: string | null
  isPinned?: boolean
}

export interface NewShoppingListInput {
  id?: EntityId
  title: string
  storeId?: EntityId | null
  ownerId: EntityId
  members?: EntityId[]
  createdAt?: string
}

export interface NewNotificationInput {
  id?: EntityId
  type: NotificationType
  title: string
  message: string
  createdAt?: string
  isRead?: boolean
  listId?: EntityId | null
  actorId?: EntityId | null
}

export interface NewFrequentProductInput {
  id?: EntityId
  sourceProductId?: EntityId | null
  name: string
  unit?: ProductUnit
  category?: ProductCategory
  estimatedPrice?: number
  timesAdded?: number
  lastAddedAt?: string
}

export type AppAction =
  | { type: 'app/hydrate'; payload: AppState }
  | { type: 'onboarding/setCompleted'; payload: boolean }
  | { type: 'user/add'; payload: User }
  | { type: 'user/setRole'; payload: { userId: EntityId; role: UserRole } }
  | { type: 'user/remove'; payload: EntityId }
  | { type: 'product/add'; payload: { product: Product; changedAt: string } }
  | {
      type: 'product/update'
      payload: { productId: EntityId; changes: Partial<Omit<Product, 'id'>>; changedAt: string }
    }
  | { type: 'product/delete'; payload: { productId: EntityId; changedAt: string } }
  | { type: 'product/undoDelete'; payload: { changedAt: string } }
  | { type: 'product/togglePurchased'; payload: { productId: EntityId; changedAt: string } }
  | {
      type: 'product/move'
      payload: {
        productId: EntityId
        storeId: EntityId | null
        listId?: EntityId
        changedAt: string
      }
    }
  | { type: 'product/undoMove'; payload: { changedAt: string } }
  | { type: 'store/add'; payload: Store }
  | {
      type: 'store/update'
      payload: { storeId: EntityId; changes: Partial<Omit<Store, 'id'>> }
    }
  | { type: 'store/delete'; payload: { storeId: EntityId; changedAt: string } }
  | { type: 'store/setPinned'; payload: { storeId: EntityId; isPinned?: boolean } }
  | { type: 'list/create'; payload: ShoppingList }
  | {
      type: 'list/setMember'
      payload: { listId: EntityId; userId: EntityId; isMember: boolean; changedAt: string }
    }
  | {
      type: 'list/complete'
      payload: { listId: EntityId; historyId: EntityId; completedAt: string }
    }
  | {
      type: 'history/repeat'
      payload: {
        historyId: EntityId
        newListId: EntityId
        repeatedAt: string
        title?: string
      }
    }
  | { type: 'history/delete'; payload: EntityId }
  | { type: 'settings/setLocale'; payload: Locale }
  | { type: 'settings/update'; payload: Partial<AppSettings> }
  | { type: 'notifications/add'; payload: AppNotification }
  | { type: 'notifications/markRead'; payload: { notificationId: EntityId; isRead: boolean } }
  | { type: 'notifications/markAllRead' }
  | { type: 'notifications/setMode'; payload: NotificationMode }
  | {
      type: 'notifications/setListMuted'
      payload: { listId: EntityId; isMuted?: boolean }
    }
  | { type: 'frequent/add'; payload: FrequentProduct }
  | { type: 'frequent/toggleProduct'; payload: { productId: EntityId; changedAt: string } }
  | { type: 'frequent/remove'; payload: EntityId }
  | { type: 'frequent/recordUse'; payload: { frequentProductId: EntityId; usedAt: string } }

function createEntityId(prefix: string): EntityId {
  const randomId = globalThis.crypto?.randomUUID?.()
  if (randomId) {
    return `${prefix}-${randomId}`
  }

  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`
}

function nowIso(): string {
  return new Date().toISOString()
}

function nonNegative(value: number | undefined, fallback = 0): number {
  if (value === undefined || !Number.isFinite(value)) {
    return fallback
  }
  return Math.max(0, value)
}

function positive(value: number | undefined, fallback = 1): number {
  if (value === undefined || !Number.isFinite(value) || value <= 0) {
    return fallback
  }
  return value
}

export const appActions = {
  hydrate: (state: AppState): AppAction => ({ type: 'app/hydrate', payload: state }),

  completeOnboarding: (): AppAction => ({ type: 'onboarding/setCompleted', payload: true }),
  resetOnboarding: (): AppAction => ({ type: 'onboarding/setCompleted', payload: false }),
  setOnboardingCompleted: (isCompleted: boolean): AppAction => ({
    type: 'onboarding/setCompleted',
    payload: isCompleted,
  }),

  addUser: (input: NewUserInput): AppAction => ({
    type: 'user/add',
    payload: {
      id: input.id ?? createEntityId('user'),
      name: input.name.trim(),
      email: input.email.trim(),
      avatar: input.avatar ?? null,
      role: input.role ?? 'viewer',
    },
  }),

  setUserRole: (userId: EntityId, role: UserRole): AppAction => ({
    type: 'user/setRole',
    payload: { userId, role },
  }),

  removeUser: (userId: EntityId): AppAction => ({ type: 'user/remove', payload: userId }),

  addProduct: (input: NewProductInput): AppAction => {
    const createdAt = input.createdAt ?? nowIso()
    const isPurchased = input.isPurchased ?? false
    const media = resolveProductMedia(input.name, input.storeId ?? '')
    const product: Product = {
      id: input.id ?? createEntityId('product'),
      name: input.name.trim(),
      quantity: positive(input.quantity),
      unit: input.unit ?? 'piece',
      category: input.category ?? 'other',
      estimatedPrice: nonNegative(input.estimatedPrice),
      note: input.note?.trim() ?? '',
      storeId: input.storeId ?? null,
      listId: input.listId,
      addedBy: input.addedBy,
      isPurchased,
      createdAt,
      purchasedAt: isPurchased ? (input.purchasedAt ?? createdAt) : null,
      imageUrl: input.imageUrl ?? media?.imageUrl ?? null,
      imageSourceUrl: input.imageSourceUrl ?? media?.sourceUrl ?? null,
      imageSourceLabel: input.imageSourceLabel ?? media?.sourceLabel ?? null,
    }
    return { type: 'product/add', payload: { product, changedAt: createdAt } }
  },

  updateProduct: (
    productId: EntityId,
    changes: Partial<Omit<Product, 'id'>>,
    changedAt = nowIso(),
  ): AppAction => ({ type: 'product/update', payload: { productId, changes, changedAt } }),

  deleteProduct: (productId: EntityId, changedAt = nowIso()): AppAction => ({
    type: 'product/delete',
    payload: { productId, changedAt },
  }),

  undoDeleteProduct: (changedAt = nowIso()): AppAction => ({
    type: 'product/undoDelete',
    payload: { changedAt },
  }),

  toggleProductPurchased: (productId: EntityId, changedAt = nowIso()): AppAction => ({
    type: 'product/togglePurchased',
    payload: { productId, changedAt },
  }),

  moveProduct: (
    productId: EntityId,
    storeId: EntityId | null,
    listId?: EntityId,
    changedAt = nowIso(),
  ): AppAction => ({
    type: 'product/move',
    payload: { productId, storeId, listId, changedAt },
  }),

  undoMoveProduct: (changedAt = nowIso()): AppAction => ({
    type: 'product/undoMove',
    payload: { changedAt },
  }),

  addStore: (input: NewStoreInput): AppAction => ({
    type: 'store/add',
    payload: {
      id: input.id ?? createEntityId('store'),
      name: input.name.trim(),
      icon: input.icon?.trim() || input.name.trim().slice(0, 2).toUpperCase(),
      color: input.color ?? '#34785B',
      city: input.city?.trim() || null,
      address: input.address?.trim() || null,
      latitude: input.latitude ?? null,
      longitude: input.longitude ?? null,
      externalAppUrl: input.externalAppUrl?.trim() || null,
      isPinned: input.isPinned ?? false,
    },
  }),

  updateStore: (storeId: EntityId, changes: Partial<Omit<Store, 'id'>>): AppAction => ({
    type: 'store/update',
    payload: { storeId, changes },
  }),

  deleteStore: (storeId: EntityId, changedAt = nowIso()): AppAction => ({
    type: 'store/delete',
    payload: { storeId, changedAt },
  }),

  setStorePinned: (storeId: EntityId, isPinned?: boolean): AppAction => ({
    type: 'store/setPinned',
    payload: { storeId, isPinned },
  }),

  createList: (input: NewShoppingListInput): AppAction => {
    const createdAt = input.createdAt ?? nowIso()
    return {
      type: 'list/create',
      payload: {
        id: input.id ?? createEntityId('list'),
        title: input.title.trim(),
        storeId: input.storeId ?? null,
        ownerId: input.ownerId,
        members: Array.from(new Set(input.members ?? [input.ownerId])),
        createdAt,
        updatedAt: createdAt,
        status: 'active',
      },
    }
  },

  setListMember: (
    listId: EntityId,
    userId: EntityId,
    isMember: boolean,
    changedAt = nowIso(),
  ): AppAction => ({
    type: 'list/setMember',
    payload: { listId, userId, isMember, changedAt },
  }),

  completeList: (listId: EntityId, completedAt = nowIso()): AppAction => ({
    type: 'list/complete',
    payload: { listId, historyId: createEntityId('history'), completedAt },
  }),

  repeatHistory: (
    historyId: EntityId,
    options: { title?: string; repeatedAt?: string; newListId?: EntityId } = {},
  ): AppAction => ({
    type: 'history/repeat',
    payload: {
      historyId,
      newListId: options.newListId ?? createEntityId('list'),
      repeatedAt: options.repeatedAt ?? nowIso(),
      title: options.title,
    },
  }),

  deleteHistory: (historyId: EntityId): AppAction => ({
    type: 'history/delete',
    payload: historyId,
  }),

  setLocale: (locale: Locale): AppAction => ({ type: 'settings/setLocale', payload: locale }),
  updateSettings: (changes: Partial<AppSettings>): AppAction => ({
    type: 'settings/update',
    payload: changes,
  }),

  addNotification: (input: NewNotificationInput): AppAction => ({
    type: 'notifications/add',
    payload: {
      id: input.id ?? createEntityId('notification'),
      type: input.type,
      title: input.title,
      message: input.message,
      createdAt: input.createdAt ?? nowIso(),
      isRead: input.isRead ?? false,
      listId: input.listId ?? null,
      actorId: input.actorId ?? null,
    },
  }),

  markNotificationRead: (notificationId: EntityId, isRead = true): AppAction => ({
    type: 'notifications/markRead',
    payload: { notificationId, isRead },
  }),
  markAllNotificationsRead: (): AppAction => ({ type: 'notifications/markAllRead' }),
  setNotificationMode: (mode: NotificationMode): AppAction => ({
    type: 'notifications/setMode',
    payload: mode,
  }),
  setListNotificationsMuted: (listId: EntityId, isMuted?: boolean): AppAction => ({
    type: 'notifications/setListMuted',
    payload: { listId, isMuted },
  }),

  addFrequentProduct: (input: NewFrequentProductInput): AppAction => ({
    type: 'frequent/add',
    payload: {
      id: input.id ?? createEntityId('frequent'),
      sourceProductId: input.sourceProductId ?? null,
      name: input.name.trim(),
      unit: input.unit ?? 'piece',
      category: input.category ?? 'other',
      estimatedPrice: nonNegative(input.estimatedPrice),
      timesAdded: Math.max(1, Math.floor(input.timesAdded ?? 1)),
      lastAddedAt: input.lastAddedAt ?? nowIso(),
    },
  }),
  toggleProductFrequent: (productId: EntityId, changedAt = nowIso()): AppAction => ({
    type: 'frequent/toggleProduct',
    payload: { productId, changedAt },
  }),
  removeFrequentProduct: (frequentProductId: EntityId): AppAction => ({
    type: 'frequent/remove',
    payload: frequentProductId,
  }),
  recordFrequentUse: (frequentProductId: EntityId, usedAt = nowIso()): AppAction => ({
    type: 'frequent/recordUse',
    payload: { frequentProductId, usedAt },
  }),
}

export function createInitialAppState(): AppState {
  const mock = createMockData()
  return {
    schemaVersion: APP_STATE_VERSION,
    hasCompletedOnboarding: false,
    ...mock,
    undo: {
      deletedProduct: null,
      productMove: null,
    },
  }
}

export const initialAppState = createInitialAppState()

function touchLists(lists: ShoppingList[], listIds: EntityId[], changedAt: string): ShoppingList[] {
  const ids = new Set(listIds)
  if (ids.size === 0) {
    return lists
  }
  return lists.map((list) => (ids.has(list.id) ? { ...list, updatedAt: changedAt } : list))
}

function listForDestination(
  state: AppState,
  storeId: EntityId | null,
  requestedListId: EntityId | undefined,
  fallbackListId: EntityId,
): EntityId {
  if (requestedListId && state.shoppingLists.some((list) => list.id === requestedListId)) {
    return requestedListId
  }

  const destination = state.shoppingLists.find(
    (list) => list.status === 'active' && list.storeId === storeId,
  )
  return destination?.id ?? fallbackListId
}

function shouldAddGeneratedNotification(
  state: AppState,
  type: NotificationType,
  listId: EntityId | null,
): boolean {
  if (listId && state.notificationSettings.mutedListIds.includes(listId)) {
    return false
  }
  if (state.notificationSettings.mode === 'all') {
    return true
  }
  return type === 'productPurchased' || type === 'memberJoined' || type === 'listCompleted'
}

function generatedNotification(
  state: AppState,
  input: {
    id: EntityId
    type: NotificationType
    productName?: string
    listTitle?: string
    listId: EntityId | null
    createdAt: string
  },
): AppNotification | null {
  if (!shouldAddGeneratedNotification(state, input.type, input.listId)) {
    return null
  }

  const isUkrainian = state.settings.locale === 'uk'
  const copy: Record<NotificationType, { title: string; message: string }> = {
    productAdded: {
      title: isUkrainian ? 'Новий товар' : 'Новый товар',
      message: isUkrainian
        ? `Додано «${input.productName ?? ''}»`
        : `Добавлено «${input.productName ?? ''}»`,
    },
    productPurchased: {
      title: isUkrainian ? 'Товар куплено' : 'Товар куплен',
      message: isUkrainian
        ? `«${input.productName ?? ''}» позначено як куплене`
        : `«${input.productName ?? ''}» отмечено как купленное`,
    },
    listChanged: {
      title: isUkrainian ? 'Список змінено' : 'Список изменён',
      message: isUkrainian
        ? `Оновлено «${input.listTitle ?? ''}»`
        : `Обновлён «${input.listTitle ?? ''}»`,
    },
    memberJoined: {
      title: isUkrainian ? 'Новий учасник' : 'Новый участник',
      message: isUkrainian ? 'До списку приєднався учасник' : 'К списку присоединился участник',
    },
    listCompleted: {
      title: isUkrainian ? 'Список завершено' : 'Список завершён',
      message: isUkrainian
        ? `«${input.listTitle ?? ''}» завершено`
        : `«${input.listTitle ?? ''}» завершён`,
    },
  }

  return {
    id: input.id,
    type: input.type,
    title: copy[input.type].title,
    message: copy[input.type].message,
    createdAt: input.createdAt,
    isRead: false,
    listId: input.listId,
    actorId: state.currentUserId,
  }
}

function prependNotification(state: AppState, notification: AppNotification | null): AppNotification[] {
  if (!notification || state.notifications.some((item) => item.id === notification.id)) {
    return state.notifications
  }
  return [notification, ...state.notifications]
}

function estimatedTotal(products: Product[]): number {
  return products.reduce((total, product) => total + Math.max(0, product.estimatedPrice), 0)
}

export function appReducer(state: AppState, action: AppAction): AppState {
  switch (action.type) {
    case 'app/hydrate':
      return {
        ...action.payload,
        schemaVersion: APP_STATE_VERSION,
        undo: { deletedProduct: null, productMove: null },
      }

    case 'onboarding/setCompleted':
      return { ...state, hasCompletedOnboarding: action.payload }

    case 'user/add': {
      const user = action.payload
      if (
        !user.name ||
        !user.email ||
        user.role === 'owner' ||
        state.users.some(
          (item) =>
            item.id === user.id || item.email.toLocaleLowerCase() === user.email.toLocaleLowerCase(),
        )
      ) {
        return state
      }
      return { ...state, users: [...state.users, user] }
    }

    case 'user/setRole': {
      const existing = state.users.find((user) => user.id === action.payload.userId)
      if (!existing || existing.role === 'owner' || action.payload.role === 'owner') {
        return state
      }
      return {
        ...state,
        users: state.users.map((user) =>
          user.id === existing.id ? { ...user, role: action.payload.role } : user,
        ),
      }
    }

    case 'user/remove': {
      const existing = state.users.find((user) => user.id === action.payload)
      if (!existing || existing.id === state.currentUserId || existing.role === 'owner') {
        return state
      }
      return {
        ...state,
        users: state.users.filter((user) => user.id !== existing.id),
        shoppingLists: state.shoppingLists.map((list) => ({
          ...list,
          members: list.members.filter((memberId) => memberId !== existing.id),
        })),
        products: state.products.map((product) =>
          product.addedBy === existing.id
            ? { ...product, addedBy: state.currentUserId }
            : product,
        ),
        purchaseHistory: state.purchaseHistory.map((entry) => ({
          ...entry,
          members: entry.members.filter((memberId) => memberId !== existing.id),
          products: entry.products.map((product) =>
            product.addedBy === existing.id
              ? { ...product, addedBy: state.currentUserId }
              : product,
          ),
        })),
        notifications: state.notifications.map((notification) =>
          notification.actorId === existing.id ? { ...notification, actorId: null } : notification,
        ),
      }
    }

    case 'product/add': {
      const { product, changedAt } = action.payload
      if (!product.name || state.products.some((item) => item.id === product.id)) {
        return state
      }
      const notification = generatedNotification(state, {
        id: `notification-product-added-${product.id}`,
        type: 'productAdded',
        productName: product.name,
        listId: product.listId,
        createdAt: changedAt,
      })
      return {
        ...state,
        products: [...state.products, product],
        shoppingLists: touchLists(state.shoppingLists, [product.listId], changedAt),
        notifications: prependNotification(state, notification),
        undo: { ...state.undo, deletedProduct: null },
      }
    }

    case 'product/update': {
      const existing = state.products.find((product) => product.id === action.payload.productId)
      if (!existing) {
        return state
      }
      const next: Product = {
        ...existing,
        ...action.payload.changes,
        quantity:
          action.payload.changes.quantity === undefined
            ? existing.quantity
            : positive(action.payload.changes.quantity, existing.quantity),
        estimatedPrice:
          action.payload.changes.estimatedPrice === undefined
            ? existing.estimatedPrice
            : nonNegative(action.payload.changes.estimatedPrice, existing.estimatedPrice),
        name: action.payload.changes.name?.trim() || existing.name,
        note: action.payload.changes.note?.trim() ?? existing.note,
      }
      return {
        ...state,
        products: state.products.map((product) => (product.id === existing.id ? next : product)),
        shoppingLists: touchLists(
          state.shoppingLists,
          [existing.listId, next.listId],
          action.payload.changedAt,
        ),
      }
    }

    case 'product/delete': {
      const index = state.products.findIndex((product) => product.id === action.payload.productId)
      if (index < 0) {
        return state
      }
      const product = state.products[index]
      return {
        ...state,
        products: state.products.filter((item) => item.id !== product.id),
        shoppingLists: touchLists(state.shoppingLists, [product.listId], action.payload.changedAt),
        undo: {
          ...state.undo,
          deletedProduct: { product, index },
          productMove:
            state.undo.productMove?.productId === product.id ? null : state.undo.productMove,
        },
      }
    }

    case 'product/undoDelete': {
      const deleted = state.undo.deletedProduct
      if (!deleted || state.products.some((product) => product.id === deleted.product.id)) {
        return deleted ? { ...state, undo: { ...state.undo, deletedProduct: null } } : state
      }
      const insertAt = Math.min(Math.max(0, deleted.index), state.products.length)
      const products = [...state.products]
      products.splice(insertAt, 0, deleted.product)
      return {
        ...state,
        products,
        shoppingLists: touchLists(
          state.shoppingLists,
          [deleted.product.listId],
          action.payload.changedAt,
        ),
        undo: { ...state.undo, deletedProduct: null },
      }
    }

    case 'product/togglePurchased': {
      const existing = state.products.find((product) => product.id === action.payload.productId)
      if (!existing) {
        return state
      }
      const isPurchased = !existing.isPurchased
      const notification = isPurchased
        ? generatedNotification(state, {
            id: `notification-product-purchased-${existing.id}-${action.payload.changedAt}`,
            type: 'productPurchased',
            productName: existing.name,
            listId: existing.listId,
            createdAt: action.payload.changedAt,
          })
        : null
      return {
        ...state,
        products: state.products.map((product) =>
          product.id === existing.id
            ? {
                ...product,
                isPurchased,
                purchasedAt: isPurchased ? action.payload.changedAt : null,
              }
            : product,
        ),
        shoppingLists: touchLists(
          state.shoppingLists,
          [existing.listId],
          action.payload.changedAt,
        ),
        notifications: prependNotification(state, notification),
      }
    }

    case 'product/move': {
      const existing = state.products.find((product) => product.id === action.payload.productId)
      if (!existing) {
        return state
      }
      const nextStoreId =
        action.payload.storeId && state.stores.some((store) => store.id === action.payload.storeId)
          ? action.payload.storeId
          : null
      const nextListId = listForDestination(
        state,
        nextStoreId,
        action.payload.listId,
        existing.listId,
      )
      if (existing.storeId === nextStoreId && existing.listId === nextListId) {
        return state
      }
      const destinationList = state.shoppingLists.find((list) => list.id === nextListId)
      const notification = generatedNotification(state, {
        id: `notification-product-moved-${existing.id}-${action.payload.changedAt}`,
        type: 'listChanged',
        listTitle: destinationList?.title ?? '',
        listId: nextListId,
        createdAt: action.payload.changedAt,
      })
      return {
        ...state,
        products: state.products.map((product) =>
          product.id === existing.id
            ? { ...product, storeId: nextStoreId, listId: nextListId }
            : product,
        ),
        shoppingLists: touchLists(
          state.shoppingLists,
          [existing.listId, nextListId],
          action.payload.changedAt,
        ),
        notifications: prependNotification(state, notification),
        undo: {
          ...state.undo,
          productMove: {
            productId: existing.id,
            fromStoreId: existing.storeId,
            fromListId: existing.listId,
            toStoreId: nextStoreId,
            toListId: nextListId,
          },
        },
      }
    }

    case 'product/undoMove': {
      const move = state.undo.productMove
      if (!move) {
        return state
      }
      const product = state.products.find((item) => item.id === move.productId)
      if (!product) {
        return { ...state, undo: { ...state.undo, productMove: null } }
      }
      const restoredStoreId =
        move.fromStoreId && !state.stores.some((store) => store.id === move.fromStoreId)
          ? null
          : move.fromStoreId
      const restoredListId = state.shoppingLists.some((list) => list.id === move.fromListId)
        ? move.fromListId
        : product.listId
      return {
        ...state,
        products: state.products.map((item) =>
          item.id === move.productId
            ? { ...item, storeId: restoredStoreId, listId: restoredListId }
            : item,
        ),
        shoppingLists: touchLists(
          state.shoppingLists,
          [product.listId, restoredListId],
          action.payload.changedAt,
        ),
        undo: { ...state.undo, productMove: null },
      }
    }

    case 'store/add':
      if (!action.payload.name || state.stores.some((store) => store.id === action.payload.id)) {
        return state
      }
      return { ...state, stores: [...state.stores, action.payload] }

    case 'store/update':
      if (!state.stores.some((store) => store.id === action.payload.storeId)) {
        return state
      }
      return {
        ...state,
        stores: state.stores.map((store) =>
          store.id === action.payload.storeId ? { ...store, ...action.payload.changes } : store,
        ),
      }

    case 'store/delete': {
      if (!state.stores.some((store) => store.id === action.payload.storeId)) {
        return state
      }
      return {
        ...state,
        stores: state.stores.filter((store) => store.id !== action.payload.storeId),
        shoppingLists: state.shoppingLists.map((list) =>
          list.storeId === action.payload.storeId
            ? { ...list, storeId: null, updatedAt: action.payload.changedAt }
            : list,
        ),
        products: state.products.map((product) =>
          product.storeId === action.payload.storeId ? { ...product, storeId: null } : product,
        ),
        purchaseHistory: state.purchaseHistory.map((entry) =>
          entry.storeId === action.payload.storeId ? { ...entry, storeId: null } : entry,
        ),
        undo: {
          ...state.undo,
          productMove:
            state.undo.productMove &&
            (state.undo.productMove.fromStoreId === action.payload.storeId ||
              state.undo.productMove.toStoreId === action.payload.storeId)
              ? null
              : state.undo.productMove,
        },
      }
    }

    case 'store/setPinned':
      if (!state.stores.some((store) => store.id === action.payload.storeId)) {
        return state
      }
      return {
        ...state,
        stores: state.stores.map((store) =>
          store.id === action.payload.storeId
            ? { ...store, isPinned: action.payload.isPinned ?? !store.isPinned }
            : store,
        ),
      }

    case 'list/create':
      if (
        !action.payload.title ||
        state.shoppingLists.some((list) => list.id === action.payload.id) ||
        state.shoppingLists.some(
          (list) => list.status === 'active' && list.storeId === action.payload.storeId,
        )
      ) {
        return state
      }
      return { ...state, shoppingLists: [...state.shoppingLists, action.payload] }

    case 'list/setMember': {
      const list = state.shoppingLists.find((item) => item.id === action.payload.listId)
      const userExists = state.users.some((user) => user.id === action.payload.userId)
      if (!list || !userExists || (!action.payload.isMember && list.ownerId === action.payload.userId)) {
        return state
      }
      const hasMember = list.members.includes(action.payload.userId)
      if (hasMember === action.payload.isMember) return state
      return {
        ...state,
        shoppingLists: state.shoppingLists.map((item) =>
          item.id === list.id
            ? {
                ...item,
                members: action.payload.isMember
                  ? [...item.members, action.payload.userId]
                  : item.members.filter((memberId) => memberId !== action.payload.userId),
                updatedAt: action.payload.changedAt,
              }
            : item,
        ),
      }
    }

    case 'list/complete': {
      const list = state.shoppingLists.find((item) => item.id === action.payload.listId)
      if (!list || list.status !== 'active') {
        return state
      }
      const sourceProducts = state.products.filter((product) => product.listId === list.id)
      const completedProducts = sourceProducts.map((product) => ({
        ...product,
        isPurchased: true,
        purchasedAt: product.purchasedAt ?? action.payload.completedAt,
      }))
      const completedById = new Map(completedProducts.map((product) => [product.id, product]))
      const history: PurchaseHistory = {
        id: action.payload.historyId,
        storeId: list.storeId,
        products: completedProducts.map((product) => ({ ...product })),
        total: estimatedTotal(completedProducts),
        date: action.payload.completedAt,
        members: [...list.members],
      }
      const notification = generatedNotification(state, {
        id: `notification-list-completed-${history.id}`,
        type: 'listCompleted',
        listTitle: list.title,
        listId: list.id,
        createdAt: action.payload.completedAt,
      })
      return {
        ...state,
        shoppingLists: state.shoppingLists.map((item) =>
          item.id === list.id
            ? { ...item, status: 'completed', updatedAt: action.payload.completedAt }
            : item,
        ),
        products: state.products.map((product) => completedById.get(product.id) ?? product),
        purchaseHistory: [history, ...state.purchaseHistory],
        notifications: prependNotification(state, notification),
      }
    }

    case 'history/repeat': {
      const history = state.purchaseHistory.find((item) => item.id === action.payload.historyId)
      if (!history) {
        return state
      }
      const store = state.stores.find((item) => item.id === history.storeId)
      const destinationStoreId = history.storeId && store ? history.storeId : null
      const existingList = state.shoppingLists.find(
        (list) => list.status === 'active' && list.storeId === destinationStoreId,
      )
      const requestedIdAlreadyExists = state.shoppingLists.some(
        (list) => list.id === action.payload.newListId,
      )
      const repeatedProductIds = history.products.map(
        (_product, index) => `${action.payload.newListId}-product-${index + 1}`,
      )
      if (
        requestedIdAlreadyExists ||
        repeatedProductIds.some((productId) =>
          state.products.some((product) => product.id === productId),
        )
      ) {
        return state
      }
      const list: ShoppingList =
        existingList ??
        ({
          id: action.payload.newListId,
          title:
            action.payload.title?.trim() ||
            (store ? `Повтор — ${store.name}` : 'Повтор списка покупок'),
          storeId: destinationStoreId,
          ownerId: state.currentUserId,
          members: Array.from(new Set([state.currentUserId, ...history.members])),
          createdAt: action.payload.repeatedAt,
          updatedAt: action.payload.repeatedAt,
          status: 'active',
        } satisfies ShoppingList)
      const products = history.products.map<Product>((product, index) => ({
        ...product,
        id: repeatedProductIds[index],
        storeId: list.storeId,
        listId: list.id,
        addedBy: state.currentUserId,
        isPurchased: false,
        createdAt: action.payload.repeatedAt,
        purchasedAt: null,
      }))
      return {
        ...state,
        shoppingLists: existingList
          ? state.shoppingLists.map((item) =>
              item.id === existingList.id
                ? {
                    ...item,
                    members: Array.from(
                      new Set([...item.members, state.currentUserId, ...history.members]),
                    ),
                    updatedAt: action.payload.repeatedAt,
                  }
                : item,
            )
          : [...state.shoppingLists, list],
        products: [...state.products, ...products],
      }
    }

    case 'history/delete':
      if (!state.purchaseHistory.some((entry) => entry.id === action.payload)) {
        return state
      }
      return {
        ...state,
        purchaseHistory: state.purchaseHistory.filter((entry) => entry.id !== action.payload),
      }

    case 'settings/setLocale':
      return { ...state, settings: { ...state.settings, locale: action.payload } }

    case 'settings/update':
      return { ...state, settings: { ...state.settings, ...action.payload } }

    case 'notifications/add':
      if (state.notifications.some((notification) => notification.id === action.payload.id)) {
        return state
      }
      return { ...state, notifications: [action.payload, ...state.notifications] }

    case 'notifications/markRead':
      return {
        ...state,
        notifications: state.notifications.map((notification) =>
          notification.id === action.payload.notificationId
            ? { ...notification, isRead: action.payload.isRead }
            : notification,
        ),
      }

    case 'notifications/markAllRead':
      return {
        ...state,
        notifications: state.notifications.map((notification) =>
          notification.isRead ? notification : { ...notification, isRead: true },
        ),
      }

    case 'notifications/setMode':
      return {
        ...state,
        notificationSettings: { ...state.notificationSettings, mode: action.payload },
      }

    case 'notifications/setListMuted': {
      const isCurrentlyMuted = state.notificationSettings.mutedListIds.includes(action.payload.listId)
      const shouldMute = action.payload.isMuted ?? !isCurrentlyMuted
      const mutedListIds = shouldMute
        ? Array.from(new Set([...state.notificationSettings.mutedListIds, action.payload.listId]))
        : state.notificationSettings.mutedListIds.filter((id) => id !== action.payload.listId)
      return {
        ...state,
        notificationSettings: { ...state.notificationSettings, mutedListIds },
      }
    }

    case 'frequent/add': {
      const duplicate = state.frequentProducts.find(
        (item) => item.name.trim().toLocaleLowerCase() === action.payload.name.toLocaleLowerCase(),
      )
      if (duplicate) {
        return {
          ...state,
          frequentProducts: state.frequentProducts.map((item) =>
            item.id === duplicate.id
              ? {
                  ...item,
                  timesAdded: item.timesAdded + action.payload.timesAdded,
                  lastAddedAt: action.payload.lastAddedAt,
                }
              : item,
          ),
        }
      }
      return { ...state, frequentProducts: [...state.frequentProducts, action.payload] }
    }

    case 'frequent/toggleProduct': {
      const product = state.products.find((item) => item.id === action.payload.productId)
      if (!product) {
        return state
      }
      const frequent = state.frequentProducts.find(
        (item) =>
          item.sourceProductId === product.id ||
          item.name.trim().toLocaleLowerCase() === product.name.trim().toLocaleLowerCase(),
      )
      if (frequent) {
        return {
          ...state,
          frequentProducts: state.frequentProducts.filter((item) => item.id !== frequent.id),
        }
      }
      return {
        ...state,
        frequentProducts: [
          ...state.frequentProducts,
          {
            id: `frequent-${product.id}`,
            sourceProductId: product.id,
            name: product.name,
            unit: product.unit,
            category: product.category,
            estimatedPrice: product.estimatedPrice,
            timesAdded: 1,
            lastAddedAt: action.payload.changedAt,
          },
        ],
      }
    }

    case 'frequent/remove':
      if (!state.frequentProducts.some((item) => item.id === action.payload)) {
        return state
      }
      return {
        ...state,
        frequentProducts: state.frequentProducts.filter((item) => item.id !== action.payload),
      }

    case 'frequent/recordUse':
      return {
        ...state,
        frequentProducts: state.frequentProducts.map((item) =>
          item.id === action.payload.frequentProductId
            ? {
                ...item,
                timesAdded: item.timesAdded + 1,
                lastAddedAt: action.payload.usedAt,
              }
            : item,
        ),
      }

    default:
      return state
  }
}
