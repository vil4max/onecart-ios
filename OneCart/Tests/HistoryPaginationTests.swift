import CoreData
@testable import OneCart
import XCTest

@MainActor
final class HistoryPaginationTests: XCTestCase {
    func testFetchHistoryDefaultLimitIs30() async throws {
        let (persistence, repository, familyID) = try await makeHistoryFixture(entryCount: 35)
        let store = CartContentStore(persistence: persistence)
        try store.reloadContent(familySpaceID: familyID)

        XCTAssertEqual(CartContentStore.historyPageSize, 30)
        XCTAssertEqual(store.history.count, 30)
        XCTAssertTrue(store.historyHasMore)
        _ = repository
    }

    func testLoadMoreHistoryAppends() async throws {
        let (persistence, _, familyID) = try await makeHistoryFixture(entryCount: 45)
        let store = CartContentStore(persistence: persistence)
        try store.reloadContent(familySpaceID: familyID)
        XCTAssertEqual(store.history.count, 30)
        XCTAssertTrue(store.historyHasMore)

        try store.loadMoreHistory(familySpaceID: familyID)
        XCTAssertEqual(store.history.count, 45)
        XCTAssertFalse(store.historyHasMore)
    }

    private func makeHistoryFixture(entryCount: Int) async throws -> (
        PersistenceController,
        FamilySpaceRepository,
        UUID
    ) {
        let (persistence, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "History")
        let context = persistence.container.viewContext
        guard let space = try repository.fetchFamilySpace(id: familyID) else {
            throw XCTSkip("missing family space")
        }

        let now = Date()
        for index in 0 ..< entryCount {
            let entry = PurchaseHistoryEntity(context: context)
            try persistence.assign(entry, toSameStoreAs: space, in: context)
            entry.id = UUID()
            entry.total = NSNumber(value: Double(index))
            entry.date = now.addingTimeInterval(TimeInterval(-index))
            entry.createdAt = entry.date
            entry.updatedAt = entry.date
            entry.familySpace = space
            entry.memberNames = "Test"
        }
        try context.save()
        return (persistence, repository, familyID)
    }
}
