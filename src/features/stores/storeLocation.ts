import type { Store } from '../../domain/models'

export const STORE_CITY_SUGGESTIONS = [
  'Київ',
  'Львів',
  'Дніпро',
  'Одеса',
  'Харків',
  'Запоріжжя',
  'Вінниця',
  'Чернівці',
] as const

export function formatCoordinates(
  latitude: number | null | undefined,
  longitude: number | null | undefined,
): string | null {
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null
  return `${Number(latitude).toFixed(5)}, ${Number(longitude).toFixed(5)}`
}

export function formatStoreLocation(
  store: Pick<Store, 'city' | 'address' | 'latitude' | 'longitude'>,
): string | null {
  const city = store.city?.trim() ?? ''
  const address = store.address?.trim() ?? ''
  if (city && address) {
    return address.toLocaleLowerCase().startsWith(city.toLocaleLowerCase())
      ? address
      : `${city}, ${address}`
  }
  if (address) return address
  if (city) return city
  return formatCoordinates(store.latitude, store.longitude)
}
