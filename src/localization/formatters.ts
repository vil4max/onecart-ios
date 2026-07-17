import { LOCALE_TAGS, type AppLocale } from './locale'

export type DateInput = Date | string | number

export interface MoneyFormatOptions {
  readonly currency?: 'UAH'
  readonly minimumFractionDigits?: number
  readonly maximumFractionDigits?: number
  readonly fallback?: string
}

export interface EstimatedMoneyFormatOptions extends MoneyFormatOptions {
  readonly marker?: string
}

export interface DateFormatOptions extends Intl.DateTimeFormatOptions {
  readonly fallback?: string
}

const DEFAULT_FALLBACK = '—'

const toValidDate = (value: DateInput): Date | null => {
  const date = value instanceof Date ? value : new Date(value)
  return Number.isNaN(date.getTime()) ? null : date
}

export const formatNumber = (
  value: number,
  locale: AppLocale,
  options?: Intl.NumberFormatOptions,
): string => {
  if (!Number.isFinite(value)) return DEFAULT_FALLBACK
  return new Intl.NumberFormat(LOCALE_TAGS[locale], options).format(value)
}

export const formatMoney = (
  amount: number,
  locale: AppLocale,
  options: MoneyFormatOptions = {},
): string => {
  if (!Number.isFinite(amount)) return options.fallback ?? DEFAULT_FALLBACK

  return new Intl.NumberFormat(LOCALE_TAGS[locale], {
    style: 'currency',
    currency: options.currency ?? 'UAH',
    currencyDisplay: 'narrowSymbol',
    minimumFractionDigits: options.minimumFractionDigits ?? 0,
    maximumFractionDigits: options.maximumFractionDigits ?? 2,
  }).format(amount)
}

export const formatEstimatedMoney = (
  amount: number,
  locale: AppLocale,
  options: EstimatedMoneyFormatOptions = {},
): string => {
  const formatted = formatMoney(amount, locale, options)
  const fallback = options.fallback ?? DEFAULT_FALLBACK
  return formatted === fallback ? formatted : `${options.marker ?? '≈'} ${formatted}`
}

export const formatDate = (
  value: DateInput,
  locale: AppLocale,
  options: DateFormatOptions = {},
): string => {
  const date = toValidDate(value)
  if (!date) return options.fallback ?? DEFAULT_FALLBACK

  const { fallback: _fallback, ...dateTimeOptions } = options
  return new Intl.DateTimeFormat(LOCALE_TAGS[locale], {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    ...dateTimeOptions,
  }).format(date)
}

export const formatShortDate = (
  value: DateInput,
  locale: AppLocale,
  fallback = DEFAULT_FALLBACK,
): string =>
  formatDate(value, locale, {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    fallback,
  })

export const formatDateTime = (
  value: DateInput,
  locale: AppLocale,
  options: DateFormatOptions = {},
): string =>
  formatDate(value, locale, {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    ...options,
  })
