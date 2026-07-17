import type { AppLocale } from './locale'

export const updateDocumentLanguage = (
  locale: AppLocale,
  root?: HTMLElement | null,
): void => {
  const documentRoot = root ?? (typeof document === 'undefined' ? null : document.documentElement)
  if (!documentRoot) return

  documentRoot.lang = locale
  documentRoot.dir = 'ltr'
}
