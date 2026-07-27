import CoreData
@testable import OneCart
import XCTest

extension XCTestCase {
    func makeInMemoryRepository() async throws
        -> (PersistenceController, FamilySpaceRepository)
    {
        let persistence = PersistenceController(inMemory: true)
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

    func assignStore(
        persistence: PersistenceController,
        productID: UUID,
        storeID: UUID
    ) async throws {
        try await persistence.performBackgroundTask { context in
            let productRequest = ProductEntity.fetchRequest()
            productRequest.predicate = NSPredicate(
                format: "id == %@ AND deletedAt == nil",
                productID as NSUUID
            )
            productRequest.fetchLimit = 1
            let storeRequest = StoreEntity.fetchRequest()
            storeRequest.predicate = NSPredicate(
                format: "id == %@ AND deletedAt == nil",
                storeID as NSUUID
            )
            storeRequest.fetchLimit = 1
            guard let product = try context.fetch(productRequest).first,
                  let store = try context.fetch(storeRequest).first
            else {
                throw RepositoryError.productNotFound
            }
            product.store = store
            product.updatedAt = Date()
        }
    }

    func makeDefaults() throws -> UserDefaults {
        let suiteName = "OneCartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
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
