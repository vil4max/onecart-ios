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
import { resolveProductMedia } from './productMedia'

export const MOCK_IDS = {
  users: {
    marina: 'user-marina',
    alex: 'user-alex',
  },
  stores: {
    atb: 'store-atb',
    silpo: 'store-silpo',
    auchan: 'store-auchan',
    novus: 'store-novus',
    varus: 'store-varus',
    fora: 'store-fora',
  },
  lists: {
    general: 'list-general',
    atb: 'list-atb',
    silpo: 'list-silpo',
    auchan: 'list-auchan',
    novus: 'list-novus',
    varus: 'list-varus',
    fora: 'list-fora',
  },
} as const

export interface MockStateData {
  users: User[]
  currentUserId: string
  stores: Store[]
  shoppingLists: ShoppingList[]
  products: Product[]
  purchaseHistory: PurchaseHistory[]
  notifications: AppNotification[]
  settings: AppSettings
  notificationSettings: NotificationSettings
  frequentProducts: FrequentProduct[]
}

function withProductMedia(product: Product): Product {
  const media = resolveProductMedia(product.name, product.storeId ?? '')
  return {
    ...product,
    imageUrl: media?.imageUrl ?? null,
    imageSourceUrl: media?.sourceUrl ?? null,
    imageSourceLabel: media?.sourceLabel ?? null,
  }
}

export function createMockData(): MockStateData {
  const users: User[] = [
    {
      id: MOCK_IDS.users.marina,
      name: 'Марина',
      email: 'marina@onecart.local',
      avatar: null,
      role: 'owner',
    },
    {
      id: MOCK_IDS.users.alex,
      name: 'Алекс',
      email: 'alex@onecart.local',
      avatar: null,
      role: 'editor',
    },
  ]

  const stores: Store[] = [
    {
      id: MOCK_IDS.stores.atb,
      name: 'АТБ',
      icon: 'АТБ',
      color: '#124C96',
      city: 'Київ',
      address: 'вул. Велика Васильківська, 72',
      latitude: 50.43868,
      longitude: 30.51629,
      externalAppUrl: 'https://www.atbmarket.com/',
      isPinned: true,
    },
    {
      id: MOCK_IDS.stores.silpo,
      name: 'Сільпо',
      icon: 'С',
      color: '#F58220',
      city: 'Київ',
      address: 'вул. Антоновича, 176',
      latitude: 50.41228,
      longitude: 30.52163,
      externalAppUrl: 'https://silpo.ua/',
      isPinned: true,
    },
    {
      id: MOCK_IDS.stores.auchan,
      name: 'Auchan',
      icon: 'A',
      color: '#D6242F',
      city: 'Київ',
      address: 'просп. Степана Бандери, 15-А',
      latitude: 50.48695,
      longitude: 30.48802,
      externalAppUrl: 'https://auchan.ua/',
      isPinned: false,
    },
    {
      id: MOCK_IDS.stores.novus,
      name: 'NOVUS',
      icon: 'N',
      color: '#198348',
      city: 'Київ',
      address: 'просп. Європейського Союзу, 47',
      latitude: 50.50363,
      longitude: 30.43259,
      externalAppUrl: 'https://novus.zakaz.ua/',
      isPinned: false,
    },
    {
      id: MOCK_IDS.stores.varus,
      name: 'VARUS',
      icon: 'V',
      color: '#5B2A86',
      city: 'Дніпро',
      address: null,
      latitude: null,
      longitude: null,
      externalAppUrl: 'https://varus.ua/',
      isPinned: false,
    },
    {
      id: MOCK_IDS.stores.fora,
      name: 'Фора',
      icon: 'Ф',
      color: '#16834B',
      city: 'Київ',
      address: null,
      latitude: null,
      longitude: null,
      externalAppUrl: 'https://fora.ua/',
      isPinned: false,
    },
  ]

  const listCreatedAt = '2026-07-14T08:00:00.000Z'
  const listUpdatedAt = '2026-07-16T08:40:00.000Z'
  const sharedMembers = [MOCK_IDS.users.marina, MOCK_IDS.users.alex]

  const shoppingLists: ShoppingList[] = [
    {
      id: MOCK_IDS.lists.general,
      title: 'Общий список',
      storeId: null,
      ownerId: MOCK_IDS.users.marina,
      members: [...sharedMembers],
      createdAt: listCreatedAt,
      updatedAt: listUpdatedAt,
      status: 'active',
    },
    {
      id: MOCK_IDS.lists.atb,
      title: 'Покупки в АТБ',
      storeId: MOCK_IDS.stores.atb,
      ownerId: MOCK_IDS.users.marina,
      members: [...sharedMembers],
      createdAt: listCreatedAt,
      updatedAt: listUpdatedAt,
      status: 'active',
    },
    {
      id: MOCK_IDS.lists.silpo,
      title: 'Покупки в Сільпо',
      storeId: MOCK_IDS.stores.silpo,
      ownerId: MOCK_IDS.users.marina,
      members: [...sharedMembers],
      createdAt: listCreatedAt,
      updatedAt: listUpdatedAt,
      status: 'active',
    },
    {
      id: MOCK_IDS.lists.auchan,
      title: 'Покупки в Auchan',
      storeId: MOCK_IDS.stores.auchan,
      ownerId: MOCK_IDS.users.marina,
      members: [...sharedMembers],
      createdAt: listCreatedAt,
      updatedAt: listUpdatedAt,
      status: 'active',
    },
    {
      id: MOCK_IDS.lists.novus,
      title: 'Покупки в NOVUS',
      storeId: MOCK_IDS.stores.novus,
      ownerId: MOCK_IDS.users.marina,
      members: [...sharedMembers],
      createdAt: listCreatedAt,
      updatedAt: listUpdatedAt,
      status: 'active',
    },
    {
      id: MOCK_IDS.lists.varus,
      title: 'Покупки в VARUS',
      storeId: MOCK_IDS.stores.varus,
      ownerId: MOCK_IDS.users.marina,
      members: [...sharedMembers],
      createdAt: listCreatedAt,
      updatedAt: listUpdatedAt,
      status: 'active',
    },
    {
      id: MOCK_IDS.lists.fora,
      title: 'Покупки в Фора',
      storeId: MOCK_IDS.stores.fora,
      ownerId: MOCK_IDS.users.marina,
      members: [...sharedMembers],
      createdAt: listCreatedAt,
      updatedAt: listUpdatedAt,
      status: 'active',
    },
  ]

  const products: Product[] = ([
    {
      id: 'product-bananas',
      name: 'Бананы',
      quantity: 1,
      unit: 'kg',
      category: 'produce',
      estimatedPrice: 72,
      note: 'Спелые, без тёмных пятен',
      storeId: MOCK_IDS.stores.atb,
      listId: MOCK_IDS.lists.atb,
      addedBy: MOCK_IDS.users.marina,
      isPurchased: false,
      createdAt: '2026-07-16T07:55:00.000Z',
      purchasedAt: null,
    },
    {
      id: 'product-milk',
      name: 'Молоко 2,5%',
      quantity: 2,
      unit: 'l',
      category: 'dairy',
      estimatedPrice: 104,
      note: '',
      storeId: MOCK_IDS.stores.silpo,
      listId: MOCK_IDS.lists.silpo,
      addedBy: MOCK_IDS.users.alex,
      isPurchased: true,
      createdAt: '2026-07-15T18:20:00.000Z',
      purchasedAt: '2026-07-16T08:35:00.000Z',
    },
    {
      id: 'product-bread',
      name: 'Хлеб',
      quantity: 1,
      unit: 'piece',
      category: 'other',
      estimatedPrice: 38,
      note: 'Цельнозерновой',
      storeId: null,
      listId: MOCK_IDS.lists.general,
      addedBy: MOCK_IDS.users.marina,
      isPurchased: false,
      createdAt: '2026-07-16T08:02:00.000Z',
      purchasedAt: null,
    },
    {
      id: 'product-eggs',
      name: 'Яйца',
      quantity: 10,
      unit: 'piece',
      category: 'dairy',
      estimatedPrice: 78,
      note: 'Категория C1',
      storeId: MOCK_IDS.stores.atb,
      listId: MOCK_IDS.lists.atb,
      addedBy: MOCK_IDS.users.alex,
      isPurchased: false,
      createdAt: '2026-07-16T08:08:00.000Z',
      purchasedAt: null,
    },
    {
      id: 'product-cheese',
      name: 'Сыр',
      quantity: 0.3,
      unit: 'kg',
      category: 'dairy',
      estimatedPrice: 126,
      note: '',
      storeId: MOCK_IDS.stores.silpo,
      listId: MOCK_IDS.lists.silpo,
      addedBy: MOCK_IDS.users.marina,
      isPurchased: false,
      createdAt: '2026-07-16T08:14:00.000Z',
      purchasedAt: null,
    },
    {
      id: 'product-water',
      name: 'Вода',
      quantity: 6,
      unit: 'l',
      category: 'drinks',
      estimatedPrice: 84,
      note: 'Без газа',
      storeId: MOCK_IDS.stores.auchan,
      listId: MOCK_IDS.lists.auchan,
      addedBy: MOCK_IDS.users.alex,
      isPurchased: true,
      createdAt: '2026-07-15T17:10:00.000Z',
      purchasedAt: '2026-07-16T08:22:00.000Z',
    },
    {
      id: 'product-napkins',
      name: 'Салфетки',
      quantity: 2,
      unit: 'pack',
      category: 'household',
      estimatedPrice: 64,
      note: '',
      storeId: null,
      listId: MOCK_IDS.lists.general,
      addedBy: MOCK_IDS.users.marina,
      isPurchased: false,
      createdAt: '2026-07-16T08:31:00.000Z',
      purchasedAt: null,
    },
  ] satisfies Product[]).map(withProductMedia)

  const historyProducts: Product[] = ([
    {
      id: 'history-product-apples',
      name: 'Яблоки',
      quantity: 1.5,
      unit: 'kg',
      category: 'produce',
      estimatedPrice: 96,
      note: '',
      storeId: MOCK_IDS.stores.atb,
      listId: 'history-list-atb-2026-07-12',
      addedBy: MOCK_IDS.users.marina,
      isPurchased: true,
      createdAt: '2026-07-12T09:00:00.000Z',
      purchasedAt: '2026-07-12T10:18:00.000Z',
    },
    {
      id: 'history-product-chicken',
      name: 'Куриное филе',
      quantity: 1,
      unit: 'kg',
      category: 'meat',
      estimatedPrice: 184,
      note: '',
      storeId: MOCK_IDS.stores.atb,
      listId: 'history-list-atb-2026-07-12',
      addedBy: MOCK_IDS.users.alex,
      isPurchased: true,
      createdAt: '2026-07-12T09:02:00.000Z',
      purchasedAt: '2026-07-12T10:20:00.000Z',
    },
    {
      id: 'history-product-buckwheat',
      name: 'Гречка',
      quantity: 1,
      unit: 'pack',
      category: 'other',
      estimatedPrice: 62,
      note: '',
      storeId: MOCK_IDS.stores.atb,
      listId: 'history-list-atb-2026-07-12',
      addedBy: MOCK_IDS.users.marina,
      isPurchased: true,
      createdAt: '2026-07-12T09:05:00.000Z',
      purchasedAt: '2026-07-12T10:22:00.000Z',
    },
  ] satisfies Product[]).map(withProductMedia)

  const purchaseHistory: PurchaseHistory[] = [
    {
      id: 'history-atb-2026-07-12',
      storeId: MOCK_IDS.stores.atb,
      products: historyProducts,
      total: 342,
      date: '2026-07-12T10:25:00.000Z',
      members: [...sharedMembers],
    },
  ]

  const notifications: AppNotification[] = [
    {
      id: 'notification-product-added',
      type: 'productAdded',
      title: 'Новый товар',
      message: 'Алекс добавил «Молоко 2,5%»',
      createdAt: '2026-07-16T08:40:00.000Z',
      isRead: false,
      listId: MOCK_IDS.lists.silpo,
      actorId: MOCK_IDS.users.alex,
    },
    {
      id: 'notification-product-purchased',
      type: 'productPurchased',
      title: 'Товар куплен',
      message: 'Вода отмечена как купленная',
      createdAt: '2026-07-16T08:22:00.000Z',
      isRead: false,
      listId: MOCK_IDS.lists.auchan,
      actorId: MOCK_IDS.users.alex,
    },
    {
      id: 'notification-list-changed',
      type: 'listChanged',
      title: 'Список изменён',
      message: 'Обновлён список покупок в АТБ',
      createdAt: '2026-07-15T19:10:00.000Z',
      isRead: true,
      listId: MOCK_IDS.lists.atb,
      actorId: MOCK_IDS.users.marina,
    },
    {
      id: 'notification-member-joined',
      type: 'memberJoined',
      title: 'Новый участник',
      message: 'Алекс присоединился к семейным спискам',
      createdAt: '2026-07-14T12:00:00.000Z',
      isRead: true,
      listId: MOCK_IDS.lists.general,
      actorId: MOCK_IDS.users.alex,
    },
    {
      id: 'notification-list-completed',
      type: 'listCompleted',
      title: 'Список завершён',
      message: 'Покупки в АТБ завершены',
      createdAt: '2026-07-12T10:25:00.000Z',
      isRead: true,
      listId: null,
      actorId: MOCK_IDS.users.marina,
    },
  ]

  const settings: AppSettings = {
    locale: 'ru',
    currency: 'UAH',
    theme: 'light',
    defaultUnit: 'piece',
    syncEnabled: true,
  }

  const notificationSettings: NotificationSettings = {
    mode: 'all',
    mutedListIds: [],
  }

  const frequentProducts: FrequentProduct[] = [
    ['frequent-milk', 'Молоко', 'l', 'dairy', 52, 14],
    ['frequent-bread', 'Хлеб', 'piece', 'other', 38, 12],
    ['frequent-eggs', 'Яйца', 'piece', 'dairy', 78, 10],
    ['frequent-water', 'Вода', 'l', 'drinks', 16, 9],
    ['frequent-cheese', 'Сыр', 'kg', 'dairy', 420, 7],
  ].map(([id, name, unit, category, estimatedPrice, timesAdded]) => ({
    id: String(id),
    sourceProductId: null,
    name: String(name),
    unit: unit as FrequentProduct['unit'],
    category: category as FrequentProduct['category'],
    estimatedPrice: Number(estimatedPrice),
    timesAdded: Number(timesAdded),
    lastAddedAt: '2026-07-15T18:00:00.000Z',
  }))

  return {
    users,
    currentUserId: MOCK_IDS.users.marina,
    stores,
    shoppingLists,
    products,
    purchaseHistory,
    notifications,
    settings,
    notificationSettings,
    frequentProducts,
  }
}
