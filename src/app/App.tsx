import { useEffect, useMemo, useState } from 'react'
import { AppErrorBoundary } from './AppErrorBoundary'
import { AppLoadingState } from './shell/AppLoadingState'
import { AppStatus } from './shell/AppStatus'
import { BottomNavigation, type MainDestination } from './shell/BottomNavigation'
import { CreateListSheet } from './shell/CreateListSheet'
import { QuickActionsSheet } from './shell/QuickActionsSheet'
import { HomeScreen } from '../features/home'
import { HistoryDetailScreen, HistoryScreen } from '../features/history'
import { NotificationsScreen } from '../features/notifications'
import { OnboardingScreen, type OnboardingPage } from '../features/onboarding/OnboardingScreen'
import { SplashScreen } from '../features/onboarding/SplashScreen'
import { ProfileScreen } from '../features/profile'
import {
  MoveProductSheet,
  ProductDetailSheet,
  ProductEditorSheet,
  type FeatureFeedback,
  type ProductEditorContext,
} from '../features/products'
import {
  SettingsScreen,
  type SettingsMockAction,
  type SettingsSection,
} from '../features/settings'
import { SharingScreen } from '../features/sharing'
import {
  DistributionSheet,
  GeneralListScreen,
  StoreListScreen,
} from '../features/shopping-lists'
import { StoreCatalogScreen, StoresScreen } from '../features/stores'
import { createTranslator, updateDocumentLanguage } from '../localization'
import { routes, useNavigation, type Route } from '../navigation'
import { useAppToast } from '../shared/hooks/useAppToast'
import { useOnlineStatus } from '../shared/hooks/useOnlineStatus'
import { downloadAppBackup, downloadListsCsv } from '../shared/downloads'
import { appActions } from '../store/appReducer'
import { AppStateProvider, useAppDispatch, useAppState } from '../store/AppStateProvider'
import { selectGeneralList, selectListById } from '../store/selectors'
import { Toast } from '../ui'
import { watchThemePreference } from '../shared/theme'

type SharingScope = 'store' | 'general' | 'family'
interface SharingTarget {
  scope: SharingScope
  listId: string | null
}

type OverlayState =
  | { type: 'quickActions' }
  | { type: 'createList'; initialStoreId?: string | null }
  | {
      type: 'productEditor'
      productId?: string | null
      context?: ProductEditorContext
      mode?: 'manual' | 'voice' | 'scanner'
    }
  | { type: 'productDetail'; productId: string }
  | { type: 'moveProduct'; productId: string }
  | { type: 'distribution' }
  | null

export function App() {
  return (
    <AppStateProvider>
      <AppBootstrap />
    </AppStateProvider>
  )
}

function AppBootstrap() {
  const state = useAppState()
  const t = useMemo(() => createTranslator(state.settings.locale), [state.settings.locale])

  return (
    <AppErrorBoundary
      title={t('state.error.title')}
      message={t('state.error.description')}
      retryLabel={t('common.retry')}
    >
      <AppRuntime />
    </AppErrorBoundary>
  )
}

function AppRuntime() {
  const state = useAppState()
  const dispatch = useAppDispatch()
  const navigation = useNavigation()
  const isOnline = useOnlineStatus()
  const { dismissToast, runToastAction, showToast, toast } = useAppToast()
  const [isSplashVisible, setSplashVisible] = useState(true)
  const [isDataLoading, setDataLoading] = useState(true)
  const [onboardingPage, setOnboardingPage] = useState(0)
  const [overlay, setOverlay] = useState<OverlayState>(null)
  const [settingsFocus, setSettingsFocus] = useState<SettingsSection | undefined>()
  const [sharingTarget, setSharingTarget] = useState<SharingTarget>({
    scope: 'family',
    listId: null,
  })
  const t = useMemo(() => createTranslator(state.settings.locale), [state.settings.locale])

  useEffect(() => {
    const splashTimer = window.setTimeout(() => setSplashVisible(false), 620)
    const dataTimer = window.setTimeout(() => setDataLoading(false), 980)
    return () => {
      window.clearTimeout(splashTimer)
      window.clearTimeout(dataTimer)
    }
  }, [])

  useEffect(() => updateDocumentLanguage(state.settings.locale), [state.settings.locale])

  useEffect(
    () => watchThemePreference(state.settings.theme),
    [state.settings.theme],
  )

  useEffect(() => {
    setOverlay(null)
    window.scrollTo({ top: 0, behavior: 'auto' })
  }, [navigation.route])

  const onboardingPages: OnboardingPage[] = [
    {
      title: t('onboarding.first.title'),
      description: t('onboarding.first.description'),
    },
    {
      title: t('onboarding.second.title'),
      description: t('onboarding.second.description'),
    },
    {
      title: t('onboarding.third.title'),
      description: t('onboarding.third.description'),
    },
  ]

  if (isSplashVisible) return <SplashScreen />

  if (isDataLoading) return <AppLoadingState label={t('state.loadingData')} />

  if (!state.hasCompletedOnboarding) {
    return (
      <OnboardingScreen
        page={onboardingPage}
        pages={onboardingPages}
        continueLabel={t('onboarding.continue')}
        startLabel={t('onboarding.start')}
        stepLabel={(current, total) => t('a11y.pageIndicator', { current, total })}
        onPageChange={setOnboardingPage}
        onContinue={() => {
          if (onboardingPage < onboardingPages.length - 1) {
            setOnboardingPage((current) => current + 1)
            return
          }
          dispatch(appActions.completeOnboarding())
          navigation.navigate(routes.home(), { replace: true })
        }}
      />
    )
  }

  const activeDestination = destinationForRoute(navigation.route)

  const openList = (listId: string, fallbackStoreId: string | null = null) => {
    const list = selectListById(state, listId)
    const storeId = list?.storeId ?? fallbackStoreId
    navigation.navigate(storeId ? routes.storeList(storeId) : routes.generalList())
  }

  const defaultProductContext = (): ProductEditorContext | null => {
    const existing = selectGeneralList(state)
    if (existing) return { listId: existing.id, storeId: null }

    const action = appActions.createList({
      title: t('home.generalList'),
      storeId: null,
      ownerId: state.currentUserId,
      members: state.users.map((user) => user.id),
    })
    if (action.type !== 'list/create') return null
    dispatch(action)
    return { listId: action.payload.id, storeId: null }
  }

  const openNewProduct = (
    context: ProductEditorContext | null = defaultProductContext(),
    mode: 'manual' | 'voice' | 'scanner' = 'manual',
  ) => {
    if (!context) {
      showToast(t('state.error.description'), { tone: 'error' })
      return
    }
    setOverlay({ type: 'productEditor', context, mode })
  }

  const handleFeedback = (feedback: FeatureFeedback) => {
    showToast(feedback.message, {
      tone: feedback.tone ?? 'info',
      actionLabel: feedback.actionLabel,
      onAction: feedback.onAction,
    })
  }

  const showSuccess = (message: string) => showToast(message, { tone: 'success' })

  const handleSettingsAction = (action: SettingsMockAction) => {
    if (action === 'backup') downloadAppBackup(state)
    if (action === 'export') downloadListsCsv(state)
  }

  const renderRoute = (route: Route) => {
    switch (route.name) {
      case 'home':
        return (
          <HomeScreen
            onOpenCatalog={() => navigation.navigate(routes.storeCatalog())}
            onOpenGeneralList={() => navigation.navigate(routes.generalList())}
            onOpenNotifications={() => navigation.navigate(routes.notifications())}
            onOpenStore={(storeId) => navigation.navigate(routes.storeList(storeId))}
            onToast={showSuccess}
          />
        )
      case 'stores':
        return (
          <StoresScreen
            onOpenCatalog={() => navigation.navigate(routes.storeCatalog())}
            onOpenStore={(storeId) => navigation.navigate(routes.storeList(storeId))}
            onToast={showSuccess}
          />
        )
      case 'storeCatalog':
        return <StoreCatalogScreen onBack={navigation.back} onToast={showSuccess} />
      case 'generalList':
        return (
          <GeneralListScreen
            onAddProduct={(context) => openNewProduct(context)}
            onBack={navigation.back}
            onFeedback={handleFeedback}
            onMoveProduct={(productId) => setOverlay({ type: 'moveProduct', productId })}
            onOpenDistribution={() => setOverlay({ type: 'distribution' })}
            onOpenProduct={(productId) => setOverlay({ type: 'productDetail', productId })}
          />
        )
      case 'storeList':
        return (
          <StoreListScreen
            storeId={route.storeId}
            onAddProduct={(context) => openNewProduct(context)}
            onBack={navigation.back}
            onCompleted={() => navigation.navigate(routes.history())}
            onCreateList={(storeId) => setOverlay({ type: 'createList', initialStoreId: storeId })}
            onFeedback={handleFeedback}
            onMoveProduct={(productId) => setOverlay({ type: 'moveProduct', productId })}
            onOpenMore={() => navigation.navigate(routes.stores())}
            onOpenProduct={(productId) => setOverlay({ type: 'productDetail', productId })}
            onShare={(listId) => {
              setSharingTarget({ scope: 'store', listId })
              navigation.navigate(routes.sharing())
            }}
          />
        )
      case 'history':
        return (
          <HistoryScreen
            onOpenEntry={(historyId) => navigation.navigate(routes.historyDetail(historyId))}
            onOpenList={openList}
            onShowToast={showToast}
          />
        )
      case 'historyDetail':
        return (
          <HistoryDetailScreen
            historyId={route.historyId}
            onBack={navigation.back}
            onOpenList={openList}
            onShowToast={showToast}
          />
        )
      case 'profile':
        return (
          <ProfileScreen
            onOpenNotifications={() => navigation.navigate(routes.notifications())}
            onOpenSettings={(destination) => {
              setSettingsFocus(destination)
              navigation.navigate(routes.settings())
            }}
            onOpenSharing={() => {
              setSharingTarget({ scope: 'family', listId: null })
              navigation.navigate(routes.sharing())
            }}
            onPrototypeAction={() => undefined}
            onShowToast={showToast}
          />
        )
      case 'notifications':
        return (
          <NotificationsScreen
            onBack={navigation.back}
            onOpenHistory={() => navigation.navigate(routes.history())}
            onOpenList={(listId) => openList(listId)}
            onShowToast={showToast}
          />
        )
      case 'sharing':
        return (
          <SharingScreen
            initialListId={sharingTarget.listId}
            initialScope={sharingTarget.scope}
            onBack={navigation.back}
            onOpenList={openList}
            onShowToast={showToast}
          />
        )
      case 'settings':
        return (
          <SettingsScreen
            focusSection={settingsFocus}
            onBack={navigation.back}
            onMockAction={handleSettingsAction}
            onOpenNotifications={() => navigation.navigate(routes.notifications())}
            onShowToast={showToast}
          />
        )
    }
  }

  return (
    <div className="app-canvas">
      <a className="skip-link" href="#onecart-main">
        {t('a11y.skipToContent')}
      </a>
      <div className="app-shell">
        <AppStatus offline={!isOnline} offlineMessage={t('state.offline.description')} />
        <div className="app-main" id="onecart-main" tabIndex={-1}>
          {renderRoute(navigation.route)}
        </div>
        <BottomNavigation
          active={activeDestination}
          labels={{
            main: t('nav.mainLabel'),
            home: t('nav.home'),
            stores: t('nav.stores'),
            add: t('nav.add'),
            history: t('nav.history'),
            profile: t('nav.profile'),
          }}
          onAdd={() => setOverlay({ type: 'quickActions' })}
          onNavigate={(destination) => navigation.navigate(routeForDestination(destination))}
        />
      </div>

      <QuickActionsSheet
        isOpen={overlay?.type === 'quickActions'}
        labels={{
          title: t('quickActions.title'),
          close: t('common.close'),
          product: t('quickActions.product'),
          productDescription: t('products.mode.manual'),
          list: t('quickActions.list'),
          listDescription: t('lists.createTitle'),
          store: t('quickActions.store'),
          storeDescription: t('storeCatalog.popular'),
          voice: t('quickActions.voice'),
          voiceDescription: t('voice.mockNotice'),
        }}
        onClose={() => setOverlay(null)}
        onAddProduct={() => openNewProduct()}
        onCreateList={() => setOverlay({ type: 'createList' })}
        onAddStore={() => {
          setOverlay(null)
          navigation.navigate(routes.storeCatalog())
        }}
        onAddVoice={() => openNewProduct(defaultProductContext(), 'voice')}
      />

      <CreateListSheet
        initialStoreId={overlay?.type === 'createList' ? overlay.initialStoreId : null}
        isOpen={overlay?.type === 'createList'}
        t={t}
        onClose={() => setOverlay(null)}
        onCreated={({ created, listId, storeId }) => {
          showSuccess(t(created ? 'toast.listCreated' : 'toast.listOpened'))
          openList(listId, storeId)
        }}
      />

      <ProductEditorSheet
        isOpen={overlay?.type === 'productEditor'}
        productId={overlay?.type === 'productEditor' ? overlay.productId : null}
        initialContext={overlay?.type === 'productEditor' ? overlay.context : undefined}
        initialMode={overlay?.type === 'productEditor' ? overlay.mode : undefined}
        onClose={() => setOverlay(null)}
        onFeedback={handleFeedback}
      />

      <ProductDetailSheet
        isOpen={overlay?.type === 'productDetail'}
        productId={overlay?.type === 'productDetail' ? overlay.productId : null}
        onClose={() => setOverlay(null)}
        onEdit={(productId) => setOverlay({ type: 'productEditor', productId })}
        onMove={(productId) => setOverlay({ type: 'moveProduct', productId })}
        onFeedback={handleFeedback}
      />

      <MoveProductSheet
        isOpen={overlay?.type === 'moveProduct'}
        productId={overlay?.type === 'moveProduct' ? overlay.productId : null}
        onClose={() => setOverlay(null)}
        onFeedback={handleFeedback}
      />

      <DistributionSheet
        isOpen={overlay?.type === 'distribution'}
        onClose={() => setOverlay(null)}
        onFeedback={handleFeedback}
      />

      {toast ? (
        <Toast
          className={toast.isDismissing ? 'ui-toast--leaving' : undefined}
          message={toast.message}
          tone={toast.tone}
          actionLabel={toast.actionLabel}
          onAction={toast.onAction ? runToastAction : undefined}
          dismissLabel={t('common.close')}
          onDismiss={dismissToast}
        />
      ) : null}
    </div>
  )
}

function destinationForRoute(route: Route): MainDestination | null {
  switch (route.name) {
    case 'home':
    case 'generalList':
    case 'notifications':
      return 'home'
    case 'stores':
    case 'storeCatalog':
    case 'storeList':
      return 'stores'
    case 'history':
    case 'historyDetail':
      return 'history'
    case 'profile':
    case 'settings':
    case 'sharing':
      return 'profile'
  }
}

function routeForDestination(destination: MainDestination): Route {
  switch (destination) {
    case 'home':
      return routes.home()
    case 'stores':
      return routes.stores()
    case 'history':
      return routes.history()
    case 'profile':
      return routes.profile()
  }
}
