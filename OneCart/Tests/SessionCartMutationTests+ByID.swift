import CoreData
@testable import OneCart
import Testing

// MARK: - Mutations by ID

/// The ID seam the cart screen calls (`CartEditing`): the session resolves the ID against the
/// active cart's rows only, and drops an ID it no longer has.
extension SessionCartMutationTests {
    /// Gives a family created next to the fixture's cart a copy of `product` under the same ID, as
    /// a restored cart keeps its products' IDs (REQ-SYNC-040). Returns the copy's family ID.
    private func addRestoredCopy(
        of product: ProductEntity,
        to fixture: MembershipSessionFixture
    ) async throws -> UUID {
        let id = try #require(product.id)
        let copyID = try await fixture.repository.createFamilySpace(
            name: "Restored", cachedForUserID: fixture.account.id, isHouseholdDefault: false
        )
        let persistence = fixture.persistence
        try await persistence.performBackgroundTask { context in
            let copy = try FamilySpaceRepository.requireFamilySpace(id: copyID, in: context)
            guard let list = copy.activeLists.first else { throw RepositoryError.listNotFound }
            let row = ProductEntity(context: context)
            try persistence.assign(row, toSameStoreAs: copy, in: context)
            row.id = id
            row.name = "Молоко"
            row.quantity = NSNumber(value: 1)
            row.unit = "piece"
            row.category = ProductCategory.other.rawValue
            row.estimatedPrice = NSNumber(value: 0)
            row.isPurchased = NSNumber(value: false)
            row.createdAt = Date()
            row.updatedAt = Date()
            row.familySpace = copy
            row.list = list
        }
        return copyID
    }

    /// Every live row with `id`, by family: (name, purchased).
    private func rows(
        withID id: UUID,
        in fixture: MembershipSessionFixture
    ) async throws -> [UUID: (String, Bool)] {
        try await fixture.persistence.performBackgroundTask { context in
            let request = ProductEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND deletedAt == nil", id as NSUUID)
            var rows: [UUID: (String, Bool)] = [:]
            for row in try context.fetch(request) {
                guard let familyID = row.familySpace?.id else { continue }
                rows[familyID] = (row.displayName, row.isPurchasedValue)
            }
            return rows
        }
    }

    @Test("REQ-SYNC-040: a check and an edit by ID change the active cart's row, not a restored copy's")
    func idMutationsChangeOnlyTheActiveFamilysRow() async throws {
        let fixture = try await MembershipSessionFixture.owner(displayName: "Alex")
        let product = try await addProduct(named: "Молоко", to: fixture)
        let id = try #require(product.id)
        let activeID = try #require(fixture.session.activeFamilySpace?.id)
        let copyID = try await addRestoredCopy(of: product, to: fixture)

        await fixture.session.setPurchased(productID: id, isPurchased: true)
        await fixture.session.updateProduct(id: id, draft: draft(named: "Кефир"))

        let rows = try await rows(withID: id, in: fixture)
        #expect(rows[activeID]?.0 == "Кефир")
        #expect(rows[activeID]?.1 == true)
        #expect(rows[copyID]?.0 == "Молоко")
        #expect(rows[copyID]?.1 == false)
        #expect(fixture.session.userAlert == nil)
    }

    @Test("REQ-SYNC-040: a delete by ID removes the active cart's row and keeps a restored copy's")
    func deleteByIDRemovesOnlyTheActiveFamilysRow() async throws {
        let fixture = try await MembershipSessionFixture.owner(displayName: "Alex")
        let product = try await addProduct(named: "Молоко", to: fixture)
        let id = try #require(product.id)
        let activeID = try #require(fixture.session.activeFamilySpace?.id)
        let copyID = try await addRestoredCopy(of: product, to: fixture)

        await fixture.session.deleteProduct(id: id)

        let rows = try await rows(withID: id, in: fixture)
        #expect(rows[activeID] == nil)
        #expect(rows[copyID]?.0 == "Молоко")
        #expect(fixture.session.products.contains { $0.id == id } == false)
        #expect(fixture.session.userAlert == nil)
    }

    @Test("A mutation by an ID the cart no longer has is dropped without a change or an alert")
    func unknownIDMutationIsDropped() async throws {
        let fixture = try await MembershipSessionFixture.owner()
        let product = try await addProduct(named: "Хлеб", to: fixture)
        let revisionBefore = fixture.session.contentRevision
        let unknownID = UUID()

        await fixture.session.setPurchased(productID: unknownID, isPurchased: true)
        await fixture.session.updateProduct(id: unknownID, draft: draft(named: "Батон"))
        await fixture.session.deleteProduct(id: unknownID)

        #expect(fixture.session.products.map(\.id) == [product.id])
        #expect(fixture.session.products.first?.isPurchasedValue == false)
        #expect(fixture.session.products.first?.displayName == "Хлеб")
        #expect(fixture.session.contentRevision == revisionBefore)
        #expect(fixture.session.userAlert == nil)
    }

    @Test("REQ-WIDGET-010: the widget totals count the lines the cart shows, without a row that has no ID")
    func widgetTotalsSkipRowsWithoutID() async throws {
        let fixture = try await MembershipSessionFixture.owner()
        _ = try await addProduct(named: "Хлеб", to: fixture)
        let familyID = try #require(fixture.personalID)
        let listID = try #require(fixture.session.activeLists.first?.id)
        let persistence = fixture.persistence
        try await persistence.performBackgroundTask { context in
            let family = try FamilySpaceRepository.requireFamilySpace(id: familyID, in: context)
            guard let list = try FamilySpaceRepository.fetchList(id: listID, in: context) else {
                throw RepositoryError.listNotFound
            }
            let row = ProductEntity(context: context)
            try persistence.assign(row, toSameStoreAs: family, in: context)
            row.name = "Ghost"
            row.quantity = NSNumber(value: 1)
            row.unit = "piece"
            row.category = ProductCategory.other.rawValue
            row.estimatedPrice = NSNumber(value: 0)
            row.isPurchased = NSNumber(value: true)
            row.createdAt = Date()
            row.updatedAt = Date()
            row.familySpace = family
            row.list = list
        }
        let context = persistence.container.viewContext
        await context.perform { context.processPendingChanges() }
        try fixture.session.reload()
        #expect(fixture.session.products.count == 2)

        let snapshot = fixture.session.makeWidgetSnapshot(accent: fixture.session.preferences.accentColor)

        #expect(snapshot.totalCount == fixture.session.cartItems(inListID: listID).count)
        #expect(snapshot.totalCount == 1)
        #expect(snapshot.purchasedCount == 0)
    }
}
