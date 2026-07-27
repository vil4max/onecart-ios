import CloudKit
import CoreData
import CoreLocation
@testable import OneCart
import XCTest

final class CloudKitErrorMappingTests: XCTestCase {
    func testCloudKitFamilyInviteShareMessageContainsShareURL() throws {
        let shareURL = try XCTUnwrap(
            URL(string: "https://www.icloud.com/share/onecart-family")
        )
        let invite = try FamilyInviteLink(
            id: XCTUnwrap(UUID(uuidString: "7A4E7A84-38A1-4E6B-8E4C-6A5D0D18B0C2")),
            familyName: "Наша группа",
            url: shareURL
        )

        XCTAssertTrue(invite.shareMessage.contains(shareURL.absoluteString))
        XCTAssertTrue(invite.shareMessage.contains("Наша группа"))
        XCTAssertTrue(invite.shareMessage.contains("корзине"))
        XCTAssertTrue(invite.shareMessage.hasPrefix("OneCart"))
        XCTAssertEqual(invite.shareTitle, "OneCart")
        XCTAssertEqual(invite.expiresAt, .distantFuture)
        XCTAssertFalse(OneCartShareBranding.thumbnailImageData.isEmpty)
    }

    func testCloudKitUserFacingErrorReplacesOpaquePartialFailure() {
        let opaque = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: nil
        )
        let message = CloudKitUserFacingError.message(for: opaque)
        XCTAssertEqual(message, CloudKitUserFacingError.genericSyncFailure)
        XCTAssertFalse(message.lowercased().contains("ckerrordomain"))
    }

    func testCloudKitUserFacingErrorUnwrapsNestedQuotaExceeded() {
        let quota = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.quotaExceeded.rawValue,
            userInfo: nil
        )
        let partial = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: ["record": quota]]
        )
        let message = CloudKitUserFacingError.message(for: partial)
        XCTAssertTrue(message.contains("iCloud"))
        XCTAssertTrue(message.contains("место"))
    }

    func testCloudKitUserFacingErrorDetectsNetworkFailure() {
        let network = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.networkUnavailable.rawValue,
            userInfo: nil
        )
        XCTAssertTrue(CloudKitUserFacingError.isNetworkError(network))
    }

    func testCloudKitUserFacingErrorMapsProductionSchemaFailure() {
        let nested = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.invalidArguments.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Cannot create new type CD_ShoppingList in production schema",
            ]
        )
        let mirroring = NSError(
            domain: NSCocoaErrorDomain,
            code: 134_400,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "The operation couldn’t be completed. Request was aborted because the mirroring delegate never successfully initialized due to error: Partial Failure",
                NSUnderlyingErrorKey: nested,
            ]
        )
        let message = CloudKitUserFacingError.message(for: mirroring)
        XCTAssertEqual(message, CloudKitUserFacingError.productionSchemaMissing)
        XCTAssertTrue(CloudKitUserFacingError.isProductionSchemaFailure(mirroring))
        XCTAssertFalse(message.contains("CD_ShoppingList"))
        XCTAssertFalse(message.contains("mirroring delegate"))
    }

    func testCloudKitUserFacingErrorMapsProductionSchemaFromUserInfoCrumb() {
        let error = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Partial Failure",
                "CKErrorDescription":
                    "Cannot create new type CD_ShoppingList in production schema",
            ]
        )
        XCTAssertTrue(CloudKitUserFacingError.isProductionSchemaFailure(error))
        XCTAssertEqual(
            CloudKitUserFacingError.message(for: error),
            CloudKitUserFacingError.productionSchemaMissing
        )
    }

    func testCloudKitBackendAccessAndInMemoryRestoredAccount() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let backend = CloudKitBackendService(persistence: persistence)
        let privateID = try await repository.createFamilySpace(name: "Моя")
        let privateSpace = try XCTUnwrap(repository.fetchFamilySpace(id: privateID))
        XCTAssertEqual(backend.access(for: privateSpace), .owner)

        let sharedID = UUID()
        try await persistence.performBackgroundTask { context in
            let space = FamilySpace(context: context)
            try persistence.assign(space, to: .shared, in: context)
            space.id = sharedID
            space.name = "Общая"
            space.createdAt = Date()
            space.updatedAt = Date()
        }
        let sharedSpace = try XCTUnwrap(repository.fetchFamilySpace(id: sharedID))
        XCTAssertEqual(backend.access(for: sharedSpace), .member)

        let account = try await backend.restoredAccount(
            appleUserID: "apple-user",
            displayName: "  "
        )
        XCTAssertEqual(account.id, OneCartStableID.uuid(for: "onecart.in-memory-user"))
        XCTAssertEqual(account.displayName, "Пользователь")
    }

    func testCloudKitUserFacingErrorMapsAuthAndPermission() {
        let auth = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.notAuthenticated.rawValue,
            userInfo: nil
        )
        XCTAssertTrue(
            CloudKitUserFacingError.message(for: auth).contains("Apple Account")
        )

        let permission = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.permissionFailure.rawValue,
            userInfo: nil
        )
        XCTAssertTrue(
            CloudKitUserFacingError.message(for: permission).contains("пригласить")
        )

        let constraint = NSError(
            domain: NSCocoaErrorDomain,
            code: NSManagedObjectConstraintMergeError,
            userInfo: nil
        )
        XCTAssertEqual(
            CloudKitUserFacingError.message(for: constraint),
            CloudKitUserFacingError.genericSyncFailure
        )
    }

    func testIsUserFacingCoreDataFailureIgnoresCloudKit() {
        let ck = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.networkFailure.rawValue,
            userInfo: nil
        )
        XCTAssertFalse(PersistenceController.isUserFacingCoreDataFailure(ck))

        let cocoa = NSError(
            domain: NSCocoaErrorDomain,
            code: NSPersistentStoreIncompatibleVersionHashError,
            userInfo: nil
        )
        XCTAssertTrue(PersistenceController.isUserFacingCoreDataFailure(cocoa))

        let migrationText = NSError(
            domain: "OneCartTest",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Core Data migration failed"]
        )
        XCTAssertTrue(PersistenceController.isUserFacingCoreDataFailure(migrationText))
    }
}
