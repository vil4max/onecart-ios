import { describe, expect, it } from 'vitest'
import { appActions, appReducer, createInitialAppState } from '../store/appReducer'
import {
  loadAppState,
  saveAppState,
  serializeAppState,
  type StorageAdapter,
} from './storage'

function createMemoryStorage(): { storage: StorageAdapter; values: Map<string, string> } {
  const values = new Map<string, string>()
  return {
    values,
    storage: {
      getItem: (key) => values.get(key) ?? null,
      setItem: (key, value) => values.set(key, value),
      removeItem: (key) => values.delete(key),
    },
  }
}

describe('OneCart theme persistence', () => {
  it.each(['light', 'dark', 'system'] as const)('restores the %s preference', (theme) => {
    const { storage } = createMemoryStorage()
    const fallback = createInitialAppState()
    const changed = appReducer(fallback, appActions.updateSettings({ theme }))

    expect(saveAppState(changed, storage)).toBe(true)
    expect(loadAppState(fallback, storage).settings.theme).toBe(theme)
  })

  it('falls back safely when a stored theme is unsupported', () => {
    const { storage, values } = createMemoryStorage()
    const fallback = createInitialAppState()
    const envelope = JSON.parse(serializeAppState(fallback)) as {
      state: { settings: { theme: string } }
    }
    envelope.state.settings.theme = 'sepia'
    values.set('onecart.app-state', JSON.stringify(envelope))

    expect(loadAppState(fallback, storage).settings.theme).toBe('light')
  })
})
