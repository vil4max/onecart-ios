import AuthenticationServices
import Combine
import CoreData
import Foundation
import Network
import SwiftUI
import UIKit

// Compatibility alias while Views migrate to AppSession.
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
            "Приглашать участников может только владелец корзины."
        case .offline:
            "Для создания ссылки подключитесь к интернету."
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
        defaultValue: "Список покупок"
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
    @Published private(set) var lists: [ShoppingListEntity] = []
    @Published private(set) var activeLists: [ShoppingListEntity] = []
    @Published private(set) var products: [ProductEntity] = []
    @Published private(set) var productsByListID: [UUID: [ProductEntity]] = [:]
    @Published private(set) var history: [PurchaseHistoryEntity] = []
    @Published private(set) var familyMembers: [FamilyMember] = []
    @Published private(set) var access: FamilyAccess?
    @Published private(set) var isFamilyMetadataLoading = false
    @Published var familyManagementPresented = false
    @Published var alertMessage: String?
    /// Pre-warmed CKShare invite for the active owner cart (filled after cart create).
    @Published private(set) var preparedInviteLink: FamilyInviteLink?
    @Published private(set) var profileAvatar: UIImage?
    @Published private(set) var profileBanner: UIImage?

    let preferences: DevicePreferences
    let persistence: PersistenceController

    var canEdit: Bool {
        activeFamilySpace != nil && (access?.canEdit ?? false)
    }

    var isOnline: Bool {
        online
    }

    private let repository: FamilySpaceRepository
    private let backend: CloudKitBackendService
    private let appleSignIn: AppleSignInAuthenticating
    private let migrationService: LegacyMigrationService
    private let legacySnapshotProvider: LegacySnapshotProviding
    private let defaults: UserDefaults
    private let connectivity = ConnectivityMonitor()
    private var online = true
    private var started = false
    private var remoteChangeObserver: NSObjectProtocol?
    private var cloudEventObserver: NSObjectProtocol?
    private var scheduledReloadTask: Task<Void, Never>?
    private var invitePrepareTask: Task<Void, Never>?
    private var preparedInviteFamilyID: UUID?
    /// Production-schema sync failure is sticky until Deploy; alert once per session.
    private var didPresentProductionSchemaAlert = false

    init(
        persistence: PersistenceController? = nil,
        preferences: DevicePreferences = DevicePreferences(),
        defaults: UserDefaults = .standard,
        legacySnapshotProvider: LegacySnapshotProviding = DefaultLegacySnapshotProvider(),
        backend: CloudKitBackendService? = nil,
        appleSignIn: AppleSignInAuthenticating = AppleSignInService.shared
    ) {
        let persistence = persistence ?? Self.makeDefaultPersistence()
        self.persistence = persistence
        self.preferences = preferences
        self.defaults = defaults
        self.legacySnapshotProvider = legacySnapshotProvider
        self.appleSignIn = appleSignIn

        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: CloudKitPermissionAuthorizer(persistence: persistence)
        )
        let backend = backend ?? CloudKitBackendService(persistence: persistence)
        self.repository = repository
        self.backend = backend
        migrationService = LegacyMigrationService(
            persistence: persistence,
            userDefaults: defaults
        )
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            isReady = true
        }
    }

    private static func makeDefaultPersistence() -> PersistenceController {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return PersistenceController(inMemory: true, cloudKitEnabled: false)
        }
        return .shared
    }

    deinit {
        scheduledReloadTask?.cancel()
        if let remoteChangeObserver {
            NotificationCenter.default.removeObserver(remoteChangeObserver)
        }
        if let cloudEventObserver {
            NotificationCenter.default.removeObserver(cloudEventObserver)
        }
        connectivity.stop()
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
        guard let account, activeFamilySpace == nil else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            await acceptPendingCloudKitShares()
            try reload()
            if familySpaces.isEmpty {
                _ = try await repository.createFamilySpace(
                    name: Self.defaultFamilyName,
                    cachedForUserID: account.id,
                    isHouseholdDefault: true
                )
                try reload()
            } else {
                try await adoptSharedFamilyCartIfNeeded(for: account)
            }
            await refreshFamilyMetadata(showErrors: false)
            scheduleInviteLinkPreparation()
        } catch {
            show(error)
        }
    }

    func retryWelcome() async {
        guard let credential = appleSignIn.storedCredential() else {
            needsWelcome = true
            welcomePhase = .signIn
            isReady = true
            return
        }
        let previousPhase = welcomePhase
        needsWelcome = true
        welcomePhase = .connecting
        isReady = true

        // Soft retry by default. Wipe local SQLite only when Core Data itself failed.
        if case let .failed(message) = previousPhase,
           message == String(localized: "welcome.core_data_failed")
        {
            do {
                try persistence.hardResetPersistentStores()
                objectWillChange.send()
            } catch {
                welcomePhase = .failed(userFacingMessage(for: error))
                return
            }
        }

        await prepareApplication(appleCredential: credential)
    }

    func reportWelcomeFailure(_ message: String) {
        needsWelcome = true
        welcomePhase = .failed(message)
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
            await prepareApplication(appleCredential: credential)
        } catch {
            welcomePhase = .failed(userFacingMessage(for: error))
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
        if let credential = appleSignIn.storedCredential() {
            let state = await appleSignIn.credentialState(for: credential.userID)
            switch state {
            case .authorized, .unknown:
                // `.unknown` can be transient at launch — keep the session and let
                // iCloud / prepareApplication report a real failure if needed.
                needsWelcome = false
                welcomePhase = .connecting
                await prepareApplication(appleCredential: credential)
                return
            case .revoked, .notFound:
                appleSignIn.clearCredential()
            }
        }

        needsWelcome = true
        welcomePhase = .signIn
        isReady = true
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
        await performMutation(successMessage: "Товар добавлен") {
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
        await performMutation(successMessage: "Товар обновлён") {
            try await self.repository.updateProduct(id: id, draft: draft)
        }
    }

    func togglePurchased(_ product: ProductEntity) async {
        guard let id = product.id else { return }
        guard canEdit else {
            presentAlert(RepositoryError.permissionDenied.localizedDescription)
            return
        }

        do {
            try await repository.togglePurchased(
                id: id,
                participantDisplayName: preferences.participantDisplayName.nilIfBlank
                    ?? account?.displayName
            )
            await persistence.container.viewContext.perform {
                self.persistence.container.viewContext.processPendingChanges()
            }
            try refreshProducts()
        } catch {
            show(error)
        }
    }

    func products(inListID listID: UUID) -> [ProductEntity] {
        productsByListID[listID] ?? []
    }

    func deleteProduct(_ product: ProductEntity) async {
        guard let id = product.id else { return }
        await performMutation(successMessage: "Товар удалён") {
            try await self.repository.deleteProduct(id: id)
        }
    }

    func completePurchasedItems(_ list: ShoppingListEntity) async {
        guard let id = list.id else { return }
        await performMutation(successMessage: "Отмеченное уехало в историю 📜") {
            _ = try await self.repository.completePurchased(listID: id)
        }
    }

    func deleteHistory(_ entry: PurchaseHistoryEntity) async {
        guard let id = entry.id else { return }
        await performMutation(successMessage: "Запись истории удалена") {
            try await self.repository.deleteHistory(id: id)
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
            throw InviteLinkError.notOwner
        }
        guard online else {
            throw InviteLinkError.offline
        }

        if let preparedInviteLink,
           preparedInviteFamilyID == familyID,
           preparedInviteLink.expiresAt > Date().addingTimeInterval(30)
        {
            return preparedInviteLink
        }

        let link = try await fetchFamilyInviteLink(for: family)
        preparedInviteLink = link
        preparedInviteFamilyID = familyID
        return link
    }

    /// Background CKShare warm-up after cart creation. Failures are silent — Invite retries.
    private func scheduleInviteLinkPreparation(delayNanoseconds: UInt64 = 1_500_000_000) {
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
        // Capture Core Data identifiers on MainActor, then leave it so ProgressView
        // keeps animating and a UI watchdog can cancel a stuck CloudKit call.
        let objectID = family.objectID
        let displayName = family.displayName
        let viewContext = persistence.container.viewContext
        if viewContext.hasChanges {
            try viewContext.save()
        }
        let backend = backend
        return try await Task.detached(priority: .userInitiated) {
            try await backend.createFamilyInviteLink(
                objectID: objectID,
                displayName: displayName
            )
        }.value
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
                try await adoptSharedFamilyCartIfNeeded(for: account)
            }
            scheduleCloudReload(delayNanoseconds: 350_000_000)
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
            presentAlert("Для изменения состава корзины подключитесь к интернету.")
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.removeMember(member, from: family)
            await refreshFamilyMetadata(showErrors: false)
        } catch {
            show(error)
        }
    }

    func leaveCurrentFamily() async {
        guard account != nil,
              let family = activeFamilySpace,
              access?.isParticipant == true else { return }
        guard online else {
            presentAlert("Чтобы покинуть корзину, подключитесь к интернету.")
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.leaveFamily(family)
            scheduleCloudReload(delayNanoseconds: 350_000_000)
        } catch {
            show(error)
        }
    }

    func refreshFromServer() async {
        do {
            try reload()
            await refreshFamilyMetadata(showErrors: true)
            syncState = online ? .synchronized : .offline
        } catch {
            show(error)
        }
    }

    /// Profile media stays on this device; CloudKit synchronizes only shopping data.
    @discardableResult
    func updateProfile(
        displayName: String,
        avatar: UIImage?,
        banner: UIImage?,
        removeAvatar: Bool,
        removeBanner: Bool
    ) async -> Bool {
        guard let account else { return false }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            presentAlert("Укажите имя")
            return false
        }

        isBusy = true
        defer { isBusy = false }

        do {
            // Mirror to disk immediately so Settings/Home show the new photo even
            // before the network round-trip finishes.
            if removeAvatar {
                ProfileMediaStore.remove(for: account.id, kind: .avatar)
            } else if let avatar {
                try ProfileMediaStore.save(avatar, for: account.id, kind: .avatar)
            }

            if removeBanner {
                ProfileMediaStore.remove(for: account.id, kind: .banner)
            } else if let banner {
                try ProfileMediaStore.save(banner, for: account.id, kind: .banner)
            }
            reloadProfileMedia(for: account.id)

            let updated = OneCartAccount(
                id: account.id,
                displayName: trimmed
            )

            self.account = updated
            preferences.participantDisplayName = updated.displayName
            reloadProfileMedia(for: updated.id)
            applyProfileToFamilyMembers(updated)
            objectWillChange.send()
            if familyManagementPresented {
                await refreshFamilyMetadata(showErrors: false)
            }
            return true
        } catch {
            // Local photos already saved — keep them and still close the editor.
            reloadProfileMedia(for: account.id)
            show(error)
            return false
        }
    }

    func showFamilyManagement() {
        familyManagementPresented = true
        Task { await refreshFamilyMetadata(showErrors: true) }
    }

    private func reloadProfileMedia(for userID: UUID) {
        profileAvatar = ProfileMediaStore.image(for: userID, kind: .avatar)
        profileBanner = ProfileMediaStore.image(for: userID, kind: .banner)
    }

    private func applyProfileToFamilyMembers(_ account: OneCartAccount) {
        familyMembers = familyMembers.map { member in
            guard member.isCurrentUser else { return member }
            return FamilyMember(
                id: member.id,
                displayName: account.displayName,
                access: member.access,
                joinedAt: member.joinedAt,
                isCurrentUser: true,
                avatarURL: nil,
                bannerURL: nil
            )
        }
    }

    func presentAlert(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        alertMessage = trimmed
    }

    func dismissAlert() {
        alertMessage = nil
    }

    private func prepareApplication(appleCredential: AppleSignInCredential) async {
        do {
            try await persistence.load()
            objectWillChange.send()
            let legacyData = legacySnapshotProvider.loadSnapshotData()
            _ = try await migrationService.migrateIfNeeded(data: legacyData)
            try await repository.deduplicateStableIDs()
            try await repository.migrateLegacyHouseholdDefaultsIfNeeded()
            preferences.reloadFromDefaults()

            let preferredName = appleCredential.providedDisplayName
                ?? preferences.participantDisplayName.nilIfBlank
                ?? appleCredential.displayName
            installConnectivityMonitor()
            installCloudObservers()

            let restoredAccount = try await backend.restoredAccount(
                appleUserID: appleCredential.userID,
                displayName: preferredName
            )
            account = restoredAccount
            if let appleName = appleCredential.providedDisplayName {
                preferences.participantDisplayName = appleName
            } else if preferences.participantDisplayName.nilIfBlank == nil {
                preferences.participantDisplayName = restoredAccount.displayName
            }
            reloadProfileMedia(for: restoredAccount.id)
            try await repository.claimUnassignedFamilySpaces(for: restoredAccount.id)
            try reload()
            await acceptPendingCloudKitShares()
            try await finishFamilyCartSetup(for: restoredAccount)
            syncState = online ? .synchronized : .offline
            await refreshFamilyMetadata(showErrors: false)
            needsWelcome = false
            isReady = true
            // Start CKShare early so Settings → Пригласить is usually instant.
            scheduleInviteLinkPreparation(delayNanoseconds: 2_000_000_000)
        } catch {
            needsWelcome = true
            welcomePhase = .failed(userFacingMessage(for: error))
            isReady = true
        }
    }

    /// Ensures one household cart. Shared invite replaces the local private cart.
    private func finishFamilyCartSetup(for account: OneCartAccount) async throws {
        try reload()
        if familySpaces.isEmpty {
            _ = try await repository.createFamilySpace(
                name: Self.defaultFamilyName,
                cachedForUserID: account.id,
                isHouseholdDefault: true
            )
            try reload()
        }
        try await adoptSharedFamilyCartIfNeeded(for: account)
    }

    private func preferredSharedFamilyID() -> UUID? {
        familySpaces.first { persistence.scope(for: $0) == .shared }?.id
    }

    /// When a shared family cart exists, it becomes active. Empty private starters are
    /// archived; private carts with content are merged into the shared cart, then archived.
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
        lists = []
        activeLists = []
        products = []
        productsByListID = [:]
        history = []
        familyMembers = []
        access = nil
        profileAvatar = nil
        profileBanner = nil
    }

    private func performMutation(
        successMessage: String?,
        operation: @escaping () async throws -> Void
    ) async {
        _ = successMessage
        guard canEdit else {
            presentAlert(RepositoryError.permissionDenied.localizedDescription)
            return
        }

        do {
            try await operation()
            await persistence.container.viewContext.perform {
                self.persistence.container.viewContext.processPendingChanges()
            }
            try reload()
        } catch {
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
        if let selectedID = selected?.id {
            defaults.set(
                selectedID.uuidString,
                forKey: activeFamilyKey(accountID: account.id)
            )
            lists = try fetchLists(familySpaceID: selectedID, in: context)
            products = try fetchProducts(familySpaceID: selectedID, in: context)
            history = try fetchHistory(familySpaceID: selectedID, in: context)
            if let selected {
                access = backend.access(for: selected)
            } else {
                access = nil
            }
            if previousID != selectedID {
                familyMembers = []
            }
            // Invalidate only a finished cache for the wrong cart / non-owner.
            // Do not cancel an in-flight warm-up when `preparedInviteFamilyID` is still nil.
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
            lists = []
            products = []
            history = []
            familyMembers = []
            access = nil
            clearPreparedInviteLink()
        }
        rebuildDerivedCollections()
    }

    private func refreshProducts() throws {
        guard let selectedID = activeFamilySpace?.id else { return }
        let context = persistence.container.viewContext
        context.processPendingChanges()
        products = try fetchProducts(familySpaceID: selectedID, in: context)
        rebuildDerivedCollections()
    }

    private func rebuildDerivedCollections() {
        activeLists = lists.filter { !$0.isDeletedValue && $0.statusValue == .active }

        var grouped: [UUID: [ProductEntity]] = [:]

        for product in products where !product.isDeletedValue {
            guard let listID = product.list?.id else { continue }
            grouped[listID, default: []].append(product)
        }

        productsByListID = grouped
    }

    private func fetchLists(
        familySpaceID: UUID,
        in context: NSManagedObjectContext
    ) throws -> [ShoppingListEntity] {
        let request = ShoppingListEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "familySpace.id == %@", familySpaceID as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ])
        request.sortDescriptors = [
            NSSortDescriptor(key: "status", ascending: true),
            NSSortDescriptor(key: "updatedAt", ascending: false),
        ]
        return try context.fetch(request)
    }

    private func fetchProducts(
        familySpaceID: UUID,
        in context: NSManagedObjectContext
    ) throws -> [ProductEntity] {
        let request = ProductEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "familySpace.id == %@", familySpaceID as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ])
        request.sortDescriptors = [
            NSSortDescriptor(key: "isPurchased", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
        ]
        return try context.fetch(request)
    }

    private func fetchHistory(
        familySpaceID: UUID,
        in context: NSManagedObjectContext
    ) throws -> [PurchaseHistoryEntity] {
        let request = PurchaseHistoryEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "familySpace.id == %@", familySpaceID as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try context.fetch(request)
    }

    private func refreshFamilyMetadata(showErrors: Bool) async {
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

    private func installCloudObservers() {
        guard remoteChangeObserver == nil, cloudEventObserver == nil else { return }
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleCloudReload() }
        }

        cloudEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: persistence.container,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self,
                      let event = notification.userInfo?[
                          NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                      ] as? NSPersistentCloudKitContainer.Event else { return }
                if event.endDate == nil {
                    self.syncState = .syncing
                } else if let error = event.error {
                    self.syncState = self.isNetworkError(error) ? .offline : .failed
                    let message = self.userFacingMessage(for: error)
                    self.lastSyncError = message
                    // Mirroring failures never go through `show(_:)` — surface the
                    // Production-schema Deploy instruction instead of failing silently.
                    if CloudKitUserFacingError.isProductionSchemaFailure(error) {
                        self.presentProductionSchemaAlertIfNeeded(message)
                    }
                } else {
                    self.syncState = self.online ? .synchronized : .offline
                    self.lastSyncError = nil
                }
            }
        }
    }

    private func scheduleCloudReload(delayNanoseconds: UInt64 = 650_000_000) {
        guard account != nil else { return }
        scheduledReloadTask?.cancel()
        scheduledReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled, let self, let account = self.account else { return }
            do {
                try await adoptSharedFamilyCartIfNeeded(for: account)
                if familyManagementPresented {
                    await refreshFamilyMetadata(showErrors: false)
                }
            } catch {
                self.syncState = .failed
                self.lastSyncError = userFacingMessage(for: error)
            }
        }
    }

    private func installConnectivityMonitor() {
        connectivity.onChange = { [weak self] isOnline in
            Task { @MainActor in
                guard let self else { return }
                let wasOnline = self.online
                self.online = isOnline
                if !isOnline {
                    self.syncState = .offline
                } else if !wasOnline, self.account != nil {
                    self.syncState = .syncing
                    self.scheduleCloudReload(delayNanoseconds: 150_000_000)
                }
            }
        }
        connectivity.start()
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

    private func presentProductionSchemaAlertIfNeeded(_ message: String) {
        guard !didPresentProductionSchemaAlert else { return }
        didPresentProductionSchemaAlert = true
        presentAlert(message)
    }

    private func userFacingMessage(for error: Error) -> String {
        if error is OneCartCloudKitError {
            return CloudKitUserFacingError.message(for: error)
        }
        if CloudKitUserFacingError.isNetworkError(error) {
            return "Нет соединения с сервисом синхронизации. Изменения останутся на устройстве и синхронизируются позже."
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

private final class ConnectivityMonitor {
    var onChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.vil55tim.onecart.connectivity")
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onChange?(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    func stop() {
        guard running else { return }
        running = false
        monitor.cancel()
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
