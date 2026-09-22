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
        preferences = DevicePreferences(defaults: defaults)
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}

/// A loaded in-memory store with one family and its household list, for tests whose
/// fakes need real Core Data entities.
@MainActor
struct CartFixture {
    let persistence: PersistenceController
    let repository: FamilySpaceRepository
    let familyID: UUID
    let listID: UUID

    static func make() async throws -> CartFixture {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await repository.createFamilySpace(name: "Family")
        let listID = try #require(try repository.fetchFamilySpace(id: familyID)?.activeLists.first?.id)
        return CartFixture(persistence: persistence, repository: repository, familyID: familyID, listID: listID)
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
        let draft = ProductDraft(
            name: name,
            quantity: 1,
            unit: .piece,
            category: ProductCategory.inferred(from: name),
            estimatedPrice: 0,
            note: ""
        )
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
