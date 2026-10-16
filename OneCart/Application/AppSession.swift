import AuthenticationServices
import CoreData
import Foundation
import SwiftUI

/// The observable session state and the root that builds the collaborators over it. State only
/// this file writes is `private(set)`; the rest is set by the session's extensions (Swift scopes
/// `private(set)` to the file), by the DEBUG demo or by tests.
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
    private(set) var familySpaces: [FamilySpace] = []
    private(set) var activeFamilySpace: FamilySpace?
    var familyMembers: [FamilyMember] = []
    var access: FamilyAccess?
    var isFamilyMetadataLoading = false
    private(set) var preferredMainTab: MainTab?
    private(set) var userAlert: UserAlert?
    var isDeletingAccount = false
    /// Backs `isBusy` for operations that may overlap, so the first one to finish
    /// does not clear the flag while another is still running.
    private(set) var busyOperationCount = 0

    /// The collaborators the composition root built; `AppSession+Dependencies.swift` forwards
    /// the ones the session uses as they are.
    let dependencies: AppSessionDependencies
    let cartContent: CartContentStore
    let invitePreparer: InviteLinkPreparer
    let shoppingTrip: ShoppingTripActivityController
    let shareOrchestrator: FamilyShareOrchestrator
    /// Family spaces: reads, rename, claim, and the local discard of a left shared cart.
    let repository: any FamilyRepository
    let cartItems: any CartItemsRepository
    let purchaseArchiver: any PurchaseArchiver
    let cartDeduplicator: any CartDeduplicator
    let memberProfiles: any MemberProfileStore
    let personalCartRestorer: any PersonalCartRestorer
    var startupTask: Task<Void, Never>?
    /// This user's CloudKit record name once iCloud reported it; keys the shared member profile.
    /// Read under an identity generation, so an iCloud account change hides it without an observer.
    var knownUserRecordName: (name: String, generation: UInt64)?
    /// Mirrors `MemberNamePromptStorage` so the root view observes the "Not now" choice.
    private(set) var memberNamePromptDeclined = false
    /// The latest queued member-profile publish; tests await it.
    var memberProfileTask: Task<Void, Never>?
    var online = true
    var started = false
    private(set) var didPresentProductionSchemaAlert = false

    // The collaborators below take the session in `init` as their context protocol, so they are
    // built on first use, once the session exists; each holds it weakly.
    @ObservationIgnored private(set) lazy var cartSync = CartSyncService(
        persistence: persistence,
        clock: clock,
        refresher: self
    )
    @ObservationIgnored private(set) lazy var cloudSync = CloudSyncCoordinator(
        persistence: persistence,
        cartSync: cartSync,
        connectivity: dependencies.connectivity,
        clock: clock,
        context: self
    )
    @ObservationIgnored private(set) lazy var household = HouseholdCartCoordinator(
        context: self,
        persistence: persistence,
        families: repository,
        personalCartRestorer: personalCartRestorer,
        defaults: defaults
    )
    @ObservationIgnored private(set) lazy var bootstrapper = SessionBootstrapper(
        dependencies: SessionBootstrapDependencies(
            persistence: persistence,
            deduplicator: cartDeduplicator,
            cloudSharing: cloudSharing,
            appleSignIn: appleSignIn,
            preferences: preferences,
            cartSync: cartSync
        )
    )
    @ObservationIgnored private(set) lazy var cartMutations = CartMutationService(
        context: self,
        dependencies: CartMutationDependencies(
            persistence: persistence,
            cartItems: cartItems,
            purchaseArchiver: purchaseArchiver,
            deduplicator: cartDeduplicator,
            categoryClassifier: categoryClassifier,
            cartContent: cartContent,
            cartSync: cartSync,
            household: household,
            clock: clock
        )
    )
    @ObservationIgnored private(set) lazy var widgetSync = WidgetPurchaseSync(
        context: self,
        dependencies: WidgetPurchaseDependencies(
            widgetStore: widgetStore,
            shoppingTrip: shoppingTrip,
            cartContent: cartContent,
            cartItems: cartItems,
            cartSync: cartSync,
            mutations: cartMutations
        )
    )
    @ObservationIgnored private(set) lazy var intentHandler = CartIntentHandler(
        context: self,
        mutations: cartMutations,
        widgetSync: widgetSync,
        cartContent: cartContent,
        shoppingTrip: shoppingTrip
    )
    @ObservationIgnored private(set) lazy var membership = MembershipService(
        context: self,
        dependencies: MembershipDependencies(
            persistence: persistence,
            cloudSharing: cloudSharing,
            families: repository,
            shareOrchestrator: shareOrchestrator,
            invitePreparer: invitePreparer,
            household: household,
            clock: clock
        )
    )
    @ObservationIgnored private(set) lazy var accountDeletion = AccountDeletionService(
        context: self,
        dependencies: AccountDeletionDependencies(
            persistence: persistence,
            cloudSharing: cloudSharing,
            families: repository,
            household: household,
            localStores: accountLocalStorePreparer,
            cloudData: accountCloudDataDeleter,
            widgetStore: widgetStore
        )
    )

    /// Builds the repositories and the collaborators that need no session over the injected
    /// ones; it creates no live service of its own (see `OneCartAppComposition.live()`).
    init(_ dependencies: AppSessionDependencies) {
        let persistence = dependencies.persistence
        let repositories = Self.makeRepositories(dependencies)
        self.dependencies = dependencies
        shoppingTrip = ShoppingTripActivityController(backend: dependencies.shoppingTripBackend)
        repository = repositories.families
        cartItems = repositories.cartItems
        purchaseArchiver = repositories.purchaseArchiver
        cartDeduplicator = repositories.deduplicator
        memberProfiles = repositories.memberProfiles
        personalCartRestorer = repositories.personalCartRestorer
        memberNamePromptDeclined = MemberNamePromptStorage.isDeclined(in: dependencies.defaults)
        cartContent = CartContentStore(persistence: persistence)
        shareOrchestrator = FamilyShareOrchestrator(
            persistence: persistence,
            shareStore: dependencies.shareStore,
            cloudSharing: dependencies.cloudSharing
        )
        invitePreparer = InviteLinkPreparer(clock: dependencies.clock)
        dependencies.preferences.onChanged = { [weak self] in
            self?.updateWidgetSnapshot()
        }
        dependencies.preferences.onAccentChanged = { [weak self] newAccent in
            self?.updateWidgetSnapshot(accentOverride: newAccent)
        }
    }
}

extension AppSession {
    private static func makeRepositories(_ dependencies: AppSessionDependencies) -> FamilySpaceRepository {
        FamilySpaceRepository(
            persistence: dependencies.persistence,
            permissionAuthorizer: CloudKitPermissionAuthorizer(
                persistence: dependencies.persistence,
                permissions: dependencies.recordPermissions
            ),
            clock: dependencies.clock
        )
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
}

// MARK: - Active cart

extension AppSession {
    /// `endingShoppingTrip` is false when nobody signed out: a failed startup or a reload before
    /// the account is restored keeps the trip for the next start to adopt (REQ-WIDGET-060).
    func clearAccountData(endingShoppingTrip: Bool = true) {
        clearPreparedInviteLink()
        cartMutations.cancelAllCategoryRefinements()
        membership.cancelLeaveRecovery()
        familySpaces = []
        activeFamilySpace = nil
        cartContent.clearContent()
        familyMembers = []
        access = nil
        household.reset()
        // Sign out and account deletion end the trip (REQ-WIDGET-060). Queued even without an
        // active trip: a start still waiting in the queue has no active trip yet.
        if endingShoppingTrip {
            shoppingTrip.end()
        }
    }

    func reload(preferredFamilySpaceID: UUID? = nil) throws {
        guard let account else {
            clearAccountData(endingShoppingTrip: false)
            return
        }

        let context = persistence.container.viewContext
        context.processPendingChanges()
        let previousID = activeFamilySpace?.id
        let selected = try fetchAndSelectFamilySpace(for: account, preferredID: preferredFamilySpaceID)
        activeFamilySpace = selected
        if let selected, persistence.scope(for: selected) == .shared {
            household.rememberSharedCartSelected()
        }
        if let selected, let selectedID = selected.id {
            defaults.set(
                selectedID.uuidString,
                forKey: activeFamilyKey(accountID: account.id)
            )
            try cartContent.reloadContent(familySpaceID: selectedID)
            access = cloudSharing.access(for: selected)
            if previousID != selectedID {
                familyMembers = []
            }
            if invitePreparer.shouldClearCache(forSelectedFamilyID: selectedID) {
                clearPreparedInviteLink()
            }
        } else {
            defaults.removeObject(forKey: activeFamilyKey(accountID: account.id))
            cartContent.clearContent()
            familyMembers = []
            access = nil
            clearPreparedInviteLink()
        }
        updateWidgetSnapshot()
    }

    /// Fetches the account's spaces into `familySpaces`, where shared spaces hide the personal
    /// cart, and picks the preferred or stored one among them, else the first.
    private func fetchAndSelectFamilySpace(for account: OneCartAccount, preferredID: UUID?) throws -> FamilySpace? {
        let fetchedSpaces = try repository.fetchFamilySpaces(for: account.id)
        let sharedSpaces = fetchedSpaces.filter { persistence.scope(for: $0) == .shared }
        familySpaces = sharedSpaces.isEmpty ? fetchedSpaces : sharedSpaces
        let storedID =
            preferredID
            ?? defaults.string(forKey: activeFamilyKey(accountID: account.id))
            .flatMap(UUID.init(uuidString:))
        return storedID.flatMap { id in
            familySpaces.first { $0.id == id }
        } ?? familySpaces.first
    }

    func refreshProducts() throws {
        guard let selectedID = activeFamilySpace?.id else { return }
        try cartContent.refreshProducts(familySpaceID: selectedID)
        updateWidgetSnapshot()
    }
}

// MARK: - Alerts, tabs and the name prompt

extension AppSession {
    func presentAlert(_ message: String, kind: UserAlertKind = .error, playHaptic: Bool = true) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        userAlert = UserAlert(kind: kind, message: trimmed)
        guard playHaptic else { return }
        switch kind {
        case .success:
            CartHaptics.success()
        case .error:
            CartHaptics.error()
        }
    }

    func dismissAlert() {
        userAlert = nil
    }

    func show(_ error: Error) {
        let message = userFacingMessage(for: error)
        if CloudKitUserFacingError.isProductionSchemaFailure(error) {
            presentProductionSchemaAlertIfNeeded(message)
            return
        }
        presentAlert(message, kind: .error)
    }

    func presentProductionSchemaAlertIfNeeded(_ message: String) {
        guard !didPresentProductionSchemaAlert else {
            CartHaptics.error()
            return
        }
        didPresentProductionSchemaAlert = true
        presentAlert(message, kind: .error)
    }

    func showFamilyManagement() {
        preferredMainTab = .account
        Task { await refreshFamilyMetadata(showErrors: true) }
    }

    func clearPreferredMainTab() {
        preferredMainTab = nil
    }

    func declineMemberNamePrompt() {
        MemberNamePromptStorage.markDeclined(in: defaults)
        memberNamePromptDeclined = true
    }
}
