import { describe, expect, it } from 'vitest'
import { formatCoordinates, formatStoreLocation } from './storeLocation'

describe('store location formatting', () => {
  it('combines city and street address without duplicating the city', () => {
    expect(
      formatStoreLocation({
        city: 'Київ',
        address: 'вул. Хрещатик, 1',
        latitude: null,
        longitude: null,
      }),
    ).toBe('Київ, вул. Хрещатик, 1')

    expect(
      formatStoreLocation({
        city: 'Київ',
        address: 'Київ, вул. Хрещатик, 1',
        latitude: null,
        longitude: null,
      }),
    ).toBe('Київ, вул. Хрещатик, 1')
  })

  it('uses coordinates when no readable address is available', () => {
    expect(formatCoordinates(50.4501, 30.5234)).toBe('50.45010, 30.52340')
    expect(
      formatStoreLocation({
        city: null,
        address: null,
        latitude: 50.4501,
        longitude: 30.5234,
      }),
    ).toBe('50.45010, 30.52340')
  })
})
