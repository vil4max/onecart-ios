import { describe, expect, it } from 'vitest'
import { MOCK_IDS } from '../../data/mockData'
import { appReducer, createInitialAppState, type AppAction } from '../../store/appReducer'
import { repeatHistoryEntry } from './historyActions'

describe('history repeat navigation', () => {
  it('returns the existing active store list used by the reducer', () => {
    const before = createInitialAppState()
    const history = before.purchaseHistory.find((entry) => entry.storeId === MOCK_IDS.stores.atb)
    const actions: AppAction[] = []

    expect(history).toBeDefined()
    if (!history) return

    const destinationListId = repeatHistoryEntry(
      before,
      (action) => actions.push(action),
      history,
      'Repeat ATB',
    )
    const after = actions.reduce(appReducer, before)

    expect(destinationListId).toBe(MOCK_IDS.lists.atb)
    expect(
      after.shoppingLists.filter(
        (list) => list.status === 'active' && list.storeId === MOCK_IDS.stores.atb,
      ),
    ).toHaveLength(1)
  })
})
