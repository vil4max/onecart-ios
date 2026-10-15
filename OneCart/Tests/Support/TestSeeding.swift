import CoreData
import Foundation
@testable import OneCart
import Synchronization
import Testing

/// One live family by stable ID, the way the session reads it.
func familySpaceRequest(id: UUID) -> NSFetchRequest<FamilySpace> {
    let request = FamilySpace.fetchRequest()
    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
        NSPredicate(format: "id == %@", id as NSUUID),
        NSPredicate(format: "deletedAt == nil"),
    ])
    request.fetchLimit = 1
    return request
}

func familyMember(
    named name: String,
    access: FamilyAccess = .member,
    isCurrentUser: Bool = false
) -> FamilyMember {
    FamilyMember(
        id: UUID(),
        displayName: name,
        access: access,
        joinedAt: Date(),
        isCurrentUser: isCurrentUser,
        avatarURL: nil,
        bannerURL: nil
    )
}

/// Counts calls of an injected closure, e.g. a system permission request a test must not make.
@MainActor
final class CallCounter {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

/// "In-memory" stores are SQLite files in a temporary directory; a suite that builds one
/// removes it when it is done so test runs do not accumulate store files.
func removeStoreFiles(of persistence: PersistenceController) {
    // Deleting the folder under an open SQLite connection logs "disk I/O error"; the
    // coordinator closes and truncates each loaded store first.
    let coordinator = persistence.container.persistentStoreCoordinator
    coordinator.performAndWait {
        for store in coordinator.persistentStores {
            guard let url = store.url else { continue }
            try? coordinator.destroyPersistentStore(at: url, type: NSPersistentStore.StoreType(rawValue: store.type))
        }
    }
    try? FileManager.default.removeItem(at: persistence.storeDirectoryURL)
}

/// Removes the stores a Swift Testing test opened through a fixture once the test body has
/// returned, so the fixture and every session or view model built on it are released first.
/// A suite whose tests build `CartFixture` or `MembershipSessionFixture` declares `.removesStores`.
struct StoreCleanupTrait: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for _: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        guard testCase != nil else {
            try await function()
            return
        }
        let registry = StoreCleanupRegistry()
        defer { registry.removeAll() }
        try await StoreCleanupRegistry.$current.withValue(registry) {
            try await function()
        }
    }
}

extension Trait where Self == StoreCleanupTrait {
    static var removesStores: Self { StoreCleanupTrait() }
}

final class StoreCleanupRegistry: Sendable {
    @TaskLocal static var current: StoreCleanupRegistry?

    private let stores = Mutex<[PersistenceController]>([])

    /// Hands the store to the running test's cleanup; records an issue outside `.removesStores`.
    static func register(_ persistence: PersistenceController) {
        guard let current else {
            Issue.record("A fixture store needs the .removesStores trait on its suite")
            return
        }
        current.stores.withLock { $0.append(persistence) }
    }

    fileprivate func removeAll() {
        for persistence in stores.withLock({ $0 }) {
            removeStoreFiles(of: persistence)
        }
    }
}
