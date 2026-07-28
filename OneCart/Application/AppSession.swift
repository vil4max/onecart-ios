import AuthenticationServices
import Combine
import CoreData
import Foundation
import SwiftUI

@MainActor
final class AppSession: ObservableObject {

    nonisolated static let defaultFamilyName = String(
        localized: "cart.default_title",
        defaultValue: "Shopping list"
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

    var lists: [ShoppingListEntity] { cartContent.lists }
    var activeLists: [ShoppingListEntity] { cartContent.activeLists }
    var products: [ProductEntity] { cartContent.products }
    var productsByListID: [UUID: [ProductEntity]] { cartContent.productsByListID }
    var history: [PurchaseHistoryEntity] { cartContent.history }
    var historyHasMore: Bool { cartContent.historyHasMore }

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

    static func householdCartName(for account: OneCartAccount) -> String {
        let name = account.displayName.nilIfBlank
            ?? String(localized: "common.default_user")
        return String(localized: "cart.owner_title \(name)")
    }

    let repository: FamilySpaceRepository
    let backend: CloudKitBackendService
    let shareOrchestrator: FamilyShareOrchestrator
    private let appleSignIn: AppleSignInAuthenticating
    let defaults: UserDefaults
    var online = true
    private var started = false
    private var didPresentProductionSchemaAlert = false
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
    }

    func dismissSharedCartRemovedMessage() {
        sharedCartRemovedMessage = nil
    }

    func start() async {
        guard !started else { return }
        started = true
        await bootstrapSession()
    }

    func retryStartup() async {
        await retryWelcome()
    }

    func ensureHouseholdCartIfNeeded() async {
        await household.ensureHouseholdCartIfNeeded()
    }

    func retryHouseholdCartBootstrap() async {
        await household.retryHouseholdCartBootstrap()
    }

    func retryWelcome() async {
        let previousPhase = welcomePhase
        await bootstrapper.retry(previousPhase: previousPhase)
    }

    func reportWelcomeFailure(_ message: String) {
        needsWelcome = true
        welcomePhase = .failed(message)
        isReady = true
    }

    func dismissWelcomeSignInAttempt() {
        needsWelcome = true
        welcomePhase = .signIn
        isReady = true
    }

    func completeAppleSignIn(authorization: ASAuthorization) async {
        needsWelcome = true
        welcomePhase = .connecting
        isReady = true
        isBusy = true
        defer { isBusy = false }
        do {
            let credential = try appleSignIn.makeCredential(from: authorization)
            appleSignIn.save(credential)
            if let providedName = credential.providedDisplayName {
                preferences.participantDisplayName = providedName
            }
            await bootstrapper.prepare(appleCredential: credential)
        } catch {
            needsWelcome = true
            if let localized = error as? LocalizedError,
               let description = localized.errorDescription?.nilIfBlank
            {
                welcomePhase = .failed(description)
            } else {
                welcomePhase = .failed(String(localized: "welcome.sign_in_failed"))
            }
        }
    }

    func signOut() {
        if let account {
            defaults.removeObject(forKey: activeFamilyKey(accountID: account.id))
        }
        appleSignIn.clearCredential()
        clearAccountData()
        account = nil
        alertMessage = nil
        needsWelcome = true
        welcomePhase = .signIn
        isReady = true
        started = true
    }

    private func bootstrapSession() async {
        await bootstrapper.start()
    }

    func createFamilyInviteLink() async throws -> FamilyInviteLink {
        guard let family = activeFamilySpace else {
            CartSyncLog.action.error("shareInvite denied notOwner")
            throw InviteLinkError.notOwner
        }
        return try await invitePreparer.createInviteLink(
            family: family,
            isOwner: access?.isOwner == true,
            isOnline: online,
            fetch: { [shareOrchestrator] in
                try await shareOrchestrator.createInviteLink(for: family)
            }
        )
    }

    func scheduleInviteLinkPreparation(delayNanoseconds: UInt64) {
        invitePreparer.schedulePreparation(
            delayNanoseconds: delayNanoseconds,
            isOnline: { [weak self] in self?.online == true },
            family: { [weak self] in self?.activeFamilySpace },
            isOwner: { [weak self] in self?.access?.isOwner == true },
            scopeIsPrivate: { [weak self] family in
                self?.persistence.scope(for: family) == .private
            },
            familyStillActive: { [weak self] familyID in
                self?.activeFamilySpace?.id == familyID
            },
            fetch: { [weak self] family in
                guard let self else { throw InviteLinkError.offline }
                return try await self.shareOrchestrator.createInviteLink(for: family)
            }
        )
    }

    func clearPreparedInviteLink() {
        invitePreparer.clear()
    }

    func presentAlert(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        alertMessage = trimmed
    }

    func dismissAlert() {
        alertMessage = nil
    }

    func bootstrapTestingSession(account: OneCartAccount) throws {
        self.account = account
        try reload()
    }

    func offerSharedCartJoinIfNeededForTesting() async throws {
        guard let account else { return }
        try await offerSharedCartJoinIfNeeded(for: account)
    }

    func finishFamilyCartSetup(for account: OneCartAccount) async throws {
        try await household.finishFamilyCartSetup(for: account)
    }

    func offerSharedCartJoinIfNeeded(for account: OneCartAccount) async throws {
        try await household.offerSharedCartJoinIfNeeded(for: account)
    }

    func installCloudObservers() {
        cloudSync.installCloudObservers()
    }

    func installConnectivityMonitor() {
        cloudSync.installConnectivityMonitor()
    }

    func activeFamilyKey(accountID: UUID) -> String {
        "onecart.active-family-space-id.\(accountID.uuidString)"
    }

    func show(_ error: Error) {
        let message = userFacingMessage(for: error)
        if CloudKitUserFacingError.isProductionSchemaFailure(error) {
            presentProductionSchemaAlertIfNeeded(message)
            return
        }
        presentAlert(message)
    }

    func presentProductionSchemaAlertIfNeeded(_ message: String) {
        guard !didPresentProductionSchemaAlert else { return }
        didPresentProductionSchemaAlert = true
        presentAlert(message)
    }

    func userFacingMessage(for error: Error) -> String {
        if error is OneCartCloudKitError {
            return CloudKitUserFacingError.message(for: error)
        }
        if CloudKitUserFacingError.isNetworkError(error) {
            return String(localized: "sync.network_deferred")
        }
        if PersistenceController.isUserFacingCoreDataFailure(error) {
            return String(localized: "welcome.core_data_failed")
        }
        return CloudKitUserFacingError.message(for: error)
    }

    private func isNetworkError(_ error: Error) -> Bool {
        CloudKitUserFacingError.isNetworkError(error)
    }
}

extension AppSession: HouseholdCartHost {
    func applyEnsuringHouseholdCart(_ value: Bool) {
        isEnsuringHouseholdCart = value
    }

    func applyHouseholdCartBootstrapFailed(_ value: Bool) {
        householdCartBootstrapFailed = value
    }

    func reloadHousehold(preferredFamilySpaceID: UUID?) throws {
        try reload(preferredFamilySpaceID: preferredFamilySpaceID)
    }

    func presentHouseholdError(_ error: Error) {
        show(error)
    }

    func scheduleInviteLinkPreparation() {
        scheduleInviteLinkPreparation(delayNanoseconds: 1_500_000_000)
    }

    func householdDisplayName(for account: OneCartAccount) -> String {
        Self.householdCartName(for: account)
    }
}

extension AppSession: CloudSyncHost {
    func applySyncState(_ state: OneCartSyncState) {
        syncState = state
    }

    func applyLastSyncError(_ message: String?) {
        lastSyncError = message
    }

    func presentSyncAlert(_ message: String) {
        presentAlert(message)
    }

    func softRefreshCartProducts() {
        do {
            try refreshProducts()
            cartSync.bumpRevisionAfterLocalChange()
            CartSyncLog.cart.info(
                "softRefresh purchased=\(self.products.filter(\.isPurchasedValue).count)/\(self.products.count)"
            )
        } catch {
            CartSyncLog.cart.error(
                "softRefresh failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func applyConnectivityOnline(_ isOnline: Bool) {
        online = isOnline
    }
}

extension AppSession: SessionBootstrapHost {
    func notifyBootstrapObjectWillChange() {
        objectWillChange.send()
    }

    func reloadAfterBootstrap() throws {
        try reload()
    }

    func applyBootstrapAccount(_ account: OneCartAccount) {
        self.account = account
    }

    func clearBootstrapAccount() {
        clearAccountData()
        account = nil
    }

    func applyBootstrapSyncState(_ state: OneCartSyncState) {
        syncState = state
    }

    func applyWelcomeSignIn() {
        needsWelcome = true
        welcomePhase = .signIn
        isReady = true
    }

    func applyWelcomeConnecting() {
        needsWelcome = true
        welcomePhase = .connecting
        isReady = true
    }

    func applyWelcomeFailed(_ message: String) {
        needsWelcome = true
        welcomePhase = .failed(message)
        isReady = true
    }

    func applyWelcomeReady(needsWelcome: Bool) {
        self.needsWelcome = needsWelcome
        if !needsWelcome {
            welcomePhase = .signIn
        }
        isReady = true
    }

    func clearStoredAppleCredential() {
        appleSignIn.clearCredential()
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
