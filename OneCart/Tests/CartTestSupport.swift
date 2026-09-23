import AuthenticationServices
import CoreData
@testable import OneCart
import XCTest

/// Main-actor isolated so main-actor test cases do not send `self` across isolation.
@MainActor
extension XCTestCase {
    func makeInMemoryRepository() async throws
        -> (PersistenceController, FamilySpaceRepository)
    {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
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
        quantity: Double = 1,
        price: Double = 38,
        note: String = ""
    ) -> ProductDraft {
        ProductDraft(
            name: name,
            quantity: quantity,
            unit: .piece,
            category: .other,
            estimatedPrice: price,
            note: note
        )
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
    /// sign-in service never fall back to `.standard`, the App Group, or the Keychain.
    func makeTestSession(
        persistence: PersistenceController? = nil,
        defaults: UserDefaults? = nil,
        appleSignIn: AppleSignInAuthenticating? = nil,
        accountCloudDataDeleter: AccountCloudDataDeleting? = nil,
        accountLocalStorePreparer: AccountLocalStorePreparing? = nil,
        widgetStore: WidgetSnapshotStore? = nil,
        shoppingTripBackend: (any ShoppingTripActivityBackend)? = nil
    ) throws -> AppSession {
        let defaults = try defaults ?? makeDefaults()
        return try AppSession(
            persistence: persistence ?? PersistenceController(inMemory: true, cloudKitEnabled: false),
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults,
            appleSignIn: appleSignIn ?? InMemoryAppleSignIn(),
            accountCloudDataDeleter: accountCloudDataDeleter,
            accountLocalStorePreparer: accountLocalStorePreparer,
            widgetStore: widgetStore ?? makeIsolatedWidgetStore(),
            // Never the live ActivityKit backend: a test must not put a trip on the simulator.
            shoppingTripBackend: shoppingTripBackend ?? FakeShoppingTripBackend()
        )
    }

    /// Both halves of the store are isolated: the defaults suite and the pending-purchase
    /// directory, which otherwise resolves to the real App Group container.
    nonisolated func makeIsolatedWidgetStore() throws -> WidgetSnapshotStore {
        let suiteName = try makeDefaultsSuiteName()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return WidgetSnapshotStore(suiteName: suiteName, pendingDirectoryURL: directory)
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

    func signIn() async throws -> AppleSignInCredential {
        throw AppleSignInError.failed
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
