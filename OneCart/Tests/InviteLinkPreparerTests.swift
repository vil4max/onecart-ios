import CoreData
@testable import OneCart
import XCTest

@MainActor
final class InviteLinkPreparerTests: XCTestCase {
    func testMissingFamilyIDThrows() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Cart")
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        family.id = nil
        let preparer = InviteLinkPreparer()

        do {
            _ = try await preparer.createInviteLink(
                family: family,
                isOnline: true,
                fetch: {
                    XCTFail("fetch must not run")
                    throw InviteLinkError.offline
                }
            )
            XCTFail("expected notOwner")
        } catch let error as InviteLinkError {
            XCTAssertEqual(error, .notOwner)
        }
        XCTAssertNil(preparer.preparedInviteLink)
    }

    func testMemberCanCreateInviteLink() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Cart")
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let preparer = InviteLinkPreparer()
        let link = try FamilyInviteLink(
            id: UUID(),
            familyName: "Cart",
            url: XCTUnwrap(URL(string: "https://www.icloud.com/share/test"))
        )

        let result = try await preparer.createInviteLink(
            family: family,
            isOnline: true,
            fetch: { link }
        )
        XCTAssertEqual(result, link)
        XCTAssertEqual(preparer.preparedInviteLink, link)
    }

    func testOfflineThrows() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        _ = persistence
        let familyID = try await repository.createFamilySpace(name: "Cart")
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let preparer = InviteLinkPreparer()

        do {
            _ = try await preparer.createInviteLink(
                family: family,
                isOnline: false,
                fetch: {
                    XCTFail("fetch must not run")
                    throw InviteLinkError.notOwner
                }
            )
            XCTFail("expected offline")
        } catch let error as InviteLinkError {
            XCTAssertEqual(error, .offline)
        }
    }

    func testCacheHitSkipsFetch() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Cart")
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let preparer = InviteLinkPreparer()
        let link = try FamilyInviteLink(
            id: UUID(),
            familyName: "Cart",
            url: XCTUnwrap(URL(string: "https://www.icloud.com/share/test"))
        )
        var fetchCount = 0

        let first = try await preparer.createInviteLink(
            family: family,
            isOnline: true,
            fetch: {
                fetchCount += 1
                return link
            }
        )
        XCTAssertEqual(first, link)
        XCTAssertEqual(fetchCount, 1)

        let second = try await preparer.createInviteLink(
            family: family,
            isOnline: true,
            fetch: {
                fetchCount += 1
                XCTFail("cache should skip fetch")
                return link
            }
        )
        XCTAssertEqual(second, link)
        XCTAssertEqual(fetchCount, 1)
    }

    func testClearEmptiesCache() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Cart")
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let preparer = InviteLinkPreparer()
        let link = try FamilyInviteLink(
            id: UUID(),
            familyName: "Cart",
            url: XCTUnwrap(URL(string: "https://www.icloud.com/share/test"))
        )
        _ = try await preparer.createInviteLink(
            family: family,
            isOnline: true,
            fetch: { link }
        )
        preparer.clear()
        XCTAssertNil(preparer.preparedInviteLink)
        XCTAssertNil(preparer.preparedInviteFamilyID)
    }

    func testShouldClearCacheOnlyWhenFamilyChanges() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Cart")
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let preparer = InviteLinkPreparer()
        let link = try FamilyInviteLink(
            id: UUID(),
            familyName: "Cart",
            url: XCTUnwrap(URL(string: "https://www.icloud.com/share/test"))
        )
        _ = try await preparer.createInviteLink(
            family: family,
            isOnline: true,
            fetch: { link }
        )

        XCTAssertFalse(preparer.shouldClearCache(forSelectedFamilyID: familyID))
        XCTAssertTrue(preparer.shouldClearCache(forSelectedFamilyID: UUID()))
    }

    func testWarmUpFailureLeavesCacheNil() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Cart")
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let preparer = InviteLinkPreparer()
        preparer.schedulePreparation(
            delayNanoseconds: 5_000_000,
            isOnline: { true },
            family: { family },
            familyStillActive: { $0 == familyID },
            fetch: { _ in throw InviteLinkError.offline }
        )
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNil(preparer.preparedInviteLink)
    }
}
