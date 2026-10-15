import CoreData
import Foundation
@testable import OneCart
import Synchronization
import Testing

/// Private-store rows always belong to this user; a shared-store row is as editable as the
/// share says, which `RecordPermissionChecking` answers.
@Suite("CloudKitPermissionAuthorizer", .removesStores)
@MainActor
struct CloudKitPermissionAuthorizerTests {
    @Test("REQ-SHARE-010: a private-store row is always editable and the share is never asked")
    func privateScopeSkipsTheChecker() async throws {
        let fixture = try await CartFixture.make()
        let checker = CountingRecordPermissions(allows: false)
        let authorizer = CloudKitPermissionAuthorizer(persistence: fixture.persistence, permissions: checker)
        let objectID = try fixture.family.objectID

        #expect(authorizer.canUpdate(objectID))
        #expect(authorizer.canDelete(objectID))
        #expect(checker.calls == 0)
    }

    @Test("REQ-SHARE-010: a shared-store row follows the share's answer", arguments: [true, false])
    func sharedScopeUsesTheChecker(allows: Bool) async throws {
        let fixture = try await CartFixture.make()
        let checker = CountingRecordPermissions(allows: allows)
        let authorizer = CloudKitPermissionAuthorizer(persistence: fixture.persistence, permissions: checker)
        let objectID = try await insertSharedFamily(in: fixture.persistence)

        #expect(authorizer.canUpdate(objectID) == allows)
        #expect(authorizer.canDelete(objectID) == allows)
        #expect(checker.calls == 2)
    }

    private func insertSharedFamily(in persistence: PersistenceController) async throws -> NSManagedObjectID {
        let sharedID = UUID()
        try await persistence.performBackgroundTask { context in
            let space = FamilySpace(context: context)
            try persistence.assign(space, to: .shared, in: context)
            space.id = sharedID
            space.name = "Общая"
            space.createdAt = Date()
            space.updatedAt = Date()
        }
        let space = try #require(try persistence.container.viewContext.fetch(familySpaceRequest(id: sharedID)).first)
        #expect(persistence.scope(for: space.objectID) == .shared)
        return space.objectID
    }
}

/// Answers every question the same way and counts them.
private final class CountingRecordPermissions: RecordPermissionChecking {
    private let allows: Bool
    private let count = Mutex(0)

    init(allows: Bool) {
        self.allows = allows
    }

    var calls: Int {
        count.withLock { $0 }
    }

    func canUpdateRecord(forManagedObjectWith _: NSManagedObjectID) -> Bool {
        count.withLock { $0 += 1 }
        return allows
    }

    func canDeleteRecord(forManagedObjectWith _: NSManagedObjectID) -> Bool {
        count.withLock { $0 += 1 }
        return allows
    }
}
