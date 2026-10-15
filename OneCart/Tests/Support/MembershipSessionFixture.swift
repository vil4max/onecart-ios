import CoreData
import Foundation
@testable import OneCart
import Testing

/// An `AppSession` over isolated stores for Swift Testing suites: an in-memory Core Data
/// stack, a private defaults suite and a widget store in a temporary directory. Nothing
/// reaches `.standard`, the App Group or the Keychain; the suite and directory are removed
/// with the fixture.
@MainActor
final class MembershipSessionFixture {
    let persistence: PersistenceController
    let repository: FamilySpaceRepository
    let defaults: UserDefaults
    let account: OneCartAccount
    let session: AppSession
    private(set) var personalID: UUID?
    private(set) var sharedID: UUID?
    private let suiteName: String
    private let widgetDirectory: URL

    private init(
        displayName: String,
        loadStore: Bool,
        classifier: any CategoryClassifying = KeywordCategoryClassifier(),
        cloudUserIdentity: (any CloudUserIdentifying)? = nil
    ) async throws {
        let suiteName = "OneCartMembershipTests.\(UUID().uuidString)"
        self.suiteName = suiteName
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        widgetDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)

        persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        if loadStore {
            try await persistence.load()
        }
        repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        account = OneCartAccount(id: UUID(), displayName: displayName)
        session = Self.makeSession(
            persistence: persistence,
            defaults: defaults,
            widgetStore: WidgetSnapshotStore(suiteName: suiteName, pendingDirectoryURL: widgetDirectory),
            classifier: classifier,
            cloudUserIdentity: cloudUserIdentity
        )
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: widgetDirectory)
        removeStoreFiles(of: persistence)
    }

    /// A second session over the same stores and defaults, as after an app relaunch.
    func relaunchedSession() -> AppSession {
        Self.makeSession(
            persistence: persistence,
            defaults: defaults,
            widgetStore: WidgetSnapshotStore(suiteName: suiteName, pendingDirectoryURL: widgetDirectory),
            classifier: KeywordCategoryClassifier(),
            cloudUserIdentity: nil
        )
    }

    /// Every dependency is a fake or isolated: never the live ActivityKit backend or the
    /// on-device language model.
    private static func makeSession(
        persistence: PersistenceController,
        defaults: UserDefaults,
        widgetStore: WidgetSnapshotStore,
        classifier: any CategoryClassifying,
        cloudUserIdentity: (any CloudUserIdentifying)?
    ) -> AppSession {
        AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults,
            appleSignIn: InMemoryAppleSignIn(),
            widgetStore: widgetStore,
            categoryClassifier: classifier,
            cloudUserIdentity: cloudUserIdentity,
            shoppingTripBackend: FakeShoppingTripBackend()
        )
    }

    /// A session with no account: the store may stay unloaded to exercise pre-load guards.
    static func signedOut(loadStore: Bool = true) async throws -> MembershipSessionFixture {
        try await MembershipSessionFixture(displayName: "Alex", loadStore: loadStore)
    }

    /// The owner of a personal household cart, signed in and reloaded.
    static func owner(
        displayName: String = "Alex",
        cartName: String? = nil,
        classifier: any CategoryClassifying = KeywordCategoryClassifier(),
        cloudUserIdentity: (any CloudUserIdentifying)? = nil
    ) async throws -> MembershipSessionFixture {
        let fixture = try await MembershipSessionFixture(
            displayName: displayName,
            loadStore: true,
            classifier: classifier,
            cloudUserIdentity: cloudUserIdentity
        )
        try await fixture.createPersonalCart(named: cartName)
        try fixture.session.bootstrapTestingSession(account: fixture.account)
        return fixture
    }

    /// A guest whose personal cart stays on disk while a shared cart is the active one, the
    /// state a member is in after accepting an invite.
    static func guest(
        displayName: String = "Sam",
        sharedName: String = "Семейная",
        cloudUserIdentity: (any CloudUserIdentifying)? = nil
    ) async throws -> MembershipSessionFixture {
        let fixture = try await MembershipSessionFixture(
            displayName: displayName,
            loadStore: true,
            cloudUserIdentity: cloudUserIdentity
        )
        try await fixture.createPersonalCart(named: nil)
        try await fixture.insertSharedCart(named: sharedName)
        try fixture.session.bootstrapTestingSession(account: fixture.account)
        try await fixture.session.offerSharedCartJoinIfNeededForTesting()
        return fixture
    }

    private func createPersonalCart(named cartName: String?) async throws {
        let id = try await repository.createFamilySpace(
            name: cartName ?? AppSession.householdCartName(for: account),
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        personalID = id
        defaults.set(id.uuidString, forKey: session.activeFamilyKey(accountID: account.id))
    }

    private func insertSharedCart(named sharedName: String) async throws {
        let sharedID = UUID()
        let persistence = persistence
        try await persistence.performBackgroundTask { context in
            let space = FamilySpace(context: context)
            try persistence.assign(space, to: .shared, in: context)
            space.id = sharedID
            space.name = sharedName
            space.createdAt = Date()
            space.updatedAt = Date()
            space.isHouseholdDefault = NSNumber(value: true)

            let list = ShoppingListEntity(context: context)
            try persistence.assign(list, toSameStoreAs: space, in: context)
            list.id = UUID()
            list.title = String(localized: "common.default_list")
            list.status = ShoppingListStatus.active.rawValue
            list.createdAt = Date()
            list.updatedAt = Date()
            list.familySpace = space
        }
        persistence.container.viewContext.processPendingChanges()
        self.sharedID = sharedID
    }
}
