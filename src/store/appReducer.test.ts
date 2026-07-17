import { describe, expect, it } from 'vitest'
import { loadAppState, saveAppState, type StorageAdapter } from '../data/storage'
import { MOCK_IDS } from '../data/mockData'
import { appActions, appReducer, createInitialAppState } from './appReducer'
import { selectOverallSummary } from './selectors'

function reduce(action: ReturnType<(typeof appActions)[keyof typeof appActions]>) {
  return appReducer(createInitialAppState(), action)
}

describe('OneCart app reducer', () => {
  it('seeds the requested stores, products and mixed purchase states', () => {
    const state = createInitialAppState()

    expect(state.stores.map((store) => store.name)).toEqual([
      'АТБ',
      'Сільпо',
      'Auchan',
      'NOVUS',
      'VARUS',
      'Фора',
    ])
    expect(state.products).toHaveLength(7)
    expect(state.products.some((product) => product.storeId === null)).toBe(true)
    expect(state.products.some((product) => product.isPurchased)).toBe(true)
    expect(state.products.find((product) => product.id === 'product-bananas')).toMatchObject({
      imageSourceLabel: 'АТБ',
    })
    expect(state.stores.find((store) => store.id === MOCK_IDS.stores.atb)).toMatchObject({
      city: 'Київ',
      latitude: expect.any(Number),
      longitude: expect.any(Number),
    })
  })

  it('marks a product purchased and updates the derived summary', () => {
    const before = createInitialAppState()
    const after = appReducer(
      before,
      appActions.toggleProductPurchased('product-bananas', '2026-07-16T10:00:00.000Z'),
    )

    expect(after.products.find((product) => product.id === 'product-bananas')).toMatchObject({
      isPurchased: true,
      purchasedAt: '2026-07-16T10:00:00.000Z',
    })
    expect(selectOverallSummary(after).purchasedCount).toBe(
      selectOverallSummary(before).purchasedCount + 1,
    )
  })

  it('moves a product between stores atomically and undoes the move', () => {
    const before = createInitialAppState()
    const moved = appReducer(
      before,
      appActions.moveProduct(
        'product-bread',
        MOCK_IDS.stores.atb,
        MOCK_IDS.lists.atb,
        '2026-07-16T10:01:00.000Z',
      ),
    )
    const movedProduct = moved.products.find((product) => product.id === 'product-bread')

    expect(movedProduct).toMatchObject({
      storeId: MOCK_IDS.stores.atb,
      listId: MOCK_IDS.lists.atb,
    })

    const restored = appReducer(
      moved,
      appActions.undoMoveProduct('2026-07-16T10:02:00.000Z'),
    )
    expect(restored.products.find((product) => product.id === 'product-bread')).toMatchObject({
      storeId: null,
      listId: MOCK_IDS.lists.general,
    })
  })

  it('restores a deleted product at its previous position', () => {
    const before = createInitialAppState()
    const originalIndex = before.products.findIndex((product) => product.id === 'product-eggs')
    const deleted = appReducer(
      before,
      appActions.deleteProduct('product-eggs', '2026-07-16T10:03:00.000Z'),
    )
    expect(deleted.products.some((product) => product.id === 'product-eggs')).toBe(false)

    const restored = appReducer(
      deleted,
      appActions.undoDeleteProduct('2026-07-16T10:04:00.000Z'),
    )
    expect(restored.products[originalIndex]?.id).toBe('product-eggs')
  })

  it('completes a list into an immutable history snapshot', () => {
    const before = createInitialAppState()
    const after = appReducer(
      before,
      appActions.completeList(MOCK_IDS.lists.atb, '2026-07-16T10:05:00.000Z'),
    )
    const completed = after.shoppingLists.find((list) => list.id === MOCK_IDS.lists.atb)
    const createdHistory = after.purchaseHistory.find(
      (entry) => entry.date === '2026-07-16T10:05:00.000Z',
    )

    expect(completed?.status).toBe('completed')
    expect(createdHistory?.products).toHaveLength(2)
    expect(createdHistory?.products.every((product) => product.isPurchased)).toBe(true)
    expect(createdHistory?.total).toBe(150)
  })

  it('repeats history into the existing active store list', () => {
    const before = createInitialAppState()
    const historyId = 'history-atb-2026-07-12'
    const repeatedListId = 'list-repeat-regression'
    const repeatedAt = '2026-07-16T10:06:00.000Z'
    const after = appReducer(
      before,
      appActions.repeatHistory(historyId, {
        newListId: repeatedListId,
        repeatedAt,
      }),
    )

    const activeStoreLists = after.shoppingLists.filter(
      (list) => list.status === 'active' && list.storeId === MOCK_IDS.stores.atb,
    )
    const repeatedProducts = after.products.filter((product) =>
      product.id.startsWith(`${repeatedListId}-product-`),
    )

    expect(activeStoreLists).toHaveLength(1)
    expect(activeStoreLists[0]?.id).toBe(MOCK_IDS.lists.atb)
    expect(activeStoreLists[0]?.updatedAt).toBe(repeatedAt)
    expect(repeatedProducts).toHaveLength(3)
    expect(
      repeatedProducts.every(
        (product) =>
          product.listId === MOCK_IDS.lists.atb &&
          product.storeId === MOCK_IDS.stores.atb &&
          !product.isPurchased,
      ),
    ).toBe(true)
    expect(after.shoppingLists.some((list) => list.id === repeatedListId)).toBe(false)
  })

  it('keeps only one active list for each store destination', () => {
    const before = createInitialAppState()
    const after = appReducer(
      before,
      appActions.createList({
        id: 'duplicate-atb-list',
        title: 'Ещё один список АТБ',
        storeId: MOCK_IDS.stores.atb,
        ownerId: before.currentUserId,
      }),
    )

    expect(after).toBe(before)
    expect(
      after.shoppingLists.filter(
        (list) => list.status === 'active' && list.storeId === MOCK_IDS.stores.atb,
      ),
    ).toHaveLength(1)
  })

  it('persists invited members, list membership and role changes', () => {
    const before = createInitialAppState()
    const userAction = appActions.addUser({
      id: 'invite-olena',
      name: 'Олена',
      email: 'olena@onecart.local',
      role: 'viewer',
    })
    const withUser = appReducer(before, userAction)
    const withMembership = appReducer(
      withUser,
      appActions.setListMember(MOCK_IDS.lists.atb, 'invite-olena', true, '2026-07-16T10:07:00.000Z'),
    )
    const withRole = appReducer(
      withMembership,
      appActions.setUserRole('invite-olena', 'editor'),
    )

    expect(withRole.users.find((user) => user.id === 'invite-olena')?.role).toBe('editor')
    expect(
      withRole.shoppingLists.find((list) => list.id === MOCK_IDS.lists.atb)?.members,
    ).toContain('invite-olena')
  })
})

describe('OneCart local persistence', () => {
  it('restores saved mutations and falls back from malformed data', () => {
    const values = new Map<string, string>()
    const storage: StorageAdapter = {
      getItem: (key) => values.get(key) ?? null,
      setItem: (key, value) => values.set(key, value),
      removeItem: (key) => values.delete(key),
    }
    const fallback = createInitialAppState()
    const changed = reduce(appActions.setLocale('uk'))

    expect(saveAppState(changed, storage)).toBe(true)
    expect(loadAppState(fallback, storage).settings.locale).toBe('uk')

    values.set('onecart.app-state', '{broken-json')
    expect(loadAppState(fallback, storage).settings.locale).toBe('ru')
  })
})
