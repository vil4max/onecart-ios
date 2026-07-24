import Foundation

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

enum FamilyCartMerge {
    static let starterFamilyNames: Set<String> = [
        AppModel.defaultFamilyName,
        "Наша группа",
    ]

    static func isStarterFamilyName(_ name: String) -> Bool {
        starterFamilyNames.contains(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

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
        guard isStarterFamilyName(space.displayName) else { return false }
        return summary(for: space).isEmpty
    }
}
