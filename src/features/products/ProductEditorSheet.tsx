import { useEffect, useId, useRef, useState, type FormEvent } from 'react'
import { Barcode, Keyboard, Mic } from 'lucide-react'
import {
  PRODUCT_CATEGORIES,
  PRODUCT_UNITS,
  type ProductCategory,
  type ProductUnit,
} from '../../domain/models'
import { resolveProductMedia } from '../../data/productMedia'
import { createTranslator } from '../../localization'
import { useAppDispatch, useAppState } from '../../store/AppStateProvider'
import { appActions } from '../../store/appReducer'
import {
  selectActiveListForStore,
  selectCurrentUser,
  selectGeneralList,
  selectProductById,
  selectSortedStores,
} from '../../store/selectors'
import { PrimaryButton, SecondaryButton } from '../../ui'
import { AccessibleSheet } from './AccessibleSheet'
import {
  CATEGORY_TRANSLATION_KEYS,
  PRODUCT_SUGGESTIONS,
  UNIT_TRANSLATION_KEYS,
} from './productPresentation'
import type { FeatureFeedback, ProductEditorContext } from './types'

type EditorMode = 'manual' | 'voice' | 'scanner'

interface EditorFormState {
  name: string
  quantity: string
  unit: ProductUnit
  storeId: string
  category: ProductCategory
  estimatedPrice: string
  note: string
  listId: string
}

interface EditorErrors {
  name?: string
  quantity?: string
  estimatedPrice?: string
  listId?: string
}

export interface ProductEditorSheetProps {
  isOpen: boolean
  onClose: () => void
  productId?: string | null
  initialContext?: ProductEditorContext
  initialMode?: EditorMode
  onSaved?: (productId: string, operation: 'added' | 'updated') => void
  onFeedback?: (feedback: FeatureFeedback) => void
}

function parseNumber(value: string): number {
  return Number(value.replace(',', '.'))
}

export function ProductEditorSheet({
  initialContext,
  initialMode = 'manual',
  isOpen,
  onClose,
  onFeedback,
  onSaved,
  productId = null,
}: ProductEditorSheetProps) {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const locale = state.settings.locale
  const t = createTranslator(locale)
  const product = selectProductById(state, productId)
  const currentUser = selectCurrentUser(state)
  const generalList = selectGeneralList(state)
  const stores = selectSortedStores(state)
  const isEditing = Boolean(productId)
  const formId = useId()
  const manualPanelId = useId()
  const voicePanelId = useId()
  const scannerPanelId = useId()
  const nameInputRef = useRef<HTMLInputElement>(null)

  const [mode, setMode] = useState<EditorMode>(initialMode)
  const [form, setForm] = useState<EditorFormState>({
    name: '',
    quantity: '1',
    unit: state.settings.defaultUnit,
    storeId: initialContext?.storeId ?? '',
    category: 'other',
    estimatedPrice: '',
    note: '',
    listId: initialContext?.listId ?? generalList?.id ?? '',
  })
  const [errors, setErrors] = useState<EditorErrors>({})
  const [voiceResult, setVoiceResult] = useState<string | null>(null)
  const [scannerResult, setScannerResult] = useState<string | null>(null)

  useEffect(() => {
    if (!isOpen) {
      return
    }

    setMode(initialMode)
    setErrors({})
    setVoiceResult(null)
    setScannerResult(null)
    if (product) {
      setForm({
        name: product.name,
        quantity: String(product.quantity),
        unit: product.unit,
        storeId: product.storeId ?? '',
        category: product.category,
        estimatedPrice: product.estimatedPrice ? String(product.estimatedPrice) : '',
        note: product.note,
        listId: product.listId,
      })
      return
    }

    setForm({
      name: '',
      quantity: '1',
      unit: state.settings.defaultUnit,
      storeId: initialContext?.storeId ?? '',
      category: 'other',
      estimatedPrice: '',
      note: '',
      listId: initialContext?.listId ?? generalList?.id ?? '',
    })
  }, [
    generalList?.id,
    initialContext?.listId,
    initialContext?.storeId,
    initialMode,
    isOpen,
    product,
    state.settings.defaultUnit,
  ])

  const chooseManualMode = (name?: string) => {
    if (name) {
      setForm((current) => ({ ...current, name }))
    }
    setMode('manual')
    window.requestAnimationFrame(() => nameInputRef.current?.focus())
  }

  const simulateVoice = () => {
    const result = locale === 'uk' ? 'Молоко 2,5%' : 'Молоко 2,5%'
    setVoiceResult(result)
  }

  const simulateScanner = () => {
    const result = locale === 'uk' ? 'Сир' : 'Сыр'
    setScannerResult(result)
  }

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    const quantity = parseNumber(form.quantity)
    const estimatedPrice = form.estimatedPrice.trim() ? parseNumber(form.estimatedPrice) : 0
    const nextErrors: EditorErrors = {}

    if (!form.name.trim()) {
      nextErrors.name = t('validation.nameRequired')
    }
    if (!Number.isFinite(quantity) || quantity <= 0) {
      nextErrors.quantity = t('validation.quantityPositive')
    }
    if (!Number.isFinite(estimatedPrice) || estimatedPrice < 0) {
      nextErrors.estimatedPrice = t('validation.priceNonNegative')
    }

    const selectedStoreId = form.storeId || null
    const destinationList =
      (selectedStoreId
        ? selectActiveListForStore(state, selectedStoreId)
        : generalList ?? state.shoppingLists.find((list) => list.id === form.listId)) ?? null
    if (!destinationList) {
      nextErrors.listId = t('common.notAvailable')
    }

    setErrors(nextErrors)
    if (Object.keys(nextErrors).length > 0 || !destinationList || !currentUser) {
      return
    }
    const media = resolveProductMedia(form.name, selectedStoreId ?? '')

    if (product) {
      const changedAt = new Date().toISOString()
      dispatch(
        appActions.updateProduct(
          product.id,
          {
            name: form.name.trim(),
            quantity,
            unit: form.unit,
            category: form.category,
            estimatedPrice,
            note: form.note.trim(),
            imageUrl: media?.imageUrl ?? null,
            imageSourceUrl: media?.sourceUrl ?? null,
            imageSourceLabel: media?.sourceLabel ?? null,
          },
          changedAt,
        ),
      )
      if (product.storeId !== selectedStoreId || product.listId !== destinationList.id) {
        dispatch(
          appActions.moveProduct(product.id, selectedStoreId, destinationList.id, changedAt),
        )
      }
      onFeedback?.({ message: t('toast.productUpdated'), tone: 'success' })
      onSaved?.(product.id, 'updated')
      onClose()
      return
    }

    const action = appActions.addProduct({
      name: form.name.trim(),
      quantity,
      unit: form.unit,
      category: form.category,
      estimatedPrice,
      note: form.note.trim(),
      storeId: selectedStoreId,
      listId: destinationList.id,
      addedBy: currentUser.id,
      imageUrl: media?.imageUrl ?? null,
      imageSourceUrl: media?.sourceUrl ?? null,
      imageSourceLabel: media?.sourceLabel ?? null,
    })
    dispatch(action)
    if (action.type === 'product/add') {
      onSaved?.(action.payload.product.id, 'added')
    }
    onFeedback?.({ message: t('toast.productAdded'), tone: 'success' })
    onClose()
  }

  const footer = (
    <>
      <SecondaryButton className="secondary-button" onClick={onClose}>
        {t('common.cancel')}
      </SecondaryButton>
      {mode === 'manual' ? (
        <PrimaryButton className="primary-button" form={formId} type="submit">
          {isEditing ? t('common.save') : t('common.add')}
        </PrimaryButton>
      ) : mode === 'voice' ? (
        <PrimaryButton
          className="primary-button"
          onClick={() => (voiceResult ? chooseManualMode(voiceResult) : simulateVoice())}
        >
          {voiceResult ? t('voice.confirm') : t('voice.simulate')}
        </PrimaryButton>
      ) : (
        <PrimaryButton
          className="primary-button"
          onClick={() => (scannerResult ? chooseManualMode(scannerResult) : simulateScanner())}
        >
          {scannerResult ? t('scanner.manual') : t('scanner.simulate')}
        </PrimaryButton>
      )}
    </>
  )

  if (isEditing && !product) {
    return (
      <AccessibleSheet
        closeLabel={t('common.close')}
        footer={
          <PrimaryButton className="primary-button button--full" onClick={onClose}>
            {t('common.close')}
          </PrimaryButton>
        }
        isOpen={isOpen}
        onClose={onClose}
        title={t('products.editTitle')}
      >
        <div aria-live="polite" className="card card--padded">
          <p>{t('common.notAvailable')}</p>
        </div>
      </AccessibleSheet>
    )
  }

  return (
    <AccessibleSheet
      closeLabel={t('common.close')}
      footer={footer}
      initialFocusRef={mode === 'manual' ? nameInputRef : undefined}
      isOpen={isOpen}
      onClose={onClose}
      title={isEditing ? t('products.editTitle') : t('products.addTitle')}
    >
      <div aria-label={isEditing ? t('products.editTitle') : t('products.addTitle')} className="segmented-control" role="tablist">
        <button
          aria-controls={manualPanelId}
          aria-selected={mode === 'manual'}
          onClick={() => setMode('manual')}
          role="tab"
          type="button"
        >
          <Keyboard aria-hidden="true" size={17} />
          {t('products.mode.manual')}
        </button>
        <button
          aria-controls={voicePanelId}
          aria-selected={mode === 'voice'}
          onClick={() => setMode('voice')}
          role="tab"
          type="button"
        >
          <Mic aria-hidden="true" size={17} />
          {t('products.mode.voice')}
        </button>
        <button
          aria-controls={scannerPanelId}
          aria-selected={mode === 'scanner'}
          onClick={() => setMode('scanner')}
          role="tab"
          type="button"
        >
          <Barcode aria-hidden="true" size={17} />
          {t('products.mode.scanner')}
        </button>
      </div>

      {mode === 'manual' ? (
        <form className="form-stack" id={formId} onSubmit={submit} role="tabpanel">
          <div className="field">
            <label className="field__label" htmlFor={`${formId}-name`}>
              {t('products.name')}
            </label>
            <input
              aria-describedby={errors.name ? `${formId}-name-error` : undefined}
              aria-invalid={Boolean(errors.name)}
              autoComplete="off"
              id={`${formId}-name`}
              maxLength={100}
              onChange={(event) => setForm((current) => ({ ...current, name: event.target.value }))}
              placeholder={t('products.namePlaceholder')}
              ref={nameInputRef}
              required
              value={form.name}
            />
            {errors.name ? (
              <span className="field__error" id={`${formId}-name-error`} role="alert">
                {errors.name}
              </span>
            ) : null}
          </div>

          <div>
            <p className="field__label">{t('products.suggestions')}</p>
            <div className="suggestion-list">
              {PRODUCT_SUGGESTIONS[locale].map((suggestion) => (
                <button
                  key={suggestion}
                  onClick={() => setForm((current) => ({ ...current, name: suggestion }))}
                  type="button"
                >
                  {suggestion}
                </button>
              ))}
            </div>
          </div>

          <div className="form-grid">
            <div className="field">
              <label className="field__label" htmlFor={`${formId}-quantity`}>
                {t('products.quantity')}
              </label>
              <input
                aria-describedby={errors.quantity ? `${formId}-quantity-error` : undefined}
                aria-invalid={Boolean(errors.quantity)}
                id={`${formId}-quantity`}
                inputMode="decimal"
                min="0.001"
                onChange={(event) =>
                  setForm((current) => ({ ...current, quantity: event.target.value }))
                }
                required
                step="any"
                type="number"
                value={form.quantity}
              />
              {errors.quantity ? (
                <span className="field__error" id={`${formId}-quantity-error`} role="alert">
                  {errors.quantity}
                </span>
              ) : null}
            </div>
            <div className="field">
              <label className="field__label" htmlFor={`${formId}-unit`}>
                {t('products.unit')}
              </label>
              <select
                id={`${formId}-unit`}
                onChange={(event) =>
                  setForm((current) => ({
                    ...current,
                    unit: event.target.value as ProductUnit,
                  }))
                }
                value={form.unit}
              >
                {PRODUCT_UNITS.map((unit) => (
                  <option key={unit} value={unit}>
                    {t(UNIT_TRANSLATION_KEYS[unit])}
                  </option>
                ))}
              </select>
            </div>

            <div className="field">
              <label className="field__label" htmlFor={`${formId}-store`}>
                {t('products.store')}
              </label>
              <select
                aria-describedby={errors.listId ? `${formId}-store-error` : undefined}
                aria-invalid={Boolean(errors.listId)}
                id={`${formId}-store`}
                onChange={(event) => {
                  setForm((current) => ({ ...current, storeId: event.target.value }))
                  if (errors.listId) setErrors((current) => ({ ...current, listId: undefined }))
                }}
                value={form.storeId}
              >
                <option value="">{t('lists.noStore')}</option>
                {stores.map((store) => (
                  <option key={store.id} value={store.id}>
                    {store.name}
                  </option>
                ))}
              </select>
              {errors.listId ? (
                <span className="field__error" id={`${formId}-store-error`} role="alert">
                  {errors.listId}
                </span>
              ) : null}
            </div>

            <div className="field">
              <label className="field__label" htmlFor={`${formId}-category`}>
                {t('products.category')}
              </label>
              <select
                id={`${formId}-category`}
                onChange={(event) =>
                  setForm((current) => ({
                    ...current,
                    category: event.target.value as ProductCategory,
                  }))
                }
                value={form.category}
              >
                {PRODUCT_CATEGORIES.map((category) => (
                  <option key={category} value={category}>
                    {t(CATEGORY_TRANSLATION_KEYS[category])}
                  </option>
                ))}
              </select>
            </div>

            <div className="field field--full">
              <label className="field__label" htmlFor={`${formId}-price`}>
                {t('products.estimatedPrice')}
              </label>
              <input
                aria-describedby={`${formId}-price-hint${errors.estimatedPrice ? ` ${formId}-price-error` : ''}`}
                aria-invalid={Boolean(errors.estimatedPrice)}
                id={`${formId}-price`}
                inputMode="decimal"
                min="0"
                onChange={(event) =>
                  setForm((current) => ({ ...current, estimatedPrice: event.target.value }))
                }
                step="0.01"
                type="number"
                value={form.estimatedPrice}
              />
              <span className="field__hint" id={`${formId}-price-hint`}>
                {t('products.priceHint')}
              </span>
              {errors.estimatedPrice ? (
                <span className="field__error" id={`${formId}-price-error`} role="alert">
                  {errors.estimatedPrice}
                </span>
              ) : null}
            </div>

            <div className="field field--full">
              <label className="field__label" htmlFor={`${formId}-note`}>
                {t('products.note')}
              </label>
              <textarea
                id={`${formId}-note`}
                maxLength={300}
                onChange={(event) => setForm((current) => ({ ...current, note: event.target.value }))}
                placeholder={t('products.notePlaceholder')}
                value={form.note}
              />
            </div>
          </div>
        </form>
      ) : mode === 'voice' ? (
        <section aria-labelledby={`${formId}-voice-title`} className="voice-stage" id={voicePanelId} role="tabpanel">
          <span aria-hidden="true" className="voice-pulse">
            <Mic size={38} />
          </span>
          <div>
            <h3 id={`${formId}-voice-title`}>{t('voice.title')}</h3>
            <p className="muted">{t('voice.mockNotice')}</p>
          </div>
          <p aria-live="polite">
            {voiceResult ? `${t('voice.transcript')}: ${voiceResult}` : t('voice.idle')}
          </p>
        </section>
      ) : (
        <section aria-labelledby={`${formId}-scanner-title`} className="scanner-stage" id={scannerPanelId} role="tabpanel">
          <div aria-hidden="true" className="scanner-frame" />
          <div>
            <h3 id={`${formId}-scanner-title`}>{t('scanner.title')}</h3>
            <p className="muted">{t('scanner.mockNotice')}</p>
          </div>
          <p aria-live="polite">
            {scannerResult
              ? t('scanner.result', { product: scannerResult })
              : t('scanner.instruction')}
          </p>
        </section>
      )}
    </AccessibleSheet>
  )
}
