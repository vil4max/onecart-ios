import AuthenticationServices
import Combine
import CoreData
import Foundation
import Network
import SwiftUI
import UIKit

// Compatibility alias while Views migrate to AppSession.
typealias AppModel = AppSession

enum AppTheme: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .light: "Светлая"
        case .dark: "Тёмная"
        case .system: "Системная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

final class DevicePreferences: ObservableObject {
    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    @Published var defaultUnit: ProductUnit {
        didSet { defaults.set(defaultUnit.rawValue, forKey: Keys.defaultUnit) }
    }

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
        theme = AppTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
        defaultUnit = ProductUnit(
            rawValue: defaults.string(forKey: Keys.defaultUnit) ?? ""
        ) ?? .piece
        participantDisplayName = defaults.string(
            forKey: Keys.participantDisplayName
        ) ?? ""
    }

    func reloadFromDefaults() {
        theme = AppTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
        defaultUnit = ProductUnit(
            rawValue: defaults.string(forKey: Keys.defaultUnit) ?? ""
        ) ?? .piece
        participantDisplayName = defaults.string(
            forKey: Keys.participantDisplayName
        ) ?? ""
    }

    private enum Keys {
        static let theme = "onecart.theme"
        static let defaultUnit = "onecart.default-unit"
        static let participantDisplayName = "onecart.participant-display-name"
    }
}

enum ToastStyle: Equatable {
    case success
    case info
    case error

    var systemImage: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let style: ToastStyle
}

struct HomeOverview: Equatable {
    var purchasedCount = 0
    var totalCount = 0
    var estimatedTotal = 0.0

    var remainingCount: Int {
        max(totalCount - purchasedCount, 0)
    }
}

struct ListOverviewSummary: Equatable {
    let productCount: Int
    let purchasedCount: Int
}

enum InviteLinkError: LocalizedError {
    case notOwner
    case offline

    var errorDescription: String? {
        switch self {
        case .notOwner:
            "Приглашать участников может только владелец группы."
        case .offline:
            "Для создания ссылки подключитесь к интернету."
        }
    }
}

enum WelcomePhase: Equatable {
    case signIn
    case audience
    case connecting
    case failed(String)
}

enum HouseholdAudience: String, CaseIterable, Identifiable {
    case justMe
    case partner
    case appleFamily

    var id: String { rawValue }
}

@MainActor
// RC05: AppSession is the Level 1 MVVM composition root (auth, sync, household selection).
final class AppSession: ObservableObject {

    nonisolated static let defaultFamilyName = String(
        localized: "cart.default_title",
        defaultValue: "Наши покупки"
    )

    @Published private(set) var isReady = false
    @Published private(set) var isBusy = false
    @Published private(set) var needsWelcome = false
    @Published private(set) var welcomePhase: WelcomePhase = .signIn
    @Published var pendingCartMerge: CartMergePrompt?
    @Published private(set) var account: OneCartAccount?
    @Published private(set) var syncState: OneCartSyncState = .synchronized
    @Published private(set) var lastSyncError: String?
    @Published private(set) var familySpaces: [FamilySpace] = []
    @Published private(set) var activeFamilySpace: FamilySpace?
    @Published private(set) var stores: [StoreEntity] = []
    @Published private(set) var lists: [ShoppingListEntity] = []
    @Published private(set) var activeLists: [ShoppingListEntity] = []
    @Published private(set) var products: [ProductEntity] = []
    @Published private(set) var productsByListID: [UUID: [ProductEntity]] = [:]
    @Published private(set) var listSummaries: [UUID: ListOverviewSummary] = [:]
    @Published private(set) var homeOverview = HomeOverview()
    @Published private(set) var history: [PurchaseHistoryEntity] = []
    @Published private(set) var familyMembers: [FamilyMember] = []
    @Published private(set) var access: FamilyAccess?
    @Published private(set) var isFamilyMetadataLoading = false
    @Published var familyManagementPresented = false
    @Published var toast: ToastMessage?
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

    private static let audienceCompletedKey = "onecart.audienceCompleted"

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

    func refreshFamilyCartFromCloud() async {
        guard account != nil else { return }
        isBusy = true
        defer { isBusy = false }
        await acceptPendingCloudKitShares()
        do {
            try reload()
            if let account {
                _ = try await resolveFamilyCartConflicts(for: account)
            }
            if activeFamilySpace != nil {
                showToast("Семейная корзина подключена")
            }
        } catch {
            show(error)
        }
    }

    func applyCartMergeChoice(_ choice: CartMergeChoice) async {
        guard let prompt = pendingCartMerge, let account else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            switch choice {
            case .useSharedOnly:
                try await repository.archiveFamilySpace(id: prompt.privateFamilyID)
            case .mergeIntoShared:
                try await repository.mergeFamilyContent(
                    from: prompt.privateFamilyID,
                    into: prompt.sharedFamilyID
                )
            case .keepPrivate:
                pendingCartMerge = nil
                return
            }
            pendingCartMerge = nil
            defaults.set(
                prompt.sharedFamilyID.uuidString,
                forKey: activeFamilyKey(accountID: account.id)
            )
            try reload(preferredFamilySpaceID: prompt.sharedFamilyID)
            showToast("Семейная корзина подключена")
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
        needsWelcome = true
        welcomePhase = .connecting
        isReady = true
        do {
            try persistence.resetLocalStoreFiles()
        } catch {
            welcomePhase = .failed(userFacingMessage(for: error))
            return
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
        appleSignIn.clearCredential()
        clearAccountData()
        account = nil
        pendingCartMerge = nil
        needsWelcome = true
        welcomePhase = .signIn
        isReady = true
        started = true
    }

    private func bootstrapSession() async {
        if let credential = appleSignIn.storedCredential() {
            let state = await appleSignIn.credentialState(for: credential.userID)
            if state == .authorized {
                needsWelcome = false
                welcomePhase = .connecting
                await prepareApplication(appleCredential: credential)
                return
            }
            appleSignIn.clearCredential()
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
            showToast("Корзина создана")
        } catch {
            show(error)
        }
    }

    func renameFamilySpace(name: String) async {
        guard access?.isOwner == true, let id = activeFamilySpace?.id else {
            showToast("Название может менять только владелец группы.", style: .info)
            return
        }
        await performMutation(successMessage: "Название обновлено") {
            try await self.repository.renameFamilySpace(id: id, name: name)
        }
    }

    func addStore(_ draft: StoreDraft) async {
        guard let familySpaceID = activeFamilySpace?.id else { return }
        await performMutation(successMessage: "Магазин добавлен") {
            try await self.repository.addStore(to: familySpaceID, draft: draft)
        }
    }

    func updateStore(_ store: StoreEntity, draft: StoreDraft) async {
        guard let id = store.id else { return }
        await performMutation(successMessage: "Магазин обновлён") {
            try await self.repository.updateStore(id: id, draft: draft)
        }
    }

    func deleteStore(_ store: StoreEntity) async {
        guard let id = store.id else { return }
        await performMutation(successMessage: "Магазин удалён") {
            try await self.repository.deleteStore(id: id)
        }
    }

    func addList(title: String, store: StoreEntity?) async {
        guard let familySpaceID = activeFamilySpace?.id else { return }
        await performMutation(successMessage: "Список создан") {
            try await self.repository.addList(
                to: familySpaceID,
                title: title,
                storeID: store?.id
            )
        }
    }

    func deleteList(_ list: ShoppingListEntity) async {
        guard let id = list.id else { return }
        await performMutation(successMessage: "Список удалён") {
            try await self.repository.deleteList(id: id)
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

    func refreshCatalogPrices(
        in listID: UUID,
        snapshots: [CatalogPriceSnapshot]
    ) async {
        guard canEdit, !snapshots.isEmpty else { return }
        do {
            let updated = try await repository.refreshCatalogPrices(
                in: listID,
                snapshots: snapshots
            )
            guard updated > 0 else { return }
            try refreshProductsAndSummaries()
        } catch {
            show(error)
        }
    }

    func verifyOfficialCatalogProduct(
        _ product: OfficialCatalogProduct,
        brand: StoreBrand
    ) async -> OfficialCatalogProduct? {
        _ = product
        _ = brand
        // CloudKit stores app data but does not execute HTTP functions. The catalog
        // detail screen keeps its on-device WKWebView verification fallback.
        return nil
    }

    func togglePurchased(_ product: ProductEntity) async {
        guard let id = product.id else { return }
        guard canEdit else {
            showToast(RepositoryError.permissionDenied.localizedDescription, style: .info)
            return
        }

        do {
            try await repository.togglePurchased(
                id: id,
                participantDisplayName: preferences.participantDisplayName.nilIfBlank
                    ?? account?.displayName
            )
            try refreshProductsAndSummaries()
        } catch {
            show(error)
        }
    }

    func summary(for listID: UUID) -> ListOverviewSummary {
        listSummaries[listID] ?? ListOverviewSummary(productCount: 0, purchasedCount: 0)
    }

    func products(inListID listID: UUID) -> [ProductEntity] {
        productsByListID[listID] ?? []
    }

    func moveProduct(
        _ product: ProductEntity,
        to destination: ShoppingListEntity
    ) async {
        guard let id = product.id, let destinationID = destination.id else { return }
        await performMutation(successMessage: "Товар перемещён") {
            try await self.repository.moveProduct(id: id, to: destinationID)
        }
    }

    func deleteProduct(_ product: ProductEntity) async {
        guard let id = product.id else { return }
        await performMutation(successMessage: "Товар удалён") {
            try await self.repository.deleteProduct(id: id)
        }
    }

    func completeList(_ list: ShoppingListEntity) async {
        guard let id = list.id else { return }
        await performMutation(successMessage: "Покупка сохранена в истории") {
            _ = try await self.repository.completeList(id: id)
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
    func createFamilyInviteLink() async throws -> FamilyInviteLink {
        guard let family = activeFamilySpace, access?.isOwner == true else {
            throw InviteLinkError.notOwner
        }
        guard online else {
            throw InviteLinkError.offline
        }

        return try await backend.createFamilyInviteLink(for: family)
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
                _ = try await resolveFamilyCartConflicts(for: account)
            }
            if familySpaces.contains(where: { persistence.scope(for: $0) == .shared }) {
                needsWelcome = false
            }
            scheduleCloudReload(delayNanoseconds: 350_000_000)
            showToast("Семейная корзина подключена")
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
            showToast("Для изменения состава группы подключитесь к интернету.", style: .info)
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.removeMember(member, from: family)
            await refreshFamilyMetadata(showErrors: false)
            showToast("Участник удалён")
        } catch {
            show(error)
        }
    }

    func leaveCurrentFamily() async {
        guard account != nil,
              let family = activeFamilySpace,
              access?.isParticipant == true else { return }
        guard online else {
            showToast("Чтобы покинуть группу, подключитесь к интернету.", style: .info)
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.leaveFamily(family)
            scheduleCloudReload(delayNanoseconds: 350_000_000)
            showToast("Вы покинули группу")
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
            showToast("Укажите имя", style: .error)
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
            showToast("Профиль обновлён")
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

    func showToast(_ text: String, style: ToastStyle = .success) {
        let nextToast = ToastMessage(text: text, style: style)
        toast = nextToast
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.toast?.id == nextToast.id {
                self.toast = nil
            }
        }
    }

    private func prepareApplication(appleCredential: AppleSignInCredential) async {
        do {
            try await persistence.load()
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
            let finished = try await finishFamilyCartSetup(for: restoredAccount)
            guard finished else { return }
            syncState = online ? .synchronized : .offline
            await refreshFamilyMetadata(showErrors: false)
            if defaults.bool(forKey: Self.audienceCompletedKey) {
                needsWelcome = false
            } else {
                needsWelcome = true
                welcomePhase = .audience
            }
            isReady = true
        } catch {
            needsWelcome = true
            welcomePhase = .failed(userFacingMessage(for: error))
            isReady = true
        }
    }

    /// Syncs CloudKit shares, ensures one Household cart, and resolves private/shared conflicts.
    @discardableResult
    private func finishFamilyCartSetup(for account: OneCartAccount) async throws -> Bool {
        try reload()
        if familySpaces.isEmpty {
            _ = try await repository.createFamilySpace(
                name: Self.defaultFamilyName,
                cachedForUserID: account.id,
                isHouseholdDefault: true
            )
            try reload()
        }
        guard familySpaces.contains(where: { persistence.scope(for: $0) == .shared }) else {
            return true
        }

        _ = try await resolveFamilyCartConflicts(for: account)
        if pendingCartMerge == nil {
            try reload(preferredFamilySpaceID: preferredSharedFamilyID())
        }
        return true
    }

    func completeHouseholdAudience(_ audience: HouseholdAudience) async {
        welcomePhase = .connecting
        guard let account else {
            welcomePhase = .failed("Сначала войдите через Apple.")
            return
        }
        do {
            if familySpaces.isEmpty {
                _ = try await repository.createFamilySpace(
                    name: Self.defaultFamilyName,
                    cachedForUserID: account.id,
                    isHouseholdDefault: true
                )
                try reload()
            }
            switch audience {
            case .justMe:
                defaults.set(true, forKey: Self.audienceCompletedKey)
                needsWelcome = false
                isReady = true
            case .partner, .appleFamily:
                defaults.set(true, forKey: Self.audienceCompletedKey)
                familyManagementPresented = true
                needsWelcome = false
                isReady = true
                showToast(
                    audience == .partner
                        ? "Пригласите партнёра через Share"
                        : "Пригласите семью через Share",
                    style: .info
                )
            }
        } catch {
            welcomePhase = .failed(userFacingMessage(for: error))
        }
    }

    private func preferredSharedFamilyID() -> UUID? {
        familySpaces.first { persistence.scope(for: $0) == .shared }?.id
    }

    @discardableResult
    private func resolveFamilyCartConflicts(for account: OneCartAccount) async throws -> Bool {
        try reload()
        guard let sharedFamily = familySpaces.first(where: {
            persistence.scope(for: $0) == .shared
        }), let sharedID = sharedFamily.id else {
            return true
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

            let summary = FamilyCartMerge.summary(for: privateFamily)
            pendingCartMerge = CartMergePrompt(
                privateFamilyID: privateID,
                sharedFamilyID: sharedID,
                privateFamilyName: privateFamily.displayName,
                sharedFamilyName: sharedFamily.displayName,
                summary: summary
            )
            return false
        }

        defaults.set(
            sharedID.uuidString,
            forKey: activeFamilyKey(accountID: account.id)
        )
        return true
    }

    private func clearAccountData() {
        familySpaces = []
        activeFamilySpace = nil
        stores = []
        lists = []
        activeLists = []
        products = []
        productsByListID = [:]
        listSummaries = [:]
        homeOverview = HomeOverview()
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
        guard canEdit else {
            showToast(RepositoryError.permissionDenied.localizedDescription, style: .info)
            return
        }

        do {
            try await operation()
            try reload()
            if let successMessage {
                showToast(successMessage)
            }
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
        familySpaces = try repository.fetchFamilySpaces()

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
            stores = try fetchStores(familySpaceID: selectedID, in: context)
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
        } else {
            defaults.removeObject(forKey: activeFamilyKey(accountID: account.id))
            stores = []
            lists = []
            products = []
            history = []
            familyMembers = []
            access = nil
        }
        rebuildDerivedCollections()
    }

    private func refreshProductsAndSummaries() throws {
        guard let selectedID = activeFamilySpace?.id else { return }
        let context = persistence.container.viewContext
        context.processPendingChanges()
        products = try fetchProducts(familySpaceID: selectedID, in: context)
        rebuildDerivedCollections()
    }

    private func rebuildDerivedCollections() {
        activeLists = lists.filter { !$0.isDeletedValue && $0.statusValue == .active }

        var purchasedCount = 0
        var estimatedTotal = 0.0
        var grouped: [UUID: [ProductEntity]] = [:]
        var counts: [UUID: (total: Int, purchased: Int)] = [:]

        for product in products where !product.isDeletedValue {
            if product.isPurchasedValue {
                purchasedCount += 1
            }
            estimatedTotal += product.estimatedPriceValue

            guard let listID = product.list?.id else { continue }
            grouped[listID, default: []].append(product)
            var entry = counts[listID] ?? (0, 0)
            entry.total += 1
            if product.isPurchasedValue {
                entry.purchased += 1
            }
            counts[listID] = entry
        }

        productsByListID = grouped
        listSummaries = counts.mapValues {
            ListOverviewSummary(productCount: $0.total, purchasedCount: $0.purchased)
        }
        homeOverview = HomeOverview(
            purchasedCount: purchasedCount,
            totalCount: products.count,
            estimatedTotal: estimatedTotal
        )
    }

    private func fetchStores(
        familySpaceID: UUID,
        in context: NSManagedObjectContext
    ) throws -> [StoreEntity] {
        let request = StoreEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "familySpace.id == %@", familySpaceID as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ])
        request.sortDescriptors = [
            NSSortDescriptor(key: "isPinned", ascending: false),
            NSSortDescriptor(
                key: "name",
                ascending: true,
                selector: #selector(NSString.localizedCaseInsensitiveCompare(_:))
            ),
        ]
        return try context.fetch(request)
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
                    self.lastSyncError = self.userFacingMessage(for: error)
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
            guard !Task.isCancelled, let self else { return }
            do {
                try reload()
                if familyManagementPresented {
                    await refreshFamilyMetadata(showErrors: false)
                }
            } catch {
                lastSyncError = userFacingMessage(for: error)
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
        showToast(userFacingMessage(for: error), style: .error)
    }

    private func userFacingMessage(for error: Error) -> String {
        let raw = error.localizedDescription
        let normalized = raw.lowercased()

        if normalized.contains("not authenticated") || normalized.contains("not signed in") {
            return "Войдите в Apple Account в Настройках iPhone и повторите попытку."
        }
        if isNetworkError(error) {
            return "Нет соединения с сервисом синхронизации. Изменения останутся на устройстве и синхронизируются позже."
        }
        if PersistenceController.isUserFacingCoreDataFailure(error) {
            return String(localized: "welcome.core_data_failed")
        }
        return (error as? LocalizedError)?.errorDescription
            ?? (raw.isEmpty ? "Не удалось завершить операцию." : raw)
    }

    private func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return true
        }
        let text = error.localizedDescription.lowercased()
        return text.contains("network connection")
            || text.contains("internet connection")
            || text.contains("timed out")
            || text.contains("could not connect")
            || text.contains("offline")
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
