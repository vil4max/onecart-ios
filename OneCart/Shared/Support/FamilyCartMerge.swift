import Foundation

enum FamilyCartMerge {
    static let legacyStarterFamilyNames: Set<String> = [
        "Наша семья",
        "Наша группа",
        AppSession.defaultFamilyName,
    ]

    static func summary(for space: FamilySpace) -> FamilySpaceContentSummary {
        FamilySpaceContentSummary(
            productCount: space.sortedProducts.count,
            storeCount: space.sortedStores.count,
            historyCount: space.sortedHistory.count
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
}

struct FamilySpaceContentSummary: Equatable {
    let productCount: Int
    let storeCount: Int
    let historyCount: Int

    var isEmpty: Bool {
        productCount == 0 && storeCount == 0 && historyCount == 0
    }
}

struct CartMergePrompt: Identifiable, Equatable {
    let id = UUID()
    let privateFamilyID: UUID
    let sharedFamilyID: UUID
    let privateFamilyName: String
    let sharedFamilyName: String
    let summary: FamilySpaceContentSummary
}

enum CartMergeChoice: Equatable {
    case useSharedOnly
    case mergeIntoShared
    case keepPrivate
}
