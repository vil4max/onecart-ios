import type { ThemePreference } from '../domain/models'

export type ResolvedTheme = Exclude<ThemePreference, 'system'>

export const DARK_THEME_MEDIA_QUERY = '(prefers-color-scheme: dark)'
export const THEME_COLORS: Readonly<Record<ResolvedTheme, string>> = {
  light: '#f5f6f3',
  dark: '#111814',
}

export interface ThemeEnvironment {
  document?: Document | null
  matchMedia?: ((query: string) => MediaQueryList) | null
}

function browserDocument(): Document | null {
  return typeof document === 'undefined' ? null : document
}

function browserMatchMedia(): ((query: string) => MediaQueryList) | null {
  return typeof window === 'undefined' || typeof window.matchMedia !== 'function'
    ? null
    : (query) => window.matchMedia(query)
}

export function isThemePreference(value: unknown): value is ThemePreference {
  return value === 'light' || value === 'dark' || value === 'system'
}

export function resolveTheme(
  preference: ThemePreference,
  systemPrefersDark = false,
): ResolvedTheme {
  return preference === 'system' ? (systemPrefersDark ? 'dark' : 'light') : preference
}

export function applyResolvedTheme(
  theme: ResolvedTheme,
  targetDocument: Document | null = browserDocument(),
): void {
  if (!targetDocument) return

  targetDocument.documentElement.dataset.theme = theme
  targetDocument.documentElement.style.colorScheme = theme
  targetDocument
    .querySelector<HTMLMetaElement>('meta[name="theme-color"]')
    ?.setAttribute('content', THEME_COLORS[theme])
}

export function applyThemePreference(
  preference: ThemePreference,
  environment: ThemeEnvironment = {},
): ResolvedTheme {
  const matchMedia = environment.matchMedia ?? browserMatchMedia()
  const systemPrefersDark =
    preference === 'system' ? (matchMedia?.(DARK_THEME_MEDIA_QUERY).matches ?? false) : false
  const resolvedTheme = resolveTheme(preference, systemPrefersDark)
  applyResolvedTheme(resolvedTheme, environment.document ?? browserDocument())
  return resolvedTheme
}

export function watchThemePreference(
  preference: ThemePreference,
  environment: ThemeEnvironment = {},
): () => void {
  const matchMedia = environment.matchMedia ?? browserMatchMedia()
  const targetDocument = environment.document ?? browserDocument()

  if (preference !== 'system' || !matchMedia) {
    applyResolvedTheme(resolveTheme(preference), targetDocument)
    return () => undefined
  }

  const mediaQuery = matchMedia(DARK_THEME_MEDIA_QUERY)
  const updateFromSystem = (event?: MediaQueryListEvent) => {
    applyResolvedTheme(resolveTheme('system', event?.matches ?? mediaQuery.matches), targetDocument)
  }

  updateFromSystem()
  mediaQuery.addEventListener?.('change', updateFromSystem)

  return () => mediaQuery.removeEventListener?.('change', updateFromSystem)
}
