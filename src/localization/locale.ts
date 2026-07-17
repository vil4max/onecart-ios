export const SUPPORTED_LOCALES = ['ru', 'uk'] as const

export type AppLocale = (typeof SUPPORTED_LOCALES)[number]

export const DEFAULT_LOCALE: AppLocale = 'uk'

export const LOCALE_TAGS: Readonly<Record<AppLocale, string>> = {
  ru: 'ru-UA',
  uk: 'uk-UA',
}

export const isAppLocale = (value: unknown): value is AppLocale =>
  typeof value === 'string' && SUPPORTED_LOCALES.includes(value as AppLocale)

export const normalizeLocale = (value: unknown): AppLocale | null => {
  if (typeof value !== 'string') return null

  const language = value.trim().toLowerCase().split(/[-_]/)[0]
  return isAppLocale(language) ? language : null
}

export const resolveLocale = (
  savedLocale?: unknown,
  browserLocales?: readonly string[],
): AppLocale => {
  const saved = normalizeLocale(savedLocale)
  if (saved) return saved

  const candidates =
    browserLocales ??
    (typeof navigator === 'undefined'
      ? []
      : navigator.languages.length > 0
        ? navigator.languages
        : [navigator.language])

  for (const candidate of candidates) {
    const locale = normalizeLocale(candidate)
    if (locale) return locale
  }

  return DEFAULT_LOCALE
}
