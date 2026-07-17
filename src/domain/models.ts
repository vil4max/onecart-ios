export type EntityId = string
export type ISODateString = string

export type UserRole = 'owner' | 'editor' | 'viewer'

export interface User {
  id: EntityId
  name: string
  email: string
  avatar: string | null
  role: UserRole
}

export interface Store {
  id: EntityId
  name: string
  icon: string
  color: string
  city?: string | null
  address: string | null
  latitude?: number | null
  longitude?: number | null
  externalAppUrl: string | null
  isPinned: boolean
}

export type ShoppingListStatus = 'active' | 'completed' | 'archived'

export interface ShoppingList {
  id: EntityId
  title: string
  storeId: EntityId | null
  ownerId: EntityId
  members: EntityId[]
  createdAt: ISODateString
  updatedAt: ISODateString
  status: ShoppingListStatus
}

export const PRODUCT_UNITS = ['piece', 'kg', 'g', 'l', 'ml', 'pack'] as const
export type ProductUnit = (typeof PRODUCT_UNITS)[number]

export const PRODUCT_CATEGORIES = [
  'produce',
  'dairy',
  'meat',
  'drinks',
  'household',
  'other',
] as const
export type ProductCategory = (typeof PRODUCT_CATEGORIES)[number]

export interface Product {
  id: EntityId
  name: string
  quantity: number
  unit: ProductUnit
  category: ProductCategory
  estimatedPrice: number
  note: string
  storeId: EntityId | null
  listId: EntityId
  addedBy: EntityId
  isPurchased: boolean
  createdAt: ISODateString
  purchasedAt: ISODateString | null
  imageUrl?: string | null
  imageSourceUrl?: string | null
  imageSourceLabel?: string | null
}

export interface PurchaseHistory {
  id: EntityId
  storeId: EntityId | null
  products: Product[]
  total: number
  date: ISODateString
  members: EntityId[]
}

export type Locale = 'ru' | 'uk'
export type Currency = 'UAH'
export type ThemePreference = 'light' | 'dark' | 'system'

export interface AppSettings {
  locale: Locale
  currency: Currency
  theme: ThemePreference
  defaultUnit: ProductUnit
  syncEnabled: boolean
}

export type NotificationType =
  | 'productAdded'
  | 'productPurchased'
  | 'listChanged'
  | 'memberJoined'
  | 'listCompleted'

export interface AppNotification {
  id: EntityId
  type: NotificationType
  title: string
  message: string
  createdAt: ISODateString
  isRead: boolean
  listId: EntityId | null
  actorId: EntityId | null
}

export type NotificationMode = 'all' | 'important'

export interface NotificationSettings {
  mode: NotificationMode
  mutedListIds: EntityId[]
}

export interface FrequentProduct {
  id: EntityId
  sourceProductId: EntityId | null
  name: string
  unit: ProductUnit
  category: ProductCategory
  estimatedPrice: number
  timesAdded: number
  lastAddedAt: ISODateString
}
