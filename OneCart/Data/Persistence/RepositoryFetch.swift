import CoreData
import Foundation

/// Live-row lookups by stable ID that the repositories share, on whatever context they run.
enum RepositoryFetch {
    static func familySpace(
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> FamilySpace? {
        let request = FamilySpace.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "id == %@", id as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func requireFamilySpace(
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> FamilySpace {
        guard let space = try familySpace(id: id, in: context) else {
            throw RepositoryError.familySpaceNotFound
        }
        return space
    }

    static func list(
        id: UUID,
        familySpaceID: UUID? = nil,
        in context: NSManagedObjectContext
    ) throws -> ShoppingListEntity? {
        let request = ShoppingListEntity.fetchRequest()
        var predicates = [
            NSPredicate(format: "id == %@", id as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ]
        if let familySpaceID {
            predicates.append(
                NSPredicate(format: "familySpace.id == %@", familySpaceID as NSUUID)
            )
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func product(
        id: UUID,
        familySpaceID: UUID? = nil,
        in context: NSManagedObjectContext
    ) throws -> ProductEntity? {
        let request = ProductEntity.fetchRequest()
        var predicates = [
            NSPredicate(format: "id == %@", id as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ]
        if let familySpaceID {
            predicates.append(
                NSPredicate(format: "familySpace.id == %@", familySpaceID as NSUUID)
            )
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}
