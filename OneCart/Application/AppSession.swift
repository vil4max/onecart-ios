import AuthenticationServices
import Combine
import CoreData
import Foundation
import SwiftUI

/// Compatibility alias while Views migrate to AppSession.
typealias AppModel = AppSession

final class DevicePreferences: ObservableObject {
    @Published var participantDisplayName: String {
        didSet {
            defaults.set(
                participantDisplayName.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: Keys.participantDisplayName
            )
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        participantDisplayName = defaults.string(
            forKey: Keys.participantDisplayName
        ) ?? ""
    }

    func reloadFromDefaults() {
        participantDisplayName = defaults.string(
            forKey: Keys.participantDisplayName
        ) ?? ""
    }

    private enum Keys {
        static let participantDisplayName = "onecart.participant-display-name"
    }
}

enum InviteLinkError: LocalizedError {
    case notOwner
    case offline

    var errorDescription: String? {
        switch self {
        case .notOwner:
            String(localized: "sync.invite_owner_only")
        case .offline:
            String(localized: "sync.invite_need_network")
        }
    }
}

enum WelcomePhase: Equatable {
    case signIn
    case connecting
    case failed(String)
}

@MainActor
// RC05: AppSession is the Level 1 MVVM composition root (auth, sync, household selection).
final class AppSession: ObservableObject {

    nonisolated static let defaultFamilyName = String(
        localized: "cart.default_title",
        defaultValue: "Shopping list"
    )

    @Published private(set) var isReady = false
    @Published private(set) var isBusy = false
    @Published private(set) var needsWelcome = false
    @Published private(set) var welcomePhase: WelcomePhase = .signIn
    @Published private(set) var account: OneCartAccount?
    @Published private(set) var syncState: OneCartSyncState = .synchronized
    @Published private(set) var lastSyncError: String?
    @Published private(set) var familySpaces: [FamilySpace] = []
    @Published private(set) var activeFamilySpace: FamilySpace?
    @Published private(set) var familyMembers: [FamilyMember] = []
    @Published private(set) var access: FamilyAccess?
    @Published private(set) var isFamilyMetadataLoading = false
    @Published private(set) var isEnsuringHouseholdCart = false
    @Published private(set) var householdCartBootstrapFailed = false
    @Published var preferredMainTab: MainTab?
    @Published var alertMessage: String?
    @Published private(set) var preparedInviteLink: FamilyInviteLink?
    @Published private(set) var sharedCartRemovedMessage: String?

    let preferences: DevicePreferences
    let persistence: PersistenceController
    let cartSync: CartSyncService
    let cartContent: CartContentStore
    let bootstrapper: SessionBootstrapper
    let cloudSync: CloudSyncCoordinator

    var lists: [ShoppingListEntity] { cartContent.lists }
    var activeLists: [ShoppingListEntity] { cartContent.activeLists }
    var products: [ProductEntity] { cartContent.products }
    var productsByListID: [UUID: [ProductEntity]] { cartContent.productsByListID }
    var history: [PurchaseHistoryEntity] { cartContent.history }
    var historyHasMore: Bool { cartContent.historyHasMore }

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

    private let repository: FamilySpaceRepository
    private let backend: CloudKitBackendService
    private let shareOrchestrator: FamilyShareOrchestrator
    private let appleSignIn: AppleSignInAuthenticating
    private let defaults: UserDefaults
    private var online = true
    private var started = false
    private var invitePrepareTask: Task<Void, Never>?
    private var preparedInviteFamilyID: UUID?
    private var didPresentProductionSchemaAlert = false
    private var lastActiveFamilyWasShared = false
    private var cartSyncCancellable: AnyCancellable?
    private var cartContentCancellable: AnyCancellable?

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
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            isReady = true
        }
        bootstrapper.bind(host: self)
        cloudSync.bind(host: self)
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
            await self?.handleInviteeSharedCartGoneIfNeeded()
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

    func deleteCurrentCartAndStartFresh() async {
        guard let account,
              let family = activeFamilySpace,
              access?.isOwner == true
        else {
            CartSyncLog.action.error("deleteCart denied missingOwnerOrFamily")
            return
        }
        guard online else {
            CartSyncLog.action.error("deleteCart denied offline")
            presentAlert(String(localized: "alert.delete_cart_need_network"))
            return
        }
        CartSyncLog.action.info("deleteCart session begin")
        isBusy = true
        defer { isBusy = false }
        do {
            let cartName = Self.householdCartName(for: account)
            let newID = try await shareOrchestrator.deleteCurrentCartAndStartFresh(
                family: family,
                accountID: account.id,
                defaultFamilyName: cartName
            )
            clearPreparedInviteLink()
            defaults.set(newID.uuidString, forKey: activeFamilyKey(accountID: account.id))
            try reload(preferredFamilySpaceID: newID)
            await refreshFamilyMetadata(showErrors: false)
            scheduleInviteLinkPreparation(delayNanoseconds: 1_500_000_000)
            CartSyncLog.action.info("deleteCart session done")
            presentAlert(String(localized: "account.recreate_cart_done \(cartName)"))
        } catch {
            CartSyncLog.action.error(
                "deleteCart session fail error=\(error.localizedDescription, privacy: .public)"
            )
            show(error)
        }
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
        guard let account else {
            if activeFamilySpace == nil {
                householdCartBootstrapFailed = true
            }
            CartSyncLog.action.error("ensureHousehold denied noAccount")
            return
        }
        guard activeFamilySpace == nil else {
            householdCartBootstrapFailed = false
            return
        }
        guard !isEnsuringHouseholdCart else {
            CartSyncLog.action.info("ensureHousehold skip alreadyRunning")
            return
        }

        CartSyncLog.action.info("ensureHousehold start")
        isEnsuringHouseholdCart = true
        householdCartBootstrapFailed = false
        defer { isEnsuringHouseholdCart = false }

        do {
            await acceptPendingCloudKitShares()
            guard !Task.isCancelled else { return }
            try reload()
            if activeFamilySpace != nil {
                CartSyncLog.action.info("ensureHousehold done afterAccept")
                return
            }

            if familySpaces.isEmpty {
                CartSyncLog.action.info("ensureHousehold create empty")
                _ = try await repository.createFamilySpace(
                    name: Self.householdCartName(for: account),
                    cachedForUserID: account.id,
                    isHouseholdDefault: true
                )
                guard !Task.isCancelled else { return }
                try reload()
            } else {
                CartSyncLog.action.info("ensureHousehold offerSharedJoin count=\(self.familySpaces.count)")
                try await offerSharedCartJoinIfNeeded(for: account)
                guard !Task.isCancelled else { return }
            }

            if activeFamilySpace == nil {
                householdCartBootstrapFailed = true
                CartSyncLog.action.error("ensureHousehold fail noActiveFamily")
                return
            }

            await refreshFamilyMetadata(showErrors: false)
            scheduleInviteLinkPreparation()
            CartSyncLog.action.info(
                "ensureHousehold done family=\(self.activeFamilySpace?.id?.uuidString ?? "-", privacy: .public)"
            )
        } catch {
            guard !Task.isCancelled else { return }
            householdCartBootstrapFailed = true
            CartSyncLog.action.error(
                "ensureHousehold fail error=\(error.localizedDescription, privacy: .public)"
            )
            show(error)
        }
    }

    func retryHouseholdCartBootstrap() async {
        householdCartBootstrapFailed = false
        await ensureHouseholdCartIfNeeded()
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

    func setActiveFamilySpace(_ space: FamilySpace) {
        guard let id = space.id, let account else { return }
        defaults.set(id.uuidString, forKey: activeFamilyKey(accountID: account.id))
        do {
            try reload(preferredFamilySpaceID: id)
            Task { await refreshFamilyMetadata(showErrors: false) }
        } catch {
            show(error)
        }
    }

    func createFamilySpace(name: String) async {
        guard let account else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let id = try await repository.createFamilySpace(
                name: name,
                cachedForUserID: account.id,
                serverRole: FamilyAccess.owner.rawValue,
                needsRemoteCreation: false
            )
            defaults.set(id.uuidString, forKey: activeFamilyKey(accountID: account.id))
            try reload(preferredFamilySpaceID: id)
        } catch {
            show(error)
        }
    }

    func addProduct(to list: ShoppingListEntity, draft: ProductDraft) async {
        guard let listID = list.id else { return }
        CartSyncLog.action.info("addProduct start name=\(draft.name, privacy: .public)")
        await performMutation(action: "addProduct", successMessage: String(localized: "alert.product_added")) {
            try await self.repository.addProduct(
                to: listID,
                draft: draft,
                purchasedByName: self.preferences.participantDisplayName.nilIfBlank
                    ?? self.account?.displayName
            )
        }
    }

    func updateProduct(_ product: ProductEntity, draft: ProductDraft) async {
        guard let id = product.id else { return }
        CartSyncLog.action.info("updateProduct start id=\(id.uuidString, privacy: .public)")
        await performMutation(action: "updateProduct", successMessage: String(localized: "alert.product_updated")) {
            try await self.repository.updateProduct(id: id, draft: draft)
        }
    }

    func togglePurchased(_ product: ProductEntity) async {
        guard let id = product.id else { return }
        guard canEdit else {
            CartSyncLog.cart.error("togglePurchased denied canEdit=false")
            CartSyncLog.action.error("togglePurchased denied canEdit=false")
            presentAlert(RepositoryError.permissionDenied.localizedDescription)
            return
        }

        do {
            CartSyncLog.cart.info("togglePurchased start id=\(id.uuidString, privacy: .public)")
            CartSyncLog.action.info("togglePurchased start id=\(id.uuidString, privacy: .public)")
            try await repository.togglePurchased(
                id: id,
                participantDisplayName: preferences.participantDisplayName.nilIfBlank
                    ?? account?.displayName
            )
            await persistence.container.viewContext.perform {
                self.persistence.container.viewContext.processPendingChanges()
            }
            try refreshProducts()
            cartSync.bumpRevisionAfterLocalChange()
            CartSyncLog.cart.info(
                "togglePurchased done purchased=\(self.products.filter(\.isPurchasedValue).count)/\(self.products.count)"
            )
            CartSyncLog.action.info("togglePurchased done")
        } catch {
            CartSyncLog.cart.error("togglePurchased failed error=\(error.localizedDescription, privacy: .public)")
            CartSyncLog.action.error(
                "togglePurchased fail error=\(error.localizedDescription, privacy: .public)"
            )
            show(error)
        }
    }

    func products(inListID listID: UUID) -> [ProductEntity] {
        cartContent.products(inListID: listID)
    }

    func deleteProduct(_ product: ProductEntity) async {
        guard let id = product.id else { return }
        CartSyncLog.action.info("deleteProduct start id=\(id.uuidString, privacy: .public)")
        await performMutation(action: "deleteProduct", successMessage: String(localized: "alert.product_deleted")) {
            try await self.repository.deleteProduct(id: id)
        }
    }

    func completePurchasedItems(_ list: ShoppingListEntity) async {
        guard let id = list.id else { return }
        CartSyncLog.action.info("completePurchase start list=\(id.uuidString, privacy: .public)")
        await performMutation(action: "completePurchase", successMessage: String(localized: "alert.purchase_completed")) {
            _ = try await self.repository.completePurchased(listID: id)
        }
    }

    func deleteHistory(_ entry: PurchaseHistoryEntity) async {
        guard let id = entry.id else { return }
        CartSyncLog.action.info("deleteHistory start id=\(id.uuidString, privacy: .public)")
        await performMutation(action: "deleteHistory", successMessage: String(localized: "alert.history_deleted")) {
            try await self.repository.deleteHistory(id: id)
        }
    }

    func loadMoreHistory() {
        guard let familySpaceID = activeFamilySpace?.id else { return }
        do {
            try cartContent.loadMoreHistory(familySpaceID: familySpaceID)
        } catch {
            show(error)
        }
    }

    /// Creates a CloudKit invite URL. Does not toggle `isBusy` — callers show local progress
    /// so the invite UI stays responsive instead of looking frozen.
    /// Prefers a link prepared in the background right after household cart creation.
    func createFamilyInviteLink() async throws -> FamilyInviteLink {
        guard let family = activeFamilySpace,
              let familyID = family.id,
              access?.isOwner == true
        else {
            CartSyncLog.action.error("shareInvite denied notOwner")
            throw InviteLinkError.notOwner
        }
        guard online else {
            CartSyncLog.action.error("shareInvite denied offline")
            throw InviteLinkError.offline
        }

        if let preparedInviteLink,
           preparedInviteFamilyID == familyID,
           preparedInviteLink.expiresAt > Date().addingTimeInterval(30)
        {
            CartSyncLog.action.info("shareInvite cacheHit")
            return preparedInviteLink
        }

        CartSyncLog.action.info("shareInvite start family=\(familyID.uuidString, privacy: .public)")
        let link = try await fetchFamilyInviteLink(for: family)
        preparedInviteLink = link
        preparedInviteFamilyID = familyID
        CartSyncLog.action.info(
            "shareInvite done host=\(link.url.host ?? "-", privacy: .public)"
        )
        return link
    }

    /// Background CKShare warm-up after cart creation. Failures are silent — Invite retries.
    func scheduleInviteLinkPreparation(delayNanoseconds: UInt64 = 1_500_000_000) {
        invitePrepareTask?.cancel()
        invitePrepareTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await prepareInviteLinkInBackground()
        }
    }

    private func prepareInviteLinkInBackground() async {
        guard online else { return }
        guard let family = activeFamilySpace,
              let familyID = family.id,
              access?.isOwner == true,
              persistence.scope(for: family) == .private
        else {
            return
        }
        if let preparedInviteLink,
           preparedInviteFamilyID == familyID,
           preparedInviteLink.expiresAt > Date().addingTimeInterval(30)
        {
            return
        }

        do {
            let link = try await fetchFamilyInviteLink(for: family)
            guard !Task.isCancelled else { return }
            guard activeFamilySpace?.id == familyID else { return }
            preparedInviteLink = link
            preparedInviteFamilyID = familyID
        } catch {
            // Keep Invite button as the explicit retry path.
        }
    }

    private func fetchFamilyInviteLink(for family: FamilySpace) async throws -> FamilyInviteLink {
        try await shareOrchestrator.createInviteLink(for: family)
    }

    private func clearPreparedInviteLink() {
        invitePrepareTask?.cancel()
        invitePrepareTask = nil
        preparedInviteLink = nil
        preparedInviteFamilyID = nil
    }

    func acceptPendingCloudKitShares() async {
        guard persistence.isLoaded else { return }
        let metadata = AppDelegate.takePendingShareMetadata()
        guard !metadata.isEmpty else { return }
        isBusy = true
        syncState = .syncing
        defer { isBusy = false }
        do {
            try await persistence.acceptShareInvitations(from: metadata)
            syncState = .synchronized
            try reload()
            if let account {
                try await offerSharedCartJoinIfNeeded(for: account)
            }
            cloudSync.scheduleCloudReload(delayNanoseconds: 350_000_000)
        } catch {
            AppDelegate.requeue(metadata)
            syncState = .failed
            lastSyncError = userFacingMessage(for: error)
            show(error)
        }
    }

    func removeMember(_ member: FamilyMember) async {
        guard let family = activeFamilySpace,
              access?.isOwner == true,
              !member.isCurrentUser else { return }
        guard online else {
            presentAlert(String(localized: "alert.members_need_network"))
            return
        }

        CartSyncLog.action.info("removeMember start id=\(member.id.uuidString, privacy: .public)")
        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.removeMember(member, from: family)
            await refreshFamilyMetadata(showErrors: false)
            CartSyncLog.action.info("removeMember done")
        } catch {
            CartSyncLog.action.error(
                "removeMember fail error=\(error.localizedDescription, privacy: .public)"
            )
            show(error)
        }
    }

    func leaveCurrentFamily() async {
        guard account != nil,
              let family = activeFamilySpace,
              access?.isParticipant == true else { return }
        guard online else {
            presentAlert(String(localized: "alert.leave_need_network"))
            return
        }

        CartSyncLog.action.info(
            "leaveFamily start family=\(family.id?.uuidString ?? "-", privacy: .public)"
        )
        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.leaveFamily(family)
            cloudSync.scheduleCloudReload(delayNanoseconds: 350_000_000)
            CartSyncLog.action.info("leaveFamily done")
        } catch {
            CartSyncLog.action.error(
                "leaveFamily fail error=\(error.localizedDescription, privacy: .public)"
            )
            show(error)
        }
    }

    func refreshFromServer() async {
        await syncCart(reason: .pull)
    }

    func showFamilyManagement() {
        preferredMainTab = .account
        Task { await refreshFamilyMetadata(showErrors: true) }
    }

    func refreshAccountSharing() async {
        await refreshFamilyMetadata(showErrors: false)
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

    /// Ensures one household cart. Shared invite replaces the local private cart.
    func finishFamilyCartSetup(for account: OneCartAccount) async throws {
        try reload()
        if familySpaces.isEmpty {
            _ = try await repository.createFamilySpace(
                name: Self.householdCartName(for: account),
                cachedForUserID: account.id,
                isHouseholdDefault: true
            )
            try reload()
        }
        try await offerSharedCartJoinIfNeeded(for: account)
    }

    private func preferredSharedFamilyID() -> UUID? {
        familySpaces.first { persistence.scope(for: $0) == .shared }?.id
    }

    func offerSharedCartJoinIfNeeded(for account: OneCartAccount) async throws {
        try await adoptSharedFamilyCartIfNeeded(for: account)
    }

    private func adoptSharedFamilyCartIfNeeded(for account: OneCartAccount) async throws {
        try reload()
        guard let sharedFamily = familySpaces.first(where: {
            persistence.scope(for: $0) == .shared
        }), let sharedID = sharedFamily.id else {
            return
        }

        let privateFamilies = familySpaces.filter {
            persistence.scope(for: $0) == .private
                && $0.cachedForUserID == account.id
        }

        for privateFamily in privateFamilies {
            guard let privateID = privateFamily.id,
                  let scope = persistence.scope(for: privateFamily) else { continue }
            if FamilyCartMerge.isDeletableStarter(privateFamily, scope: scope) {
                try await repository.archiveFamilySpace(id: privateID)
                continue
            }
            try await repository.mergeFamilyContent(from: privateID, into: sharedID)
        }

        defaults.set(
            sharedID.uuidString,
            forKey: activeFamilyKey(accountID: account.id)
        )
        try reload(preferredFamilySpaceID: sharedID)
    }

    private func clearAccountData() {
        clearPreparedInviteLink()
        familySpaces = []
        activeFamilySpace = nil
        cartContent.clearContent()
        familyMembers = []
        access = nil
        householdCartBootstrapFailed = false
        isEnsuringHouseholdCart = false
    }

    private func performMutation(
        action: String,
        successMessage: String?,
        operation: @escaping () async throws -> Void
    ) async {
        _ = successMessage
        guard canEdit else {
            CartSyncLog.action.error("\(action) denied canEdit=false")
            presentAlert(RepositoryError.permissionDenied.localizedDescription)
            return
        }

        do {
            try await operation()
            await persistence.container.viewContext.perform {
                self.persistence.container.viewContext.processPendingChanges()
            }
            try reload()
            cartSync.bumpRevisionAfterLocalChange()
            CartSyncLog.action.info("\(action) done")
        } catch {
            CartSyncLog.action.error(
                "\(action) fail error=\(error.localizedDescription, privacy: .public)"
            )
            show(error)
        }
    }

    private func reload(preferredFamilySpaceID: UUID? = nil) throws {
        guard let account else {
            clearAccountData()
            return
        }

        let context = persistence.container.viewContext
        context.processPendingChanges()
        let previousID = activeFamilySpace?.id
        familySpaces = try repository.fetchFamilySpaces(for: account.id)

        let storedID = preferredFamilySpaceID
            ?? defaults.string(forKey: activeFamilyKey(accountID: account.id))
            .flatMap(UUID.init(uuidString:))
        let selected = storedID.flatMap { id in
            familySpaces.first { $0.id == id }
        } ?? familySpaces.first(where: {
            persistence.scope(for: $0) == .shared
        }) ?? familySpaces.first

        activeFamilySpace = selected
        if let selected {
            lastActiveFamilyWasShared = persistence.scope(for: selected) == .shared
        } else {
            lastActiveFamilyWasShared = false
        }
        if let selectedID = selected?.id {
            defaults.set(
                selectedID.uuidString,
                forKey: activeFamilyKey(accountID: account.id)
            )
            try cartContent.reloadContent(familySpaceID: selectedID)
            if let selected {
                access = backend.access(for: selected)
            } else {
                access = nil
            }
            if previousID != selectedID {
                familyMembers = []
            }
            if let preparedInviteFamilyID, preparedInviteFamilyID != selectedID {
                clearPreparedInviteLink()
            } else if preparedInviteLink != nil,
                      (access?.isOwner != true
                          || selected.map { persistence.scope(for: $0) } != .private)
            {
                clearPreparedInviteLink()
            }
        } else {
            defaults.removeObject(forKey: activeFamilyKey(accountID: account.id))
            cartContent.clearContent()
            familyMembers = []
            access = nil
            clearPreparedInviteLink()
        }
    }

    private func refreshProducts() throws {
        guard let selectedID = activeFamilySpace?.id else { return }
        try cartContent.refreshProducts(familySpaceID: selectedID)
    }

    func refreshFamilyMetadata(showErrors: Bool) async {
        guard let account, online else { return }
        isFamilyMetadataLoading = true
        defer { isFamilyMetadataLoading = false }
        do {
            if let family = activeFamilySpace {
                familyMembers = try backend.familyMembers(for: family, account: account)
            } else {
                familyMembers = []
            }
        } catch {
            if showErrors { show(error) }
        }
    }

    func installCloudObservers() {
        cloudSync.installCloudObservers()
    }

    private func handleInviteeSharedCartGoneIfNeeded() async {
        guard let account else { return }
        let hasShared = familySpaces.contains { persistence.scope(for: $0) == .shared }
        guard !hasShared, lastActiveFamilyWasShared || access?.isParticipant == true else { return }

        let privateFamily = familySpaces.first {
            persistence.scope(for: $0) == .private && $0.cachedForUserID == account.id
        }
        if let privateID = privateFamily?.id {
            defaults.set(privateID.uuidString, forKey: activeFamilyKey(accountID: account.id))
            try? reload(preferredFamilySpaceID: privateID)
        } else if activeFamilySpace == nil {
            do {
                let newID = try await repository.createFamilySpace(
                    name: Self.householdCartName(for: account),
                    cachedForUserID: account.id,
                    isHouseholdDefault: true
                )
                defaults.set(newID.uuidString, forKey: activeFamilyKey(accountID: account.id))
                try reload(preferredFamilySpaceID: newID)
            } catch {
                show(error)
                return
            }
        }
        lastActiveFamilyWasShared = false
        if sharedCartRemovedMessage == nil {
            sharedCartRemovedMessage = String(localized: "cart.shared_removed_message")
        }
        CartSyncLog.cart.info("invitee shared cart gone; fell back to private")
    }

    func installConnectivityMonitor() {
        cloudSync.installConnectivityMonitor()
    }

    private func activeFamilyKey(accountID: UUID) -> String {
        "onecart.active-family-space-id.\(accountID.uuidString)"
    }

    private func show(_ error: Error) {
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
