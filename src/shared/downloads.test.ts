import { describe, expect, it } from 'vitest'
import { createInitialAppState } from '../store/appReducer'
import { createListsCsv } from './downloads'

describe('OneCart list export', () => {
  it('exports list, store and product data as a UTF-8 CSV', () => {
    const csv = createListsCsv(createInitialAppState())

    expect(csv.startsWith('\uFEFF')).toBe(true)
    expect(csv).toContain('"list","store","product"')
    expect(csv).toContain('"Покупки в АТБ","АТБ","Бананы"')
    expect(csv.split('\n')).toHaveLength(8)
  })

  it('neutralizes spreadsheet formulas in user-authored cells', () => {
    const state = createInitialAppState()
    state.products[0] = { ...state.products[0], name: '=SUM(1,1)', note: '@command' }

    const csv = createListsCsv(state)

    expect(csv).toContain('"\'=SUM(1,1)"')
    expect(csv).toContain('"\'@command"')
  })
})
