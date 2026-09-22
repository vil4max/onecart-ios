import AuthenticationServices
import CoreData
import Foundation
import SwiftUI

@MainActor
@Observable
final class AppSession {

    nonisolated static let defaultFamilyName = String(
        localized: "cart.default_title",
        defaultValue: "OneCart Family"
    )

    var isReady = false
    private(set) var isBusy = false
    var needsWelcome = false
    var welcomePhase: WelcomePhase = .signIn
    var account: OneCartAccount?
    var syncState: OneCartSyncState = .synchronized
    var lastSyncError: String?
    var familySpaces: [FamilySpace] = []
    var activeFamilySpace: FamilySpace?
    var familyMembers: [FamilyMember] = []
    var access: FamilyAccess?
    var isFamilyMetadataLoading = false
    var isEnsuringHouseholdCart = false
    var householdCartBootstrapFailed = false
    var preferredMainTab: MainTab?
    var userAlert: UserAlert?
    var sharedCartRemovedMessage: String?
    var isDeletingAccount = false
    var isReconcilingPersonalCart = false
    var pendingCartMutationCount = 0
    /// Backs `isBusy` for operations that may overlap, so the first one to finish
    /// does not clear the flag while another is still running.
    private(set) var busyOperationCount = 0

    var alertMessage: String? {
        userAlert?.message
    }

    let preferences: DevicePreferences
    let persistence: PersistenceController
    let cartSync: CartSyncService
    let cartContent: CartContentStore
    let bootstrapper: SessionBootstrapper
    let cloudSync: CloudSyncCoordinator
    let invitePreparer: InviteLinkPreparer
    let household: HouseholdCartCoordinator
    let accountCloudDataDeleter: AccountCloudDataDeleting
    let accountLocalStorePreparer: AccountLocalStorePreparing
    let widgetStore: WidgetSnapshotStore
    var startupTask: Task<Void, Never>?
    var widgetDrainTask: Task<Void, Error>?

    var lists: [ShoppingListEntity] {
        cartContent.lists
    }

    var activeLists: [ShoppingListEntity] {
        cartContent.activeLists
    }

    var products: [ProductEntity] {
        cartContent.products
    }

    var productsByListID: [UUID: [ProductEntity]] {
        cartContent.productsByListID
    }

    var history: [PurchaseHistoryEntity] {
        cartContent.history
    }

    var historyHasMore: Bool {
        cartContent.historyHasMore
    }

    var preparedInviteLink: FamilyInviteLink? {
        invitePreparer.preparedInviteLink
    }

    var canEdit: Bool {
        !isReconcilingPersonalCart && !isDeletingAccount && activeFamilySpace != nil && (access?.canEdit ?? false)
    }

    var isOnline: Bool {
        online
    }

    var isCartSyncing: Bool {
        cartSync.isCartSyncing
    }

    var contentRevision: Int {
        cartSync.contentRevision
    }

    var cartTitle: String {
        activeFamilySpace?.displayName
            ?? account.map { Self.householdCartName(for: $0) }
            ?? Self.defaultFamilyName
    }

    static func householdCartName(for account: OneCartAccount) -> String {
        let trimmed = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !ParticipantDisplayName.isPlaceholder(trimmed)
        else {
            return defaultFamilyName
        }
        return String(localized: "cart.personal_title \(trimmed)")
    }

    let repository: FamilySpaceRepository
    let backend: CloudKitBackendService
    let shareOrchestrator: FamilyShareOrchestrator
    let appleSignIn: AppleSignInAuthenticating
    let defaults: UserDefaults
    var online = true
    var started = false
    var didPresentProductionSchemaAlert = false
    var lastActiveFamilyWasShared = false

    init(
        persistence: PersistenceController? = nil,
        preferences: DevicePreferences? = nil,
        defaults: UserDefaults = .standard,
        backend: CloudKitBackendService? = nil,
        appleSignIn: AppleSignInAuthenticating = AppleSignInService.shared,
        accountCloudDataDeleter: AccountCloudDataDeleting? = nil,
        accountLocalStorePreparer: AccountLocalStorePreparing? = nil,
        widgetStore: WidgetSnapshotStore = .shared
    ) {
        let persistence = persistence ?? Self.makeDefaultPersistence()
        self.persistence = persistence
        self.preferences = preferences ?? DevicePreferences(defaults: defaults)
        self.defaults = defaults
        self.appleSignIn = appleSignIn
        self.widgetStore = widgetStore

        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: CloudKitPermissionAuthorizer(persistence: persistence)
        )
        let backend = backend ?? CloudKitBackendService(persistence: persistence)
        self.repository = repository
        self.backend = backend
        self.accountCloudDataDeleter = accountCloudDataDeleter ?? backend
        self.accountLocalStorePreparer = accountLocalStorePreparer ?? persistence
        cartSync = CartSyncService(persistence: persistence)
        cartContent = CartContentStore(persistence: persistence)
        bootstrapper = SessionBootstrapper(
            persistence: persistence,
            repository: repository,
            backend: backend,
            appleSignIn: appleSignIn
        )
        cloudSync = CloudSyncCoordinator(persistence: persistence, cartSync: cartSync)
        shareOrchestrator = FamilyShareOrchestrator(
            persistence: persistence,
            backend: backend,
            repository: repository
        )
        invitePreparer = InviteLinkPreparer()
        household = HouseholdCartCoordinator(
            persistence: persistence,
            repository: repository,
            defaults: defaults
        )
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            isReady = true
        }
        bootstrapper.bind(host: self)
        cloudSync.bind(host: self)
        household.bind(host: self)
        bindCartSync()
    }

    private static func makeDefaultPersistence() -> PersistenceController {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return PersistenceController(inMemory: true, cloudKitEnabled: false)
        }
        return .shared
    }

    private func bindCartSync() {
        preferences.onChanged = { [weak self] in
            self?.updateWidgetSnapshot()
        }
        preferences.onAccentChanged = { [weak self] newAccent in
            self?.updateWidgetSnapshot(accentOverride: newAccent)
        }
        preferences.onThemeChanged = { [weak self] newTheme in
            self?.updateWidgetSnapshot(themeOverride: newTheme)
        }
        cartSync.onHardRefresh = { [weak self] in
            guard let self else { return }
            try CartSyncService.resetViewContextAndRefetch(persistence: persistence) {
                try self.reload()
            }
        }
        cartSync.onOwnerACLHeal = { [weak self] in
            guard let self, let family = activeFamilySpace else { return }
            await shareOrchestrator.ensureOwnerReadWriteACL(
                for: family,
                isOwner: access?.isOwner == true
            )
        }
        cartSync.onInviteeSharedGone = { [weak self] in
            await self?.household.handleInviteeSharedCartGoneIfNeeded()
        }
        cartSync.purchasedCountProvider = { [weak self] in
            guard let self else { return (0, 0) }
            let total = products.count
            let purchased = products.filter(\.isPurchasedValue).count
            return (purchased, total)
        }
    }

    func syncCart(reason: CartSyncReason) async {
        await cloudSync.syncCart(reason: reason)
        switch reason {
        case .appear, .foreground, .cloudImport:
            // CloudKit may have delivered a same-name row from another device
            // with a different stable ID — merge before archiving/presenting.
            await deduplicateCartIfNeeded()
        case .pull:
            break
        }
        switch reason {
        case .appear, .foreground:
            await archiveStalePurchasedIfNeeded()
        case .pull, .cloudImport:
            break
        }
    }

    func beginBusyOperation() {
        busyOperationCount += 1
        isBusy = true
    }

    func endBusyOperation() {
        busyOperationCount = max(0, busyOperationCount - 1)
        if busyOperationCount == 0 {
            isBusy = false
        }
    }

    func dismissSharedCartRemovedMessage() {
        sharedCartRemovedMessage = nil
    }
}
