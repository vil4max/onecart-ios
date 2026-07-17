import { useId, useMemo, useRef, useState, type CSSProperties, type FormEvent } from 'react'
import { ArrowLeft, Check, Settings2, Store as StoreIcon } from 'lucide-react'
import type { NewStoreInput } from '../../store/appReducer'
import {
  BottomSheet,
  EmptyState,
  IconButton,
  PrimaryButton,
  SearchField,
  SecondaryButton,
  SectionHeader,
  StoreMark,
} from '../../ui'
import { LOCALE_TAGS, createTranslator } from '../../localization'
import { appActions } from '../../store/appReducer'
import { useAppDispatch, useAppSelector } from '../../store/AppStateProvider'
import { selectCurrentUser, selectLocale, selectStores } from '../../store/selectors'
import { StoreLocationFields } from './StoreLocationFields'
import './Stores.css'

export interface StoreCatalogScreenProps {
  onBack: () => void
  onToast: (message: string) => void
}

interface CatalogStore {
  id: string
  name: string
  icon: string
  color: string
  externalAppUrl: string | null
}

const CATALOG_STORES: readonly CatalogStore[] = [
  {
    id: 'catalog-atb',
    name: 'АТБ',
    icon: 'АТБ',
    color: '#124C96',
    externalAppUrl: 'https://www.atbmarket.com/',
  },
  {
    id: 'catalog-silpo',
    name: 'Сільпо',
    icon: 'С',
    color: '#F58220',
    externalAppUrl: 'https://silpo.ua/',
  },
  {
    id: 'catalog-auchan',
    name: 'Auchan',
    icon: 'A',
    color: '#D6242F',
    externalAppUrl: 'https://auchan.ua/',
  },
  {
    id: 'catalog-novus',
    name: 'NOVUS',
    icon: 'N',
    color: '#198348',
    externalAppUrl: 'https://novus.zakaz.ua/',
  },
  {
    id: 'catalog-varus',
    name: 'VARUS',
    icon: 'V',
    color: '#5B2A86',
    externalAppUrl: 'https://varus.ua/',
  },
  {
    id: 'catalog-fora',
    name: 'Фора',
    icon: 'Ф',
    color: '#16834B',
    externalAppUrl: 'https://fora.ua/',
  },
  {
    id: 'catalog-metro',
    name: 'METRO',
    icon: 'M',
    color: '#FFCF00',
    externalAppUrl: 'https://www.metro.ua/',
  },
]

const CUSTOM_COLORS = ['#34785B', '#4F6D8A', '#9A6547', '#8B5D75', '#6D628A', '#58746D'] as const

export function StoreCatalogScreen({ onBack, onToast }: StoreCatalogScreenProps) {
  const dispatch = useAppDispatch()
  const locale = useAppSelector(selectLocale)
  const stores = useAppSelector(selectStores)
  const currentUser = useAppSelector(selectCurrentUser)
  const [search, setSearch] = useState('')
  const [customName, setCustomName] = useState('')
  const [customColor, setCustomColor] = useState<string>(CUSTOM_COLORS[0])
  const [customIcon, setCustomIcon] = useState('')
  const [customCity, setCustomCity] = useState('')
  const [customAddress, setCustomAddress] = useState('')
  const [customLatitude, setCustomLatitude] = useState<number | null>(null)
  const [customLongitude, setCustomLongitude] = useState<number | null>(null)
  const [formAttempted, setFormAttempted] = useState(false)
  const [selectedCatalogStore, setSelectedCatalogStore] = useState<CatalogStore | null>(null)
  const [standardCity, setStandardCity] = useState('')
  const [standardAddress, setStandardAddress] = useState('')
  const [standardLatitude, setStandardLatitude] = useState<number | null>(null)
  const [standardLongitude, setStandardLongitude] = useState<number | null>(null)
  const [standardExternalUrl, setStandardExternalUrl] = useState('')
  const [standardIncludeInGeneral, setStandardIncludeInGeneral] = useState(true)
  const [standardUrlInvalid, setStandardUrlInvalid] = useState(false)
  const standardSetupFormId = useId()
  const addressInputRef = useRef<HTMLInputElement>(null)
  const t = createTranslator(locale)
  const localeTag = LOCALE_TAGS[locale]
  const connectedNames = useMemo(
    () => new Set(stores.map((store) => store.name.trim().toLocaleLowerCase(localeTag))),
    [localeTag, stores],
  )
  const normalizedSearch = search.trim().toLocaleLowerCase(localeTag)
  const availableStores = useMemo(
    () =>
      CATALOG_STORES.filter(
        (store) =>
          !connectedNames.has(store.name.toLocaleLowerCase(localeTag)) &&
          (!normalizedSearch || store.name.toLocaleLowerCase(localeTag).includes(normalizedSearch)),
      ),
    [connectedNames, localeTag, normalizedSearch],
  )

  const addStoreAndList = (input: NewStoreInput, createStoreList = true): boolean => {
    if (!currentUser) {
      onToast(t('error.permissionDenied'))
      return false
    }

    const storeAction = appActions.addStore(input)
    if (storeAction.type !== 'store/add') return false

    dispatch(storeAction)
    if (createStoreList) {
      dispatch(
        appActions.createList({
          title: storeAction.payload.name,
          storeId: storeAction.payload.id,
          ownerId: currentUser.id,
          members: [currentUser.id],
        }),
      )
    }
    onToast(t('toast.storeAdded'))
    return true
  }

  const openCatalogStoreSetup = (store: CatalogStore) => {
    setSelectedCatalogStore(store)
    setStandardCity('')
    setStandardAddress('')
    setStandardLatitude(null)
    setStandardLongitude(null)
    setStandardExternalUrl(store.externalAppUrl ?? '')
    setStandardIncludeInGeneral(true)
    setStandardUrlInvalid(false)
  }

  const closeCatalogStoreSetup = () => {
    setSelectedCatalogStore(null)
    setStandardUrlInvalid(false)
  }

  const submitCatalogStore = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (!selectedCatalogStore) return

    const externalUrlInput = standardExternalUrl.trim()
    let externalAppUrl: string | null = null

    if (externalUrlInput) {
      try {
        const url = new URL(
          /^[a-z][a-z\d+.-]*:\/\//i.test(externalUrlInput)
            ? externalUrlInput
            : `https://${externalUrlInput}`,
        )
        if (url.protocol !== 'https:' && url.protocol !== 'http:') {
          setStandardUrlInvalid(true)
          return
        }
        externalAppUrl = url.toString()
      } catch {
        setStandardUrlInvalid(true)
        return
      }
    }

    if (
      addStoreAndList({
        name: selectedCatalogStore.name,
        icon: selectedCatalogStore.icon,
        color: selectedCatalogStore.color,
        city: standardCity.trim() || null,
        address: standardAddress.trim() || null,
        latitude: standardLatitude,
        longitude: standardLongitude,
        externalAppUrl,
      }, standardIncludeInGeneral)
    ) {
      closeCatalogStoreSetup()
      onBack()
    }
  }

  const submitCustomStore = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setFormAttempted(true)
    const name = customName.trim()
    if (!name) return

    if (
      addStoreAndList({
        name,
        color: customColor,
        icon: customIcon.trim() || undefined,
        city: customCity.trim() || null,
        address: customAddress.trim() || null,
        latitude: customLatitude,
        longitude: customLongitude,
      })
    ) {
      setCustomName('')
      setCustomIcon('')
      setCustomCity('')
      setCustomAddress('')
      setCustomLatitude(null)
      setCustomLongitude(null)
      setFormAttempted(false)
      onBack()
    }
  }

  return (
    <main className="screen store-catalog-screen">
      <header className="app-topbar">
        <IconButton icon={ArrowLeft} label={t('common.back')} onClick={onBack} />
        <div className="app-topbar__title">
          <h1>{t('storeCatalog.title')}</h1>
        </div>
      </header>

      <div className="screen-content">
        <SearchField
          autoComplete="off"
          clearLabel={t('common.clear')}
          label={t('storeCatalog.searchLabel')}
          onValueChange={setSearch}
          placeholder={t('storeCatalog.searchPlaceholder')}
          value={search}
        />

        <section aria-labelledby="catalog-popular" className="section-stack">
          <SectionHeader title={t('storeCatalog.popular')} />
          <span className="sr-only" id="catalog-popular">
            {t('storeCatalog.popular')}
          </span>
          <p className="quiet">{t('mock.noStoreApis')}</p>

          {availableStores.length > 0 ? (
            <div className="store-catalog-screen__grid">
              {availableStores.map((store) => (
                <article className="card card--padded store-catalog-screen__card" key={store.id}>
                  <div className="store-catalog-screen__identity">
                    <StoreMark
                      color={store.color}
                      icon={store.icon}
                      name={store.name}
                      storeId={store.id}
                    />
                    <div>
                      <h2>{store.name}</h2>
                      <p>{t('storeCatalog.popular')}</p>
                    </div>
                  </div>
                  <PrimaryButton
                    disabled={!currentUser}
                    leadingIcon={Settings2}
                    onClick={() => openCatalogStoreSetup(store)}
                  >
                    {t('storeCatalog.configure')}
                  </PrimaryButton>
                </article>
              ))}
            </div>
          ) : (
            <EmptyState
              actionLabel={search ? t('common.clear') : undefined}
              description={t('storeCatalog.noResultsHint')}
              icon={StoreIcon}
              onAction={search ? () => setSearch('') : undefined}
              title={t('storeCatalog.noResults')}
            />
          )}
        </section>

        <section aria-labelledby="catalog-custom" className="section-stack">
          <SectionHeader title={t('storeCatalog.other')} />
          <span className="sr-only" id="catalog-custom">
            {t('storeCatalog.other')}
          </span>

          <form className="card card--padded form-stack" onSubmit={submitCustomStore}>
            <label className="field">
              <span className="field__label">{t('storeForm.name')}</span>
              <input
                aria-invalid={formAttempted && !customName.trim() ? true : undefined}
                maxLength={60}
                onChange={(event) => setCustomName(event.currentTarget.value)}
                placeholder={t('storeForm.namePlaceholder')}
                value={customName}
              />
              {formAttempted && !customName.trim() ? (
                <span className="field__error" role="alert">
                  {t('validation.nameRequired')}
                </span>
              ) : null}
            </label>

            <div className="form-grid">
              <label className="field">
                <span className="field__label">{t('storeForm.icon')}</span>
                <input
                  maxLength={3}
                  onChange={(event) => setCustomIcon(event.currentTarget.value)}
                  placeholder={customName.trim().slice(0, 2).toLocaleUpperCase(localeTag)}
                  value={customIcon}
                />
              </label>
            </div>

            <StoreLocationFields
              address={customAddress}
              city={customCity}
              latitude={customLatitude}
              longitude={customLongitude}
              onAddressChange={setCustomAddress}
              onCityChange={setCustomCity}
              onCoordinatesChange={(latitude, longitude) => {
                setCustomLatitude(latitude)
                setCustomLongitude(longitude)
              }}
              t={t}
            />

            <fieldset className="store-catalog-screen__color-fieldset">
              <legend className="field__label">{t('storeForm.color')}</legend>
              <div className="color-options">
                {CUSTOM_COLORS.map((color) => (
                  <button
                    aria-label={`${t('storeForm.color')} ${color}`}
                    aria-pressed={customColor === color}
                    className="color-option"
                    key={color}
                    onClick={() => setCustomColor(color)}
                    style={{ '--option-color': color } as CSSProperties}
                    type="button"
                  >
                    {customColor === color ? <Check aria-hidden="true" size={18} /> : null}
                  </button>
                ))}
              </div>
            </fieldset>

            {!currentUser ? (
              <p className="field__error" role="alert">
                {t('error.permissionDenied')}
              </p>
            ) : null}

            <PrimaryButton disabled={!currentUser || !customName.trim()} type="submit">
              {t('stores.add')}
            </PrimaryButton>
          </form>
        </section>
      </div>

      <BottomSheet
        closeLabel={t('common.close')}
        description={t('storeCatalog.setupDescription')}
        footer={
          <>
            <SecondaryButton onClick={closeCatalogStoreSetup}>{t('common.cancel')}</SecondaryButton>
            <PrimaryButton
              disabled={!currentUser}
              form={standardSetupFormId}
              type="submit"
            >
              {t('storeCatalog.addStandard')}
            </PrimaryButton>
          </>
        }
        initialFocusRef={addressInputRef}
        isOpen={selectedCatalogStore !== null}
        onClose={closeCatalogStoreSetup}
        title={t('storeCatalog.setupTitle', {
          store: selectedCatalogStore?.name ?? '',
        })}
      >
        {selectedCatalogStore ? (
          <form
            className="form-stack"
            id={standardSetupFormId}
            noValidate
            onSubmit={submitCatalogStore}
          >
            <div className="store-catalog-screen__setup-identity">
              <StoreMark
                color={selectedCatalogStore.color}
                icon={selectedCatalogStore.icon}
                name={selectedCatalogStore.name}
                storeId={selectedCatalogStore.id}
              />
              <div>
                <strong>{selectedCatalogStore.name}</strong>
                <span>{t('mock.noStoreApis')}</span>
              </div>
            </div>

            <StoreLocationFields
              address={standardAddress}
              addressInputRef={addressInputRef}
              city={standardCity}
              latitude={standardLatitude}
              longitude={standardLongitude}
              onAddressChange={setStandardAddress}
              onCityChange={setStandardCity}
              onCoordinatesChange={(latitude, longitude) => {
                setStandardLatitude(latitude)
                setStandardLongitude(longitude)
              }}
              t={t}
            />

            <label className="field">
              <span className="field__label">{t('storeCatalog.externalAppUrl')}</span>
              <input
                aria-describedby={`${standardSetupFormId}-url-hint${
                  standardUrlInvalid ? ` ${standardSetupFormId}-url-error` : ''
                }`}
                aria-invalid={standardUrlInvalid || undefined}
                autoComplete="url"
                inputMode="url"
                maxLength={500}
                onChange={(event) => {
                  setStandardExternalUrl(event.currentTarget.value)
                  if (standardUrlInvalid) setStandardUrlInvalid(false)
                }}
                placeholder="https://"
                type="url"
                value={standardExternalUrl}
              />
              <span className="field__hint" id={`${standardSetupFormId}-url-hint`}>
                {t('storeCatalog.externalAppUrlHint')}
              </span>
              {standardUrlInvalid ? (
                <span
                  className="field__error"
                  id={`${standardSetupFormId}-url-error`}
                  role="alert"
                >
                  {t('validation.urlInvalid')}
                </span>
              ) : null}
            </label>

            <button
              aria-checked={standardIncludeInGeneral}
              className="card store-catalog-screen__general-toggle"
              onClick={() => setStandardIncludeInGeneral((current) => !current)}
              role="switch"
              type="button"
            >
              <span className="settings-row__copy">
                <strong>{t('storeCatalog.includeInGeneral')}</strong>
                <span>{t('storeCatalog.includeInGeneralHint')}</span>
              </span>
              <span className={standardIncludeInGeneral ? 'badge' : 'badge badge--quiet'}>
                {t(standardIncludeInGeneral ? 'common.enabled' : 'common.disabled')}
              </span>
            </button>
          </form>
        ) : null}
      </BottomSheet>
    </main>
  )
}
