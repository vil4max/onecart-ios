import type { Product, ProductCategory, ProductUnit } from '../../domain/models'
import {
  formatNumber,
  type AppLocale,
  type TranslationKey,
  type Translator,
} from '../../localization'

export const UNIT_TRANSLATION_KEYS: Record<ProductUnit, TranslationKey> = {
  piece: 'units.piece',
  kg: 'units.kg',
  g: 'units.g',
  l: 'units.l',
  ml: 'units.ml',
  pack: 'units.pack',
}

export const CATEGORY_TRANSLATION_KEYS: Record<ProductCategory, TranslationKey> = {
  produce: 'categories.produce',
  dairy: 'categories.dairy',
  meat: 'categories.meat',
  drinks: 'categories.drinks',
  household: 'categories.household',
  other: 'categories.other',
}

export const PRODUCT_SUGGESTIONS: Readonly<Record<AppLocale, readonly string[]>> = {
  ru: ['Молоко', 'Молоко 2,5%', 'Хлеб', 'Яйца', 'Сыр'],
  uk: ['Молоко', 'Молоко 2,5%', 'Хліб', 'Яйця', 'Сир'],
}

export function formatProductQuantity(
  product: Pick<Product, 'quantity' | 'unit'>,
  locale: AppLocale,
  t: Translator,
): string {
  return `${formatNumber(product.quantity, locale, { maximumFractionDigits: 3 })} ${t(
    UNIT_TRANSLATION_KEYS[product.unit],
  )}`
}

