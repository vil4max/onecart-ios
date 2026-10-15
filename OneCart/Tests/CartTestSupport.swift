import AuthenticationServices
import CoreData
@testable import OneCart
import XCTest

/// Main-actor isolated so main-actor test cases do not send `self` across isolation.
@MainActor
extension XCTestCase {
    func makeInMemoryRepository(clock: AppClock = .live) async throws
        -> (PersistenceController, FamilySpaceRepository)
    {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer(),
            clock: clock
        )
        return (persistence, repository)
    }

    func seedCart(
        repository: FamilySpaceRepository,
        name: String = "Семья",
        draft: ProductDraft? = nil
    ) async throws -> (familyID: UUID, listID: UUID, productID: UUID) {
        let familyID = try await repository.createFamilySpace(name: name)
        let listID = try XCTUnwrap(
            try repository.fetchFamilySpace(id: familyID)?.activeLists.first?.id
        )
        let productID = try await repository.addProduct(
            to: listID,
            draft: draft ?? productDraft()
        )
        return (familyID, listID, productID)
    }

    func productDraft(
        name: String = "Хлеб",
        category: ProductCategory = .other
    ) -> ProductDraft {
        ProductDraft(name: name, category: category)
    }

    func fetchProduct(
        id: UUID,
        repository: FamilySpaceRepository
    ) -> ProductEntity? {
        for space in (try? repository.fetchFamilySpaces()) ?? [] {
            if let product = space.sortedProducts.first(where: { $0.id == id }) {
                return product
            }
        }
        return nil
    }

    /// The only sanctioned way to build an `AppSession` in tests: the defaults and the
    /// sign-in service never fall back to `.standard`, the App Group, or the Keychain, and iCloud
    /// is `InMemoryFamilySharing`, so no test creates a `CKContainer`. The session starts ready,
    /// as after a finished launch, so guards such as the widget drain's `isReady` let tests in.
    func makeTestSession(
        persistence: PersistenceController? = nil,
        defaults: UserDefaults? = nil,
        cloudSharing: (any FamilyCloudSharing)? = nil,
        shareStore: (any CloudKitShareStoring)? = nil,
        appleSignIn: AppleSignInAuthenticating? = nil,
        accountCloudDataDeleter: AccountCloudDataDeleting? = nil,
        accountLocalStorePreparer: AccountLocalStorePreparing? = nil,
        widgetStore: (any WidgetSnapshotStoring)? = nil,
        categoryClassifier: any CategoryClassifying = KeywordCategoryClassifier(),
        shoppingTripBackend: (any ShoppingTripActivityBackend)? = nil,
        shareInbox: (any PendingShareInbox)? = nil,
        shareAccepter: (any ShareInvitationAccepting)? = nil,
        clock: AppClock = .live
    ) throws -> AppSession {
        let defaults = try defaults ?? makeDefaults()
        let persistence = persistence ?? makeInMemoryPersistence()
        let cloudSharing = cloudSharing ?? InMemoryFamilySharing(persistence: persistence)
        let session = try AppSession(
            AppSessionDependencies(
                persistence: persistence,
                preferences: DevicePreferences(defaults: defaults, appGroupDefaults: nil),
                defaults: defaults,
                cloudSharing: cloudSharing,
                shareStore: shareStore ?? FakeCloudKitShareStore(),
                recordPermissions: AllowAllRecordPermissions(),
                appleSignIn: appleSignIn ?? InMemoryAppleSignIn(),
                accountCloudDataDeleter: accountCloudDataDeleter ?? cloudSharing,
                accountLocalStorePreparer: accountLocalStorePreparer ?? persistence,
                widgetStore: widgetStore ?? makeWidgetStore().store,
                // Never the on-device language model or the live ActivityKit backend: a test must
                // not wait on a model or put a trip on the simulator.
                categoryClassifier: categoryClassifier,
                cloudUserIdentity: cloudSharing,
                shoppingTripBackend: shoppingTripBackend ?? FakeShoppingTripBackend(),
                shareInbox: shareInbox ?? LivePendingShareInbox(),
                shareAccepter: shareAccepter ?? FakeShareInvitationAccepter(),
                // Snapshots and seen members land in the test suite; no banner is posted.
                activityNotifier: LiveCartActivityNotifier(defaults: defaults, notificationCenter: nil),
                memberJoinNotifier: LiveMemberJoinNotifier(defaults: defaults, notificationCenter: nil),
                connectivity: FakeConnectivityMonitor(),
                clock: clock
            )
        )
        session.isReady = true
        return session
    }

    /// An "in-memory" store is an ephemeral SQLite file in a temporary directory; teardown removes it.
    nonisolated func makeInMemoryPersistence(cloudKitEnabled: Bool = false) -> PersistenceController {
        let persistence = PersistenceController(isEphemeral: true, cloudKitEnabled: cloudKitEnabled)
        addTeardownBlock {
            removeStoreFiles(of: persistence)
        }
        return persistence
    }

    /// Both halves of the store are isolated: the defaults suite and the pending-purchase
    /// directory, which otherwise resolves to the real App Group container.
    nonisolated func makeWidgetStore() throws -> (store: WidgetSnapshotStore, suite: String, directory: URL) {
        let suite = try makeDefaultsSuiteName()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let store = WidgetSnapshotStore(suiteName: suite, pendingDirectoryURL: directory, reloadTimelines: {})
        return (store, suite, directory)
    }

    nonisolated func makeDefaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: makeDefaultsSuiteName()))
    }

    /// Registers removal of the suite so test runs do not accumulate preference files.
    nonisolated func makeDefaultsSuiteName() throws -> String {
        let suiteName = "OneCartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        return suiteName
    }
}

/// Keychain-free sign-in double; starts signed out, like a clean device.
final class InMemoryAppleSignIn: AppleSignInAuthenticating, @unchecked Sendable {
    private let lock = NSLock()
    private var credential: AppleSignInCredential?

    init(credential: AppleSignInCredential? = nil) {
        self.credential = credential
    }

    func storedCredential() -> AppleSignInCredential? {
        lock.withLock { credential }
    }

    func save(_ credential: AppleSignInCredential) {
        lock.withLock { self.credential = credential }
    }

    func clearCredential() {
        lock.withLock { credential = nil }
    }

    func credentialState(for userID: String) async -> AppleSignInCredentialState {
        // Reads under the lock: `storedCredential()` is a main-actor requirement, this is not.
        lock.withLock { credential }?.userID == userID ? .authorized : .notFound
    }

    func makeCredential(from _: ASAuthorization) throws -> AppleSignInCredential {
        throw AppleSignInError.failed
    }
}

final class DenyAllPermissionAuthorizer: PermissionAuthorizing {
    func canUpdate(_: NSManagedObjectID) -> Bool {
        false
    }

    func canDelete(_: NSManagedObjectID) -> Bool {
        false
    }
}

extension FamilySpaceRepository {
    /// Flips the stored state. Production code always sends the state the user asked for
    /// (`setPurchasedState`); tests without a rendered row check items this way.
    func togglePurchased(id: UUID, familySpaceID: UUID? = nil, participantDisplayName: String?) async throws {
        let current = try await persistence.performBackgroundTask { context -> PurchaseStateProbe? in
            guard let product = try Self.fetchProduct(id: id, familySpaceID: familySpaceID, in: context),
                let familyID = product.familySpace?.id
            else { return nil }
            return PurchaseStateProbe(familyID: familyID, isPurchased: product.isPurchasedValue)
        }
        guard let current else { throw RepositoryError.productNotFound }
        try await setPurchasedState(
            id: id,
            familySpaceID: current.familyID,
            isPurchased: !current.isPurchased,
            participantDisplayName: participantDisplayName
        )
    }
}

private struct PurchaseStateProbe: Sendable {
    let familyID: UUID
    let isPurchased: Bool
}
