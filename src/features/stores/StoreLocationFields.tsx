import { useId, useState, type RefObject } from 'react'
import { LocateFixed, MapPin } from 'lucide-react'
import type { Translator } from '../../localization'
import { SecondaryButton } from '../../ui'
import { formatCoordinates, STORE_CITY_SUGGESTIONS } from './storeLocation'

export interface StoreLocationFieldsProps {
  city: string
  address: string
  latitude: number | null
  longitude: number | null
  onCityChange: (city: string) => void
  onAddressChange: (address: string) => void
  onCoordinatesChange: (latitude: number | null, longitude: number | null) => void
  t: Translator
  addressInputRef?: RefObject<HTMLInputElement | null>
}

export function StoreLocationFields({
  address,
  addressInputRef,
  city,
  latitude,
  longitude,
  onAddressChange,
  onCityChange,
  onCoordinatesChange,
  t,
}: StoreLocationFieldsProps) {
  const cityListId = useId()
  const [isLocating, setIsLocating] = useState(false)
  const [locationError, setLocationError] = useState<string | null>(null)
  const coordinates = formatCoordinates(latitude, longitude)

  const useCurrentLocation = () => {
    if (typeof navigator === 'undefined' || !navigator.geolocation) {
      setLocationError(t('storeForm.locationUnsupported'))
      return
    }

    setIsLocating(true)
    setLocationError(null)
    navigator.geolocation.getCurrentPosition(
      (position) => {
        onCoordinatesChange(position.coords.latitude, position.coords.longitude)
        setIsLocating(false)
      },
      () => {
        setLocationError(t('storeForm.locationDenied'))
        setIsLocating(false)
      },
      {
        enableHighAccuracy: false,
        maximumAge: 300_000,
        timeout: 10_000,
      },
    )
  }

  return (
    <div className="store-location-fields">
      <label className="field">
        <span className="field__label">{t('storeForm.city')}</span>
        <input
          autoComplete="address-level2"
          list={cityListId}
          maxLength={80}
          onChange={(event) => onCityChange(event.currentTarget.value)}
          placeholder={t('storeForm.cityPlaceholder')}
          value={city}
        />
        <datalist id={cityListId}>
          {STORE_CITY_SUGGESTIONS.map((suggestion) => (
            <option key={suggestion} value={suggestion} />
          ))}
        </datalist>
      </label>

      <label className="field">
        <span className="field__label">{t('storeForm.address')}</span>
        <input
          autoComplete="street-address"
          maxLength={160}
          onChange={(event) => onAddressChange(event.currentTarget.value)}
          placeholder={t('storeForm.addressPlaceholder')}
          ref={addressInputRef}
          value={address}
        />
      </label>

      <div className="store-location-fields__geo">
        <SecondaryButton
          disabled={isLocating}
          leadingIcon={LocateFixed}
          onClick={useCurrentLocation}
        >
          {isLocating ? t('storeForm.locating') : t('storeForm.useCurrentLocation')}
        </SecondaryButton>
        {coordinates ? (
          <span className="store-location-fields__coordinates">
            <MapPin aria-hidden="true" size={16} />
            <span>
              {t('storeForm.coordinates')}: {coordinates}
            </span>
          </span>
        ) : null}
      </div>

      {locationError ? (
        <p className="field__error" role="alert">
          {locationError}
        </p>
      ) : coordinates ? (
        <p className="field__hint">{t('storeForm.locationReady')}</p>
      ) : null}
    </div>
  )
}
