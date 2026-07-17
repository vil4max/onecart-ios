import { describe, expect, it } from 'vitest'
import {
  applyResolvedTheme,
  applyThemePreference,
  isThemePreference,
  resolveTheme,
  THEME_COLORS,
  watchThemePreference,
} from './theme'

function createFakeDocument() {
  let themeColor = ''
  const documentElement = {
    dataset: {} as Record<string, string>,
    style: { colorScheme: '' },
  }
  const targetDocument = {
    documentElement,
    querySelector: (selector: string) =>
      selector === 'meta[name="theme-color"]'
        ? {
            setAttribute: (name: string, value: string) => {
              if (name === 'content') themeColor = value
            },
          }
        : null,
  } as unknown as Document

  return {
    documentElement,
    targetDocument,
    themeColor: () => themeColor,
  }
}

describe('OneCart theme runtime', () => {
  it('recognizes all supported preferences and resolves the system value', () => {
    expect(['light', 'dark', 'system'].every(isThemePreference)).toBe(true)
    expect(isThemePreference('sepia')).toBe(false)
    expect(resolveTheme('system', false)).toBe('light')
    expect(resolveTheme('system', true)).toBe('dark')
    expect(resolveTheme('dark', false)).toBe('dark')
  })

  it('applies the resolved theme and matching browser chrome color', () => {
    const fakeDocument = createFakeDocument()

    applyResolvedTheme('dark', fakeDocument.targetDocument)

    expect(fakeDocument.documentElement.dataset.theme).toBe('dark')
    expect(fakeDocument.documentElement.style.colorScheme).toBe('dark')
    expect(fakeDocument.themeColor()).toBe(THEME_COLORS.dark)
  })

  it('uses the current device theme for a system preference', () => {
    const fakeDocument = createFakeDocument()
    const resolved = applyThemePreference('system', {
      document: fakeDocument.targetDocument,
      matchMedia: () => ({ matches: true }) as MediaQueryList,
    })

    expect(resolved).toBe('dark')
    expect(fakeDocument.documentElement.dataset.theme).toBe('dark')
  })

  it('updates live when the device theme changes and removes the listener', () => {
    const fakeDocument = createFakeDocument()
    let changeListener: ((event: MediaQueryListEvent) => void) | undefined
    let removedListener: ((event: MediaQueryListEvent) => void) | undefined
    const mediaQuery = {
      matches: false,
      addEventListener: (
        _type: string,
        listener: (event: MediaQueryListEvent) => void,
      ) => {
        changeListener = listener
      },
      removeEventListener: (
        _type: string,
        listener: (event: MediaQueryListEvent) => void,
      ) => {
        removedListener = listener
      },
    } as unknown as MediaQueryList

    const stopWatching = watchThemePreference('system', {
      document: fakeDocument.targetDocument,
      matchMedia: () => mediaQuery,
    })

    expect(fakeDocument.documentElement.dataset.theme).toBe('light')
    changeListener?.({ matches: true } as MediaQueryListEvent)
    expect(fakeDocument.documentElement.dataset.theme).toBe('dark')

    stopWatching()
    expect(removedListener).toBe(changeListener)
  })
})
