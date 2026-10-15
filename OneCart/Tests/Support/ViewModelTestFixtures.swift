import CoreData
import Foundation
@testable import OneCart
import Testing

/// Preferences on an isolated defaults suite; the suite is removed with the fixture so test
/// runs do not accumulate preference files, and nothing ever touches `.standard`.
@MainActor
final class IsolatedPreferences {
    let defaults: UserDefaults
    let preferences: DevicePreferences
    private let suiteName: String

    init() throws {
        let suiteName = "OneCartViewModelTests.\(UUID().uuidString)"
        self.suiteName = suiteName
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        preferences = DevicePreferences(defaults: defaults, appGroupDefaults: nil)
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - Value snapshots for the view model fakes

extension CartItem {
    /// A name-only line as the repository stores it: the category is inferred from the name.
    static func line(
        _ name: String,
        purchased: Bool = false,
        id: UUID = UUID(),
        createdByName: String? = nil,
        purchasedByName: String? = nil
    ) -> CartItem {
        CartItem(
            id: id,
            displayName: name,
            category: ProductCategory.inferred(from: name),
            isPurchased: purchased,
            createdByName: createdByName,
            purchasedByName: purchasedByName
        )
    }
}

extension CartList {
    static func general(id: UUID = UUID(), createdAt: Date? = nil) -> CartList {
        CartList(id: id, hasStore: false, createdAt: createdAt)
    }

    static func store(id: UUID = UUID(), createdAt: Date?) -> CartList {
        CartList(id: id, hasStore: true, createdAt: createdAt)
    }
}

extension HistoryLine {
    /// An archived name-only line bought at `moment`; the category is inferred from the name.
    static func bought(
        _ name: String,
        at moment: Date,
        id: HistoryLine.Identity = .purchase(familyID: UUID(), productID: UUID()),
        createdByName: String? = nil,
        purchasedByName: String? = "Alex"
    ) -> HistoryLine {
        HistoryLine(
            id: id,
            displayName: name,
            category: ProductCategory.inferred(from: name),
            purchaseMoment: moment,
            createdByName: createdByName,
            purchasedByName: purchasedByName
        )
    }
}

extension FamilySpace {
    /// An unsaved family outside any context. `activeFamilySpace` is still an entity, but the
    /// cart screen only tests it for presence, so its tests need no store.
    static func detached() throws -> FamilySpace {
        let entity = try #require(OneCartManagedObjectModel.makeModel().entitiesByName["FamilySpace"])
        return FamilySpace(entity: entity, insertInto: nil)
    }
}

/// A loaded in-memory store with one family and its household list, for repository and
/// mapping tests that need real Core Data entities.
@MainActor
struct CartFixture {
    let persistence: PersistenceController
    let repository: FamilySpaceRepository
    let familyID: UUID
    let listID: UUID

    /// The store is removed by the suite's `.removesStores` scope after the test returns.
    static func make() async throws -> CartFixture {
        let persistence = PersistenceController(isEphemeral: true, cloudKitEnabled: false)
        StoreCleanupRegistry.register(persistence)
        try await persistence.load()
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await repository.createFamilySpace(name: "Family")
        let listID = try #require(try repository.fetchFamilySpace(id: familyID)?.activeLists.first?.id)
        return CartFixture(
            persistence: persistence,
            repository: repository,
            familyID: familyID,
            listID: listID
        )
    }

    var family: FamilySpace {
        get throws {
            try #require(try repository.fetchFamilySpace(id: familyID))
        }
    }

    var list: ShoppingListEntity {
        get throws {
            try #require(family.activeLists.first { $0.id == listID })
        }
    }

    var products: [ProductEntity] {
        get throws {
            try family.sortedProducts
        }
    }

    var history: [PurchaseHistoryEntity] {
        get throws {
            try family.sortedHistory
        }
    }

    @discardableResult
    func addProduct(named name: String, purchased: Bool = false) async throws -> UUID {
        let draft = ProductDraft.nameOnly(name)
        let id = try await repository.addProduct(to: listID, draft: draft)
        if purchased {
            try await repository.togglePurchased(id: id, participantDisplayName: "Alex")
        }
        await settle()
        return id
    }

    func product(id: UUID) throws -> ProductEntity {
        try #require(products.first { $0.id == id })
    }

    /// Lets background saves merge into the view context before entities are read.
    func settle() async {
        let context = persistence.container.viewContext
        await context.perform {
            context.processPendingChanges()
        }
    }
}
