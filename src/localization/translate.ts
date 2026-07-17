import { ru, type TranslationKey } from './ru'
import { uk } from './uk'
import type { AppLocale } from './locale'

export type InterpolationValue = string | number
export type InterpolationValues = Readonly<Record<string, InterpolationValue>>
export type Translator = (key: TranslationKey, values?: InterpolationValues) => string

const dictionaries: Readonly<
  Record<AppLocale, Readonly<Record<TranslationKey, string>>>
> = { ru, uk }

const INTERPOLATION_PATTERN = /\{\{\s*([\w.-]+)\s*\}\}/g

export const getDictionary = (
  locale: AppLocale,
): Readonly<Record<TranslationKey, string>> => dictionaries[locale]

export const interpolate = (
  template: string,
  values: InterpolationValues = {},
): string =>
  template.replace(INTERPOLATION_PATTERN, (placeholder, name: string) =>
    Object.prototype.hasOwnProperty.call(values, name) ? String(values[name]) : placeholder,
  )

export const translate = (
  locale: AppLocale,
  key: TranslationKey,
  values?: InterpolationValues,
): string => interpolate(dictionaries[locale][key], values)

export const createTranslator = (locale: AppLocale): Translator =>
  (key, values) => translate(locale, key, values)
