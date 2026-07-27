import CoreData
import Foundation

enum FamilyCartMerge {
    static let legacyStarterFamilyNames: Set<String> = [
        "Наша семья",
        "Наша группа",
        "Наши покупки",
        "Our shopping",
        "Наші покупки",
        AppSession.defaultFamilyName,
    ]

    static func summary(for space: FamilySpace) -> FamilySpaceContentSummary {
        guard let context = space.managedObjectContext, let spaceID = space.id else {
            return FamilySpaceContentSummary(
                productCount: space.sortedProducts.count,
                storeCount: space.sortedStores.count,
                historyCount: space.sortedHistory.count
            )
        }

        return FamilySpaceContentSummary(
            productCount: count(
                entityName: "Product",
                familySpaceID: spaceID,
                in: context
            ),
            storeCount: count(
                entityName: "Store",
                familySpaceID: spaceID,
                in: context
            ),
            historyCount: count(
                entityName: "PurchaseHistory",
                familySpaceID: spaceID,
                in: context
            )
        )
    }

    static func isDeletableStarter(
        _ space: FamilySpace,
        scope: PersistentStoreScope
    ) -> Bool {
        guard scope == .private else { return false }
        guard space.isHouseholdDefaultValue else { return false }
        return summary(for: space).isEmpty
    }

    static func shouldMigrateLegacyNameToHouseholdDefault(_ name: String) -> Bool {
        legacyStarterFamilyNames.contains(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func count(
        entityName: String,
        familySpaceID: UUID,
        in context: NSManagedObjectContext
    ) -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "familySpace.id == %@", familySpaceID as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ])
        return (try? context.count(for: request)) ?? 0
    }
}

struct FamilySpaceContentSummary: Equatable {
    let productCount: Int
    let storeCount: Int
    let historyCount: Int

    var isEmpty: Bool {
        productCount == 0 && storeCount == 0 && historyCount == 0
    }
}
