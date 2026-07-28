import CoreData
@testable import OneCart
import XCTest

@MainActor
final class InviteLinkPreparerTests: XCTestCase {
    func testNotOwnerThrows() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Cart")
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let preparer = InviteLinkPreparer()

        do {
            _ = try await preparer.createInviteLink(
                family: family,
                isOwner: false,
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

    func testOfflineThrows() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        _ = persistence
        let familyID = try await repository.createFamilySpace(name: "Cart")
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let preparer = InviteLinkPreparer()

        do {
            _ = try await preparer.createInviteLink(
                family: family,
                isOwner: true,
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
            isOwner: true,
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
            isOwner: true,
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
            isOwner: true,
            isOnline: true,
            fetch: { link }
        )
        preparer.clear()
        XCTAssertNil(preparer.preparedInviteLink)
        XCTAssertNil(preparer.preparedInviteFamilyID)
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
            isOwner: { true },
            scopeIsPrivate: { _ in true },
            familyStillActive: { $0 == familyID },
            fetch: { _ in throw InviteLinkError.offline }
        )
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNil(preparer.preparedInviteLink)
    }
}
