import type { Dispatch } from 'react'
import type { Product, PurchaseHistory } from '../../domain/models'
import { appActions, type AppAction, type AppState } from '../../store/appReducer'

let localSequence = 0

function createScreenId(prefix: string): string {
  localSequence += 1
  return `${prefix}-${Date.now().toString(36)}-${localSequence}`
}

export function repeatHistoryEntry(
  state: AppState,
  dispatch: Dispatch<AppAction>,
  entry: PurchaseHistory,
  title: string,
): string {
  const newListId = createScreenId(`list-repeat-${entry.id}`)
  const destinationStoreId =
    entry.storeId && state.stores.some((store) => store.id === entry.storeId)
      ? entry.storeId
      : null
  const existingList = state.shoppingLists.find(
    (list) => list.status === 'active' && list.storeId === destinationStoreId,
  )
  dispatch(
    appActions.repeatHistory(entry.id, {
      newListId,
      repeatedAt: new Date().toISOString(),
      title,
    }),
  )
  return existingList?.id ?? newListId
}

export function addHistoryProductAgain(
  state: AppState,
  dispatch: Dispatch<AppAction>,
  product: Product,
  destinationTitle: string,
): string {
  const existingList = state.shoppingLists.find(
    (list) => list.status === 'active' && list.storeId === product.storeId,
  )
  const listId = existingList?.id ?? createScreenId('list-history-item')

  if (!existingList) {
    dispatch(
      appActions.createList({
        id: listId,
        title: destinationTitle,
        storeId: product.storeId,
        ownerId: state.currentUserId,
        members: [state.currentUserId],
      }),
    )
  }

  dispatch(
    appActions.addProduct({
      name: product.name,
      quantity: product.quantity,
      unit: product.unit,
      category: product.category,
      estimatedPrice: product.estimatedPrice,
      note: product.note,
      storeId: product.storeId,
      listId,
      addedBy: state.currentUserId,
    }),
  )

  return listId
}

export function addFrequentProductToGeneralList(
  state: AppState,
  dispatch: Dispatch<AppAction>,
  frequentProductId: string,
  destinationTitle: string,
): string | null {
  const frequentProduct = state.frequentProducts.find((item) => item.id === frequentProductId)
  if (!frequentProduct) return null

  const existingList = state.shoppingLists.find(
    (list) => list.status === 'active' && list.storeId === null,
  )
  const listId = existingList?.id ?? createScreenId('list-general')

  if (!existingList) {
    dispatch(
      appActions.createList({
        id: listId,
        title: destinationTitle,
        storeId: null,
        ownerId: state.currentUserId,
        members: [state.currentUserId],
      }),
    )
  }

  dispatch(
    appActions.addProduct({
      name: frequentProduct.name,
      quantity: 1,
      unit: frequentProduct.unit,
      category: frequentProduct.category,
      estimatedPrice: frequentProduct.estimatedPrice,
      storeId: null,
      listId,
      addedBy: state.currentUserId,
    }),
  )
  dispatch(appActions.recordFrequentUse(frequentProduct.id))
  return listId
}
