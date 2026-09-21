import CloudKit
import CoreData
@testable import OneCart
import XCTest

@MainActor
final class SharedCartJoinTests: XCTestCase {
    func test_REQ_SHARE_090_emptyPrivateAutoAdoptsShared() async throws {
        let (session, _, privateID, sharedID) = try await makeJoinFixture(
            privateName: "Моя",
            sharedName: "Семейная",
            sharedProduct: "Test 1"
        )

        try await session.offerSharedCartJoinIfNeededForTesting()

        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)
        XCTAssertEqual(session.familySpaces.map(\.id), [sharedID])
        XCTAssertNotNil(try session.persistence.container.viewContext.fetch(
            familySpaceRequest(id: privateID)
        ).first)
        XCTAssertEqual(Set(session.products.map(\.displayName)), ["Test 1"])
    }

    func test_REQ_SHARE_090_privateContentIsNotMergedIntoSharedOnAdopt() async throws {
        let (session, _, privateID, sharedID) = try await makeJoinFixture(
            privateName: "Моя",
            sharedName: "Семейная",
            privateProduct: "Мой хлеб",
            sharedProduct: "Test 1"
        )

        try await session.offerSharedCartJoinIfNeededForTesting()

        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)
        XCTAssertEqual(session.familySpaces.map(\.id), [sharedID])
        XCTAssertNotNil(try session.persistence.container.viewContext.fetch(
            familySpaceRequest(id: privateID)
        ).first)
        XCTAssertEqual(Set(session.products.map(\.displayName)), ["Test 1"])
    }

    func test_REQ_SHARE_090_ensureHouseholdAdoptsSharedEvenWhenPrivateActive() async throws {
        let (session, _, privateID, sharedID) = try await makeJoinFixture(
            privateName: "Моя",
            sharedName: "Семейная",
            sharedProduct: "Test 1"
        )
        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)
        XCTAssertEqual(session.familySpaces.map(\.id), [sharedID])

        await session.ensureHouseholdCartIfNeeded()

        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)
        XCTAssertEqual(session.access, .member)
        XCTAssertNotNil(try session.persistence.container.viewContext.fetch(
            familySpaceRequest(id: privateID)
        ).first)
    }

    func test_REQ_SHARE_090_reloadPrefersSharedOverStoredPrivate() async throws {
        let (session, _, _, sharedID) = try await makeJoinFixture(
            privateName: "Моя",
            sharedName: "Семейная",
            sharedProduct: "Test 1"
        )

        try session.reload(preferredFamilySpaceID: sharedID)

        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)
        XCTAssertEqual(session.familySpaces.map(\.id), [sharedID])
    }

    func test_REQ_SHARE_090_reloadSwitchesToSharedWhenSharedAppearsLater() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Саша")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let privateID = try await repository.createFamilySpace(
            name: "Моя",
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        defaults.set(privateID.uuidString, forKey: activeFamilyKey(accountID: account.id))
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        XCTAssertEqual(session.activeFamilySpace?.id, privateID)

        let sharedID = try await seedSharedCart(
            persistence: persistence,
            name: "Семейная",
            productName: "Test 1"
        )
        try session.reload(preferredFamilySpaceID: privateID)

        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)
        XCTAssertEqual(session.familySpaces.map(\.id), [sharedID])
        XCTAssertEqual(Set(session.products.map(\.displayName)), ["Test 1"])
    }

    func test_REQ_SHARE_090_alreadyOnSharedStaysShared() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Саша")
        let sharedID = try await seedSharedCart(
            persistence: persistence,
            name: "Семейная",
            productName: "Test 1"
        )
        defaults.set(sharedID.uuidString, forKey: activeFamilyKey(accountID: account.id))

        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        try await session.offerSharedCartJoinIfNeededForTesting()

        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)
        XCTAssertEqual(Set(session.products.map(\.displayName)), ["Test 1"])
    }

    func test_REQ_SHARE_090_adoptSelectsSharedWithoutMergingPrivateContent() async throws {
        let (session, _, privateID, sharedID) = try await makeJoinFixture(
            privateName: "Моя",
            sharedName: "Семейная",
            privateProduct: "Мой хлеб",
            sharedProduct: nil,
            includeSharedList: false
        )

        try await session.offerSharedCartJoinIfNeededForTesting()

        XCTAssertEqual(
            session.activeFamilySpace?.id,
            sharedID,
            "Invitee must join shared cart; personal stays hidden on disk"
        )
        XCTAssertEqual(
            persistenceScope(for: session.activeFamilySpace, in: session.persistence),
            .shared
        )
        XCTAssertNotNil(try session.persistence.container.viewContext.fetch(
            familySpaceRequest(id: privateID)
        ).first)
        XCTAssertTrue(session.products.isEmpty)
    }

    func test_REQ_SYNC_040_acceptSelectsNewestSharedWithoutDeletingOtherFamilies() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Саша")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )

        let privateID = try await repository.createFamilySpace(
            name: "Моя",
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        let privateListID = try XCTUnwrap(
            repository.fetchFamilySpace(id: privateID)?.activeLists.first?.id
        )
        _ = try await repository.addProduct(
            to: privateListID,
            draft: productDraft(name: "Мой хлеб")
        )

        let oldSharedID = try await seedSharedCart(
            persistence: persistence,
            name: "Старая семейная",
            productName: "Old",
            updatedAt: Date().addingTimeInterval(-3600)
        )
        let newSharedID = try await seedSharedCart(
            persistence: persistence,
            name: "Новая семейная",
            productName: "New",
            updatedAt: Date()
        )
        defaults.set(oldSharedID.uuidString, forKey: activeFamilyKey(accountID: account.id))

        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        XCTAssertEqual(session.activeFamilySpace?.id, oldSharedID)
        XCTAssertEqual(session.access, .member)

        try await session.offerSharedCartJoinIfNeededForTesting()

        XCTAssertEqual(session.activeFamilySpace?.id, newSharedID)
        XCTAssertEqual(session.access, .member)
        XCTAssertNotNil(try session.persistence.container.viewContext.fetch(
            familySpaceRequest(id: oldSharedID)
        ).first)
        let oldFamily = try XCTUnwrap(repository.fetchFamilySpace(id: oldSharedID))
        XCTAssertNil(oldFamily.deletedAt)
        XCTAssertEqual(oldFamily.activeLists.flatMap(\.sortedProducts).map(\.displayName), ["Old"])
        XCTAssertNotNil(try session.persistence.container.viewContext.fetch(
            familySpaceRequest(id: privateID)
        ).first)
        XCTAssertEqual(Set(session.products.map(\.displayName)), ["New"])
    }

    func test_REQ_SYNC_030_refreshFromServerPicksUpToggledPurchasedState() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Саша")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await repository.createFamilySpace(
            name: "Семейная",
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        let listID = try XCTUnwrap(
            repository.fetchFamilySpace(id: familyID)?.activeLists.first?.id
        )
        let productID = try await repository.addProduct(
            to: listID,
            draft: productDraft(name: "Test 1")
        )
        defaults.set(familyID.uuidString, forKey: activeFamilyKey(accountID: account.id))

        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        XCTAssertEqual(session.products.filter(\.isPurchasedValue).count, 0)

        try await repository.togglePurchased(id: productID, participantDisplayName: "Анна")
        await session.refreshFromServer()

        XCTAssertEqual(session.products.filter(\.isPurchasedValue).count, 1)
        let refreshed = try XCTUnwrap(session.products.first { $0.id == productID })
        XCTAssertTrue(refreshed.isPurchasedValue)
        XCTAssertEqual(refreshed.purchasedByName, "Анна")
        XCTAssertEqual(
            session.products(inListID: listID).filter(\.isPurchasedValue).count,
            1
        )
    }

    private func makeJoinFixture(
        privateName: String,
        sharedName: String,
        privateProduct: String? = nil,
        sharedProduct: String? = nil,
        includeSharedList: Bool = true
    ) async throws -> (AppSession, OneCartAccount, UUID, UUID) {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Саша")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )

        let privateID = try await repository.createFamilySpace(
            name: privateName,
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        if let privateProduct {
            let listID = try XCTUnwrap(
                repository.fetchFamilySpace(id: privateID)?.activeLists.first?.id
            )
            _ = try await repository.addProduct(
                to: listID,
                draft: productDraft(name: privateProduct)
            )
        }

        let sharedID = try await seedSharedCart(
            persistence: persistence,
            name: sharedName,
            productName: sharedProduct,
            includeList: includeSharedList
        )
        defaults.set(privateID.uuidString, forKey: activeFamilyKey(accountID: account.id))

        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        persistence.container.viewContext.processPendingChanges()
        return (session, account, privateID, sharedID)
    }

    private func familySpaceRequest(id: UUID) -> NSFetchRequest<FamilySpace> {
        let request = FamilySpace.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "id == %@", id as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ])
        request.fetchLimit = 1
        return request
    }

    private func persistenceScope(
        for space: FamilySpace?,
        in persistence: PersistenceController
    ) -> PersistentStoreScope? {
        guard let space else { return nil }
        return persistence.scope(for: space)
    }
}

@MainActor
final class SharedCartSelectionTests: XCTestCase {
    func test_REQ_SYNC_040_cloudReloadKeepsChosenSharedCartWhenAnotherSharedCartIsNewer() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Саша")
        let chosenID = try await seedSharedCart(
            persistence: persistence,
            name: "Выбранная",
            productName: "Chosen",
            updatedAt: Date().addingTimeInterval(-3600)
        )
        let otherID = try await seedSharedCart(
            persistence: persistence,
            name: "Другая",
            productName: "Other",
            updatedAt: Date()
        )
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        try await session.offerSharedCartJoinIfNeededForTesting()
        let chosen = try XCTUnwrap(session.familySpaces.first { $0.id == chosenID })
        session.setActiveFamilySpace(chosen)
        XCTAssertEqual(session.activeFamilySpace?.id, chosenID)

        // Every cloud import runs the same join offer; the other cart stays the most recently edited.
        try await session.offerSharedCartJoinIfNeededForTesting()
        try await session.offerSharedCartJoinIfNeededForTesting()

        XCTAssertEqual(session.activeFamilySpace?.id, chosenID)
        XCTAssertEqual(
            defaults.string(forKey: activeFamilyKey(accountID: account.id)),
            chosenID.uuidString
        )
        XCTAssertEqual(Set(session.products.map(\.displayName)), ["Chosen"])
        XCTAssertEqual(Set(session.familySpaces.compactMap(\.id)), [chosenID, otherID])
    }

    func test_REQ_SHARE_090_newlyJoinedSharedCartBecomesActiveOverCurrentSharedCart() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Саша")
        let currentID = try await seedSharedCart(
            persistence: persistence,
            name: "Текущая",
            productName: "Current",
            updatedAt: Date()
        )
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        try await session.offerSharedCartJoinIfNeededForTesting()
        XCTAssertEqual(session.activeFamilySpace?.id, currentID)

        // Older updatedAt proves selection follows the join, not the sort order.
        let joinedID = try await seedSharedCart(
            persistence: persistence,
            name: "Новая",
            productName: "Joined",
            updatedAt: Date().addingTimeInterval(-3600)
        )
        try await session.offerSharedCartJoinIfNeededForTesting()

        XCTAssertEqual(session.activeFamilySpace?.id, joinedID)
        XCTAssertEqual(Set(session.products.map(\.displayName)), ["Joined"])
    }
}

@MainActor
private extension XCTestCase {
    func seedSharedCart(
        persistence: PersistenceController,
        name: String,
        productName: String?,
        includeList: Bool = true,
        updatedAt: Date = Date()
    ) async throws -> UUID {
        let sharedID = UUID()
        let listID = UUID()
        try await persistence.performBackgroundTask { context in
            let space = FamilySpace(context: context)
            try persistence.assign(space, to: .shared, in: context)
            space.id = sharedID
            space.name = name
            space.createdAt = updatedAt
            space.updatedAt = updatedAt
            space.isHouseholdDefault = NSNumber(value: true)

            guard includeList else { return }

            let list = ShoppingListEntity(context: context)
            try persistence.assign(list, toSameStoreAs: space, in: context)
            list.id = listID
            list.title = String(localized: "common.default_list")
            list.status = ShoppingListStatus.active.rawValue
            list.createdAt = updatedAt
            list.updatedAt = updatedAt
            list.familySpace = space

            if let productName {
                let product = ProductEntity(context: context)
                try persistence.assign(product, toSameStoreAs: space, in: context)
                product.id = UUID()
                product.name = productName
                product.quantity = NSNumber(value: 1)
                product.unit = ProductUnit.piece.rawValue
                product.category = ProductCategory.other.rawValue
                product.estimatedPrice = NSNumber(value: 0)
                product.isPurchased = NSNumber(value: false)
                product.createdAt = updatedAt
                product.updatedAt = updatedAt
                product.familySpace = space
                product.list = list
            }
        }
        persistence.container.viewContext.processPendingChanges()
        return sharedID
    }

    func activeFamilyKey(accountID: UUID) -> String {
        "onecart.active-family-space-id.\(accountID.uuidString)"
    }
}

@MainActor
final class ShareLinkJoinACLTests: XCTestCase {
    func test_REQ_SHARE_080_backgroundInvitePreparation_keepsRevokedShareClosed() {
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        share.publicPermission = .none
        XCTAssertThrowsError(try FamilyInviteLinkBuilder.linkForOpenShare(share, displayName: "Family")) { error in
            guard case OneCartCloudKitError.inviteDoorClosed = error else {
                return XCTFail("Expected the revoked invite to remain unavailable")
            }
        }
        XCTAssertEqual(share.publicPermission, .none)
    }

    func test_REQ_SHARE_060_applyReadWriteACLPreservesRevokedPublicPermission() {
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        share.publicPermission = .none
        XCTAssertFalse(OneCartShareLinkJoin.applyReadWriteACL(to: share))
        XCTAssertEqual(share.publicPermission, .none)
    }

    func test_REQ_SHARE_070_applyReadWriteACLReopensDoorWhenRequested() {
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        share.publicPermission = .none
        XCTAssertTrue(OneCartShareLinkJoin.applyReadWriteACL(to: share, reopenInviteDoor: true))
        XCTAssertEqual(share.publicPermission, .readWrite)
    }

    func test_REQ_SHARE_060_revokeIsDoorCloseNotGuestBan() {
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        share.publicPermission = .readWrite
        share.publicPermission = .none
        XCTAssertEqual(share.publicPermission, .none)
        XCTAssertTrue(OneCartShareLinkJoin.applyReadWriteACL(to: share, reopenInviteDoor: true))
        XCTAssertEqual(share.publicPermission, .readWrite)
    }

    func testApplyReadWriteACLUpgradesUnknownOrReadOnlyPublicPermission() {
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        share.publicPermission = .readOnly
        XCTAssertTrue(OneCartShareLinkJoin.applyReadWriteACL(to: share))
        XCTAssertEqual(share.publicPermission, .readWrite)
    }

    func testApplyReadWriteACLIsIdempotent() {
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        share.publicPermission = .readWrite
        XCTAssertFalse(OneCartShareLinkJoin.applyReadWriteACL(to: share))
    }

    /// The participant upgrade loop is not reachable from a unit test: `CKShare.Participant`
    /// has no public initializer, and `oneTimeURLParticipant()` raises without the
    /// `com.apple.developer.icloud-extended-share-access` entitlement. This covers only the
    /// owner-only share, which must report no change and leave the owner alone.
    func testApplyReadWriteACLLeavesOwnerOnlyOpenShareUnchanged() {
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        share.publicPermission = .readWrite
        XCTAssertEqual(share.participants.map(\.role), [.owner])
        let ownerPermission = share.owner.permission

        XCTAssertFalse(OneCartShareLinkJoin.applyReadWriteACL(to: share))
        XCTAssertEqual(share.publicPermission, .readWrite)
        XCTAssertEqual(share.participants.map(\.role), [.owner])
        XCTAssertEqual(share.owner.permission, ownerPermission)
    }
}

@MainActor
final class MemberJoinDiffTests: XCTestCase {
    func test_REQ_WIDGET_030_firstSnapshotSeedsWithoutNotify() {
        let member = FamilyMember(
            id: UUID(),
            displayName: "Sam",
            access: .member,
            joinedAt: Date(),
            isCurrentUser: false,
            avatarURL: nil,
            bannerURL: nil
        )
        let diff = MemberJoinDiff.evaluate(
            previousIDs: [],
            storedIDs: [],
            current: [member]
        )
        XCTAssertFalse(diff.shouldNotify)
        XCTAssertTrue(diff.newcomerIDs.isEmpty)
        XCTAssertEqual(diff.nextStoredIDs, [member.id])
    }

    func test_REQ_WIDGET_030_newMemberAfterBaselineNotifies() {
        let existingID = UUID()
        let newID = UUID()
        let existing = FamilyMember(
            id: existingID,
            displayName: "Alex",
            access: .owner,
            joinedAt: Date(),
            isCurrentUser: true,
            avatarURL: nil,
            bannerURL: nil
        )
        let joined = FamilyMember(
            id: newID,
            displayName: "Sam",
            access: .member,
            joinedAt: Date(),
            isCurrentUser: false,
            avatarURL: nil,
            bannerURL: nil
        )
        let diff = MemberJoinDiff.evaluate(
            previousIDs: [existingID],
            storedIDs: [existingID],
            current: [existing, joined]
        )
        XCTAssertTrue(diff.shouldNotify)
        XCTAssertEqual(diff.newcomerIDs, [newID])
        XCTAssertEqual(diff.nextStoredIDs, [existingID, newID])
    }
}
