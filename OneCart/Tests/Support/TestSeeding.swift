import CoreData
import Foundation
@testable import OneCart

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
    try? FileManager.default.removeItem(at: persistence.storeDirectoryURL)
}

/// For value-type fixtures, which have no deinit: removes the store files once the last
/// copy holding this object is gone.
final class StoreFileCleanup: Sendable {
    private let directory: URL

    init(_ persistence: PersistenceController) {
        directory = persistence.storeDirectoryURL
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
