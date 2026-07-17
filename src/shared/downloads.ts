import { serializeAppState } from '../data/storage'
import type { AppState } from '../store/appReducer'

function dateStamp(): string {
  return new Date().toISOString().slice(0, 10)
}

function downloadText(filename: string, text: string, type: string): boolean {
  if (typeof document === 'undefined' || typeof URL === 'undefined') return false
  const blob = new Blob([text], { type })
  const url = URL.createObjectURL(blob)
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = filename
  anchor.hidden = true
  document.body.append(anchor)
  anchor.click()
  anchor.remove()
  window.setTimeout(() => URL.revokeObjectURL(url), 0)
  return true
}

function csvCell(value: string | number | null): string {
  const text = value === null ? '' : String(value)
  const safeText = /^[\t\r\n ]*[=+@-]/.test(text) ? `'${text}` : text
  return `"${safeText.replaceAll('"', '""')}"`
}

export function downloadAppBackup(state: AppState): boolean {
  return downloadText(
    `onecart-backup-${dateStamp()}.json`,
    serializeAppState(state),
    'application/json;charset=utf-8',
  )
}

export function createListsCsv(state: AppState): string {
  const listsById = new Map(state.shoppingLists.map((list) => [list.id, list]))
  const storesById = new Map(state.stores.map((store) => [store.id, store]))
  const rows = state.products.map((product) => {
    const list = listsById.get(product.listId)
    const store = product.storeId ? storesById.get(product.storeId) : null
    return [
      list?.title ?? '',
      store?.name ?? '',
      product.name,
      product.quantity,
      product.unit,
      product.category,
      product.estimatedPrice,
      product.note,
      product.isPurchased ? 'true' : 'false',
    ]
      .map(csvCell)
      .join(',')
  })
  const header = [
    'list',
    'store',
    'product',
    'quantity',
    'unit',
    'category',
    'estimatedPriceUAH',
    'note',
    'purchased',
  ]
    .map(csvCell)
    .join(',')
  return `\uFEFF${[header, ...rows].join('\n')}`
}

export function downloadListsCsv(state: AppState): boolean {
  return downloadText(
    `onecart-lists-${dateStamp()}.csv`,
    createListsCsv(state),
    'text/csv;charset=utf-8',
  )
}
