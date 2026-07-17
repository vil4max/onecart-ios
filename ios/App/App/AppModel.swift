import Combine
import CoreData
import Foundation
import Network
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        case .system: return "Системная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

enum AppLocale: String, CaseIterable, Identifiable {
    case ru
    case uk

    var id: String { rawValue }
    var title: String { self == .ru ? "Русский" : "Українська" }
}

final class DevicePreferences: ObservableObject {
    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }
    @Published var locale: AppLocale {
        didSet { defaults.set(locale.rawValue, forKey: Keys.locale) }
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
        locale = AppLocale(rawValue: defaults.string(forKey: Keys.locale) ?? "") ?? .ru
        defaultUnit = ProductUnit(
            rawValue: defaults.string(forKey: Keys.defaultUnit) ?? ""
        ) ?? .piece
        participantDisplayName = defaults.string(
            forKey: Keys.participantDisplayName
        ) ?? ""
    }

    func reloadFromDefaults() {
        theme = AppTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
        locale = AppLocale(rawValue: defaults.string(forKey: Keys.locale) ?? "") ?? .ru
        defaultUnit = ProductUnit(
            rawValue: defaults.string(forKey: Keys.defaultUnit) ?? ""
        ) ?? .piece
        participantDisplayName = defaults.string(
            forKey: Keys.participantDisplayName
        ) ?? ""
    }

    private enum Keys {
        static let theme = "onecart.theme"
        static let locale = "onecart.locale"
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
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
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

    var remainingCount: Int { max(totalCount - purchasedCount, 0) }
}

struct ListOverviewSummary: Equatable {
    let productCount: Int
    let purchasedCount: Int
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var isBusy = false
    @Published private(set) var launchError: String?
    @Published private(set) var account: OneCartAccount?
    @Published private(set) var authenticationMessage: String?
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
    @Published private(set) var pendingInvitations: [FamilyInvitation] = []
    @Published private(set) var access: FamilyAccess?
    @Published private(set) var isFamilyMetadataLoading = false
    @Published private(set) var hasPendingFamilyInvite = false
    @Published var familyManagementPresented = false
    @Published var familyInvitePreview: FamilyInvitePreview?
    @Published var toast: ToastMessage?

    let preferences: DevicePreferences
    let persistence: PersistenceController

    var canEdit: Bool {
        activeFamilySpace != nil && (access?.canEdit ?? false)
    }

    var isOnline: Bool { online }

    private let repository: FamilySpaceRepository
    private let backend: SupabaseBackendService
    private let syncService: FamilySyncService
    private let migrationService: LegacyMigrationService
    private let legacySnapshotProvider: LegacySnapshotProviding
    private let defaults: UserDefaults
    private let connectivity = ConnectivityMonitor()
    private var online = true
    private var started = false
    private var synchronizing = false
    private var needsResync = false
    /// Suppresses Realtime→sync echo right after our own snapshot write.
    private var realtimeQuietUntil = Date.distantPast
    private var realtimeTask: Task<Void, Never>?
    private var scheduledSyncTask: Task<Void, Never>?
    private static let pendingInviteTokenKey = "onecart.pending-family-invite-token"
    private static let realtimeQuietInterval: TimeInterval = 2.8

    init(
        persistence: PersistenceController = .shared,
        preferences: DevicePreferences = DevicePreferences(),
        defaults: UserDefaults = .standard,
        legacySnapshotProvider: LegacySnapshotProviding = DefaultLegacySnapshotProvider(),
        backend: SupabaseBackendService? = nil
    ) {
        self.persistence = persistence
        self.preferences = preferences
        self.defaults = defaults
        self.legacySnapshotProvider = legacySnapshotProvider

        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let backend = backend ?? SupabaseBackendService()
        self.repository = repository
        self.backend = backend
        syncService = FamilySyncService(
            persistence: persistence,
            repository: repository,
            backend: backend
        )
        migrationService = LegacyMigrationService(
            persistence: persistence,
            userDefaults: defaults
        )
        hasPendingFamilyInvite = defaults.string(
            forKey: Self.pendingInviteTokenKey
        ) != nil
    }

    deinit {
        realtimeTask?.cancel()
        scheduledSyncTask?.cancel()
        connectivity.stop()
    }

    func start() async {
        guard !started else { return }
        started = true
        await prepareApplication()
    }

    func retryStartup() async {
        launchError = nil
        await prepareApplication()
    }

    func signIn(email: String, password: String) async {
        authenticationMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            let account = try await backend.signIn(email: email, password: password)
            try await activate(account: account)
            showToast("Вы вошли в OneCart")
        } catch {
            authenticationMessage = userFacingMessage(for: error)
        }
    }

    func register(displayName: String, email: String, password: String) async {
        authenticationMessage = nil
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            authenticationMessage = "Введите имя."
            return
        }
        guard password.count >= 8 else {
            authenticationMessage = "Пароль должен содержать не меньше 8 символов."
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            switch try await backend.register(
                displayName: name,
                email: email,
                password: password
            ) {
            case .signedIn(let account):
                try await activate(account: account)
                showToast("Аккаунт создан")
            case .confirmationRequired(let email):
                authenticationMessage = "Мы отправили письмо на \(email). Подтвердите адрес и затем войдите."
            }
        } catch {
            authenticationMessage = userFacingMessage(for: error)
        }
    }

    func clearAuthenticationMessage() {
        authenticationMessage = nil
    }

    func signOut() async {
        isBusy = true
        realtimeTask?.cancel()
        realtimeTask = nil
        scheduledSyncTask?.cancel()
        scheduledSyncTask = nil
        try? await backend.signOut()

        account = nil
        familySpaces = []
        activeFamilySpace = nil
        stores = []
        lists = []
        products = []
        history = []
        familyMembers = []
        pendingInvitations = []
        access = nil
        familyInvitePreview = nil
        isFamilyMetadataLoading = false
        hasPendingFamilyInvite = defaults.string(
            forKey: Self.pendingInviteTokenKey
        ) != nil
        lastSyncError = nil
        syncState = .synchronized
        isBusy = false
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
                needsRemoteCreation: true
            )
            defaults.set(id.uuidString, forKey: activeFamilyKey(accountID: account.id))
            try reload(preferredFamilySpaceID: id)
            showToast("Семейное пространство создано")
            scheduleSynchronization()
        } catch {
            show(error)
        }
    }

    func renameFamilySpace(name: String) async {
        guard access?.isOwner == true, let id = activeFamilySpace?.id else {
            showToast("Название может менять только владелец семьи.", style: .info)
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
            scheduleSynchronization()
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

    func inviteMember(email: String) async {
        guard let familyID = activeFamilySpace?.id, access?.isOwner == true else {
            showToast("Приглашать участников может только владелец семьи.", style: .info)
            return
        }
        guard online else {
            showToast("Для отправки приглашения подключитесь к интернету.", style: .info)
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.invite(familyID: familyID, email: email)
            showToast("Приглашение отправлено на email")
        } catch {
            show(error)
        }
    }

    func createFamilyInviteLink() async -> FamilyInviteLink? {
        guard let familyID = activeFamilySpace?.id, access?.isOwner == true else {
            showToast("Приглашать участников может только владелец семьи.", style: .info)
            return nil
        }
        guard online else {
            showToast("Для создания ссылки подключитесь к интернету.", style: .info)
            return nil
        }

        if activeFamilySpace?.needsRemoteCreationValue == true {
            await synchronizeNow(showErrors: true)
            guard syncState == .synchronized else { return nil }
        }

        isBusy = true
        defer { isBusy = false }
        do {
            return try await backend.createFamilyInviteLink(familyID: familyID)
        } catch {
            show(error)
            return nil
        }
    }

    func handleIncomingURL(_ url: URL) async {
        guard let token = OneCartInviteURL.token(from: url) else { return }
        defaults.set(token.uuidString, forKey: Self.pendingInviteTokenKey)
        hasPendingFamilyInvite = true
        familyManagementPresented = false

        guard account != nil else {
            showToast(
                "Войдите или зарегистрируйтесь, чтобы принять приглашение.",
                style: .info
            )
            return
        }
        await presentPendingFamilyInvite(showErrors: true)
    }

    func acceptFamilyInvite(_ preview: FamilyInvitePreview) async {
        guard online else {
            showToast("Для принятия приглашения подключитесь к интернету.", style: .info)
            return
        }

        isBusy = true
        do {
            let familyID = try await backend.acceptFamilyInviteLink(token: preview.token)
            defaults.removeObject(forKey: Self.pendingInviteTokenKey)
            hasPendingFamilyInvite = false
            familyInvitePreview = nil
            isBusy = false

            await synchronizeNow(showErrors: true)
            if let space = familySpaces.first(where: { $0.id == familyID }) {
                setActiveFamilySpace(space)
            }
            showToast("Вы присоединились к семье «\(preview.familyName)»")
        } catch {
            isBusy = false
            show(error)
        }
    }

    func dismissFamilyInvitePreview() {
        familyInvitePreview = nil
    }

    func showPendingFamilyInvite() async {
        await presentPendingFamilyInvite(showErrors: true)
    }

    func acceptInvitation(_ invitation: FamilyInvitation) async {
        guard online else {
            showToast("Для принятия приглашения подключитесь к интернету.", style: .info)
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.acceptInvitation(id: invitation.id)
            await synchronizeNow(showErrors: true)
            if let space = familySpaces.first(where: { $0.id == invitation.familyID }) {
                setActiveFamilySpace(space)
            }
            showToast("Вы присоединились к семье")
        } catch {
            show(error)
        }
    }

    func removeMember(_ member: FamilyMember) async {
        guard let familyID = activeFamilySpace?.id,
              access?.isOwner == true,
              !member.isCurrentUser else { return }
        guard online else {
            showToast("Для изменения состава семьи подключитесь к интернету.", style: .info)
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.removeMember(familyID: familyID, userID: member.id)
            await refreshFamilyMetadata(showErrors: false)
            showToast("Участник удалён")
        } catch {
            show(error)
        }
    }

    func leaveCurrentFamily() async {
        guard let account,
              let familyID = activeFamilySpace?.id,
              access?.isParticipant == true else { return }
        guard online else {
            showToast("Чтобы покинуть семью, подключитесь к интернету.", style: .info)
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.leaveFamily(id: familyID)
            try await repository.removeCachedFamilySpace(id: familyID, for: account.id)
            defaults.removeObject(forKey: activeFamilyKey(accountID: account.id))
            try reload()
            await refreshFamilyMetadata(showErrors: false)
            showToast("Вы покинули семейное пространство")
        } catch {
            show(error)
        }
    }

    func refreshFromServer() async {
        await synchronizeNow(showErrors: true)
    }

    func showFamilyManagement() {
        familyManagementPresented = true
        Task { await refreshFamilyMetadata(showErrors: true) }
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

    private func prepareApplication() async {
        do {
            try await persistence.load()
            let legacyData = legacySnapshotProvider.loadSnapshotData()
            _ = try await migrationService.migrateIfNeeded(data: legacyData)
            try await repository.deduplicateStableIDs()
            preferences.reloadFromDefaults()
            installConnectivityMonitor()

            account = await backend.restoredAccount()
            if let account {
                try await repository.claimUnassignedFamilySpaces(for: account.id)
                try reload()
                if online {
                    await synchronizeNow(showErrors: false)
                    startRealtime()
                } else {
                    syncState = .offline
                }
                await presentPendingFamilyInvite(showErrors: false)
            } else {
                clearAccountData()
            }
            isReady = true
        } catch {
            launchError = userFacingMessage(for: error)
            isReady = true
        }
    }

    private func activate(account: OneCartAccount) async throws {
        self.account = account
        if preferences.participantDisplayName.nilIfBlank == nil {
            preferences.participantDisplayName = account.displayName
        }
        try await repository.claimUnassignedFamilySpaces(for: account.id)
        try reload()
        if online {
            await synchronizeNow(showErrors: false)
            startRealtime()
        } else {
            syncState = .offline
        }
        await presentPendingFamilyInvite(showErrors: false)
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
        pendingInvitations = []
        access = nil
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
            scheduleSynchronization()
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
        } ?? familySpaces.first

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
            access = FamilyAccess(rawValue: selected?.serverRole ?? "")
                ?? (selected?.needsRemoteCreationValue == true ? .owner : .member)
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

    private func synchronizeNow(showErrors: Bool) async {
        guard let account else { return }
        guard online else {
            syncState = .offline
            return
        }
        guard !synchronizing else {
            needsResync = true
            return
        }

        synchronizing = true
        syncState = .syncing
        defer {
            synchronizing = false
            // Own writes echo through Realtime; keep a quiet window so we don't
            // immediately schedule another full snapshot reload on MainActor.
            realtimeQuietUntil = Date().addingTimeInterval(Self.realtimeQuietInterval)
            if needsResync {
                needsResync = false
                let delayNs = UInt64((Self.realtimeQuietInterval + 0.5) * 1_000_000_000)
                scheduleSynchronization(delayNanoseconds: delayNs)
            }
        }
        do {
            _ = try await syncService.synchronize(account: account)
            try reload()
            if familyManagementPresented {
                await refreshFamilyMetadata(showErrors: false)
            } else {
                await refreshPendingInvitations(showErrors: false)
            }
            syncState = .synchronized
            lastSyncError = nil
        } catch {
            if isNetworkError(error) {
                syncState = .offline
            } else {
                syncState = .failed
            }
            lastSyncError = userFacingMessage(for: error)
            if showErrors {
                show(error)
            }
        }
    }

    private func refreshFamilyMetadata(showErrors: Bool) async {
        guard account != nil, online else { return }
        isFamilyMetadataLoading = true
        defer { isFamilyMetadataLoading = false }
        do {
            async let invitations = backend.pendingInvitations()
            if let familyID = activeFamilySpace?.id {
                async let members = backend.familyMembers(familyID: familyID)
                familyMembers = try await members
            } else {
                familyMembers = []
            }
            pendingInvitations = try await invitations
        } catch {
            if showErrors { show(error) }
        }
    }

    private func refreshPendingInvitations(showErrors: Bool) async {
        guard account != nil, online else { return }
        do {
            pendingInvitations = try await backend.pendingInvitations()
        } catch {
            if showErrors { show(error) }
        }
    }

    private func presentPendingFamilyInvite(showErrors: Bool) async {
        guard account != nil,
              online,
              let tokenValue = defaults.string(forKey: Self.pendingInviteTokenKey),
              let token = UUID(uuidString: tokenValue) else { return }

        do {
            guard let preview = try await backend.familyInvitePreview(token: token) else {
                defaults.removeObject(forKey: Self.pendingInviteTokenKey)
                hasPendingFamilyInvite = false
                familyInvitePreview = nil
                if showErrors {
                    showToast(
                        "Ссылка уже использована или срок её действия истёк.",
                        style: .error
                    )
                }
                return
            }
            familyInvitePreview = preview
        } catch {
            if showErrors { show(error) }
        }
    }

    private func scheduleSynchronization(delayNanoseconds: UInt64 = 650_000_000) {
        guard account != nil else { return }
        guard online else {
            syncState = .offline
            return
        }

        scheduledSyncTask?.cancel()
        scheduledSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.synchronizeNow(showErrors: false)
        }
    }

    private func handleRealtimeChange() {
        guard Date() >= realtimeQuietUntil else { return }
        if synchronizing {
            needsResync = true
            return
        }
        scheduleSynchronization(delayNanoseconds: 1_200_000_000)
    }

    private func startRealtime() {
        guard account != nil, online else { return }
        realtimeTask?.cancel()
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.backend.listenForDatabaseChanges { [weak self] in
                    Task { @MainActor in
                        self?.handleRealtimeChange()
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.lastSyncError = self.userFacingMessage(for: error)
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
                    self.realtimeTask?.cancel()
                    self.realtimeTask = nil
                } else if !wasOnline, self.account != nil {
                    await self.synchronizeNow(showErrors: false)
                    self.startRealtime()
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

        if normalized.contains("invalid login credentials") {
            return "Неверный email или пароль."
        }
        if normalized.contains("email not confirmed") {
            return "Сначала подтвердите email по ссылке из письма."
        }
        if normalized.contains("user already registered") {
            return "Аккаунт с таким email уже существует."
        }
        if normalized.contains("only the family owner") {
            return "Это действие доступно только владельцу семьи."
        }
        if normalized.contains("already a family member") {
            return "Этот человек уже состоит в семье."
        }
        if normalized.contains("already the family owner") {
            return "Нельзя пригласить собственный email."
        }
        if normalized.contains("invitation") && normalized.contains("expired") {
            return "Срок действия приглашения истёк."
        }
        if normalized.contains("invitation is unavailable") {
            return "Ссылка уже использована, отозвана или устарела."
        }
        if normalized.contains("family_invite_link")
            && normalized.contains("does not exist") {
            return "Ссылки-приглашения ещё не подключены на сервере OneCart."
        }
        if normalized.contains("row-level security") {
            return "Сервер не смог создать семейное пространство. Повторите синхронизацию после обновления настроек."
        }
        if isNetworkError(error) {
            return "Нет соединения с сервером. Изменения останутся на устройстве и синхронизируются позже."
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
