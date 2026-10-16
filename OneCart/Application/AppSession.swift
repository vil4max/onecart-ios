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
    /// Backs `isBusy` for operations that may overlap, so the first one to finish
    /// does not clear the flag while another is still running.
    private(set) var busyOperationCount = 0

    /// The collaborators the composition root built; `AppSession+Dependencies.swift` forwards
    /// the ones the session uses as they are.
    let dependencies: AppSessionDependencies
    let cartSync: CartSyncService
    let cartContent: CartContentStore
    let bootstrapper: SessionBootstrapper
    let cloudSync: CloudSyncCoordinator
    let invitePreparer: InviteLinkPreparer
    let household: HouseholdCartCoordinator
    let shoppingTrip: ShoppingTripActivityController
    let shareOrchestrator: FamilyShareOrchestrator
    /// Family spaces: reads, rename, claim, and the local discard of a left shared cart.
    let repository: any FamilyRepository
    let cartItems: any CartItemsRepository
    let purchaseArchiver: any PurchaseArchiver
    let cartDeduplicator: any CartDeduplicator
    let memberProfiles: any MemberProfileStore
    var startupTask: Task<Void, Never>?
    /// This user's CloudKit record name once iCloud reported it; keys the shared member profile.
    /// Read under an identity generation, so an iCloud account change hides it without an observer.
    var knownUserRecordName: (name: String, generation: UInt64)?
    /// Mirrors `MemberNamePromptStorage` so the root view observes the "Not now" choice.
    var memberNamePromptDeclined = false
    /// The latest queued member-profile publish; tests await it.
    var memberProfileTask: Task<Void, Never>?
    /// Retries the fallback to the personal cart after a leave timed out; sign-out cancels it.
    var leaveRecoveryTask: Task<Void, Never>?
    /// Fallback passes run after a leave timed out; tests wait on it instead of yielding.
    var leaveRecoveryPassCount = 0
    var online = true
    var started = false
    var didPresentProductionSchemaAlert = false
    var lastActiveFamilyWasShared = false
    var isLeavingSharedCart = false

    // The cart services take the session as their context, so they are built on first use,
    // once the session exists.
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

    /// Builds the coordinators and repositories over the injected collaborators; it creates no
    /// live service of its own (see `OneCartAppComposition.live()`).
    init(_ dependencies: AppSessionDependencies) {
        let persistence = dependencies.persistence
        let clock = dependencies.clock
        let repositories = Self.makeRepositories(dependencies)
        self.dependencies = dependencies
        shoppingTrip = ShoppingTripActivityController(backend: dependencies.shoppingTripBackend)
        repository = repositories.families
        cartItems = repositories.cartItems
        purchaseArchiver = repositories.purchaseArchiver
        cartDeduplicator = repositories.deduplicator
        memberProfiles = repositories.memberProfiles
        memberNamePromptDeclined = MemberNamePromptStorage.isDeclined(in: dependencies.defaults)
        cartSync = CartSyncService(persistence: persistence, clock: clock)
        cartContent = CartContentStore(persistence: persistence)
        bootstrapper = SessionBootstrapper(
            persistence: persistence,
            families: repositories.families,
            deduplicator: repositories.deduplicator,
            cloudSharing: dependencies.cloudSharing,
            appleSignIn: dependencies.appleSignIn
        )
        cloudSync = CloudSyncCoordinator(
            persistence: persistence,
            cartSync: cartSync,
            connectivity: dependencies.connectivity,
            clock: clock
        )
        shareOrchestrator = FamilyShareOrchestrator(
            persistence: persistence,
            shareStore: dependencies.shareStore,
            cloudSharing: dependencies.cloudSharing
        )
        invitePreparer = InviteLinkPreparer(clock: clock)
        household = HouseholdCartCoordinator(
            persistence: persistence,
            families: repositories.families,
            personalCartRestorer: repositories.personalCartRestorer,
            defaults: dependencies.defaults
        )
        bindCollaborators()
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

    private func bindCollaborators() {
        bootstrapper.bind(host: self)
        cloudSync.bind(host: self)
        household.bind(host: self)
        cartSync.refresher = self
        preferences.onChanged = { [weak self] in
            self?.updateWidgetSnapshot()
        }
        preferences.onAccentChanged = { [weak self] newAccent in
            self?.updateWidgetSnapshot(accentOverride: newAccent)
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
}
