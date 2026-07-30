import AuthenticationServices
import Combine
import CoreData
import Foundation
import SwiftUI

@MainActor
final class AppSession: ObservableObject {

    nonisolated static let defaultFamilyName = String(
        localized: "cart.default_title",
        defaultValue: "Tim's Cart"
    )

    @Published var isReady = false
    @Published var isBusy = false
    @Published var needsWelcome = false
    @Published var welcomePhase: WelcomePhase = .signIn
    @Published var account: OneCartAccount?
    @Published var syncState: OneCartSyncState = .synchronized
    @Published var lastSyncError: String?
    @Published var familySpaces: [FamilySpace] = []
    @Published var activeFamilySpace: FamilySpace?
    @Published var familyMembers: [FamilyMember] = []
    @Published var access: FamilyAccess?
    @Published var isFamilyMetadataLoading = false
    @Published var isEnsuringHouseholdCart = false
    @Published var householdCartBootstrapFailed = false
    @Published var preferredMainTab: MainTab?
    @Published var alertMessage: String?
    @Published var sharedCartRemovedMessage: String?

    let preferences: DevicePreferences
    let persistence: PersistenceController
    let cartSync: CartSyncService
    let cartContent: CartContentStore
    let bootstrapper: SessionBootstrapper
    let cloudSync: CloudSyncCoordinator
    let invitePreparer: InviteLinkPreparer
    let household: HouseholdCartCoordinator

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
        activeFamilySpace != nil && (access?.canEdit ?? false)
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

    static func householdCartName(for _: OneCartAccount) -> String {
        defaultFamilyName
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
    private var cartSyncCancellable: AnyCancellable?
    private var cartContentCancellable: AnyCancellable?
    private var invitePreparerCancellable: AnyCancellable?

    init(
        persistence: PersistenceController? = nil,
        preferences: DevicePreferences = DevicePreferences(),
        defaults: UserDefaults = .standard,
        backend: CloudKitBackendService? = nil,
        appleSignIn: AppleSignInAuthenticating = AppleSignInService.shared
    ) {
        let persistence = persistence ?? Self.makeDefaultPersistence()
        self.persistence = persistence
        self.preferences = preferences
        self.defaults = defaults
        self.appleSignIn = appleSignIn

        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: CloudKitPermissionAuthorizer(persistence: persistence)
        )
        let backend = backend ?? CloudKitBackendService(persistence: persistence)
        self.repository = repository
        self.backend = backend
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
        cartSyncCancellable = cartSync.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        cartContentCancellable = cartContent.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        invitePreparerCancellable = invitePreparer.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
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
        case .appear, .foreground:
            await archiveStalePurchasedIfNeeded()
        case .pull, .cloudImport, .afterToggle, .afterMutation:
            break
        }
    }

    func dismissSharedCartRemovedMessage() {
        sharedCartRemovedMessage = nil
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
