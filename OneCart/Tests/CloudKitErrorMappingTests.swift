import CloudKit
import CoreData
@testable import OneCart
import XCTest

@MainActor
final class CloudKitErrorMappingTests: XCTestCase {
    func test_REQ_SHARE_020_cloudKitFamilyInviteShareMessageContainsShareURL() throws {
        let shareURL = try XCTUnwrap(
            URL(string: "https://www.icloud.com/share/onecart-family")
        )
        let invite = try FamilyInviteLink(
            id: XCTUnwrap(UUID(uuidString: "7A4E7A84-38A1-4E6B-8E4C-6A5D0D18B0C2")),
            familyName: "Наша группа",
            url: shareURL
        )

        let expected = String(
            format: String(localized: "share.message"),
            "Наша группа",
            shareURL.absoluteString
        )
        XCTAssertEqual(invite.shareMessage, expected)
        XCTAssertTrue(invite.shareMessage.contains(shareURL.absoluteString))
        XCTAssertTrue(invite.shareMessage.contains("Наша группа"))
        XCTAssertTrue(invite.shareMessage.hasPrefix("OneCart Family"))
        XCTAssertEqual(invite.shareTitle, "OneCart Family")
        XCTAssertFalse(try XCTUnwrap(ShareThumbnailRenderer(accent: .emerald).thumbnailPNGData()).isEmpty)
    }

    func test_REQ_SHELL_050_cloudKitUserFacingErrorReplacesOpaquePartialFailure() {
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
        XCTAssertEqual(message, String(localized: "sync.quota_exceeded"))
    }

    func test_REQ_SHELL_050_cloudKitUserFacingErrorDetectsNetworkFailure() {
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
            userInfo: [NSLocalizedDescriptionKey: "Cannot create new type CD_ShoppingList in production schema"]
        )
        let mirroring = NSError(
            domain: NSCocoaErrorDomain,
            code: 134_400,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "The operation couldn’t be completed. Request was aborted because the mirroring "
                    + "delegate never successfully initialized due to error: Partial Failure",
                NSUnderlyingErrorKey: nested,
            ]
        )
        let message = CloudKitUserFacingError.message(for: mirroring)
        XCTAssertEqual(message, CloudKitUserFacingError.productionSchemaMissing)
        XCTAssertTrue(CloudKitUserFacingError.isProductionSchemaFailure(mirroring))
        XCTAssertFalse(message.contains("CD_ShoppingList"))
        XCTAssertFalse(message.contains("mirroring delegate"))
    }

    func testCloudKitUserFacingErrorMapsProductionSchemaFieldModify() {
        let schemaMessage = "Cannot create or modify field 'CD_deletedAt' in record 'CD_Product' in production schema"
        let nested = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.invalidArguments.rawValue,
            userInfo: [NSLocalizedDescriptionKey: schemaMessage]
        )
        let partial = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Failed to modify some records",
                CKPartialErrorsByItemIDKey: ["product-1": nested],
            ]
        )
        XCTAssertTrue(CloudKitUserFacingError.isProductionSchemaFailure(partial))
        XCTAssertEqual(
            CloudKitUserFacingError.message(for: partial),
            CloudKitUserFacingError.productionSchemaMissing
        )
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

    func testCloudKitBackendAccessFollowsTheStoreScope() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let backend = CloudKitBackendService(persistence: persistence)
        let privateID = try await repository.createFamilySpace(name: "Моя")
        persistence.container.viewContext.processPendingChanges()
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
        persistence.container.viewContext.processPendingChanges()
        let sharedSpace = try XCTUnwrap(repository.fetchFamilySpace(id: sharedID))
        XCTAssertEqual(backend.access(for: sharedSpace), .member)
    }

    func test_REQ_SHELL_050_cloudKitUserFacingErrorMapsAuthAndPermission() {
        let auth = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.notAuthenticated.rawValue,
            userInfo: nil
        )
        XCTAssertEqual(
            CloudKitUserFacingError.message(for: auth),
            String(localized: "sync.sign_in_apple_account")
        )

        let permission = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.permissionFailure.rawValue,
            userInfo: nil
        )
        XCTAssertEqual(
            CloudKitUserFacingError.message(for: permission),
            String(localized: "sync.share_access_denied")
        )

        let unknownItem = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.unknownItem.rawValue,
            userInfo: nil
        )
        XCTAssertEqual(
            CloudKitUserFacingError.message(for: unknownItem),
            String(localized: "sync.share_access_denied")
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

        let migration = PersistenceError.loadFailed(
            underlying: NSError(domain: NSCocoaErrorDomain, code: NSMigrationError)
        )
        XCTAssertTrue(PersistenceController.isUserFacingCoreDataFailure(migration))

        // Description text never decides: it is localized on device.
        let migrationText = NSError(
            domain: "OneCartTest",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Core Data migration failed"]
        )
        XCTAssertFalse(PersistenceController.isUserFacingCoreDataFailure(migrationText))
    }

    func testMirroringAbortWithCreatedByNameIsSchemaNotLocalDatabase() {
        let schemaMessage =
            "Cannot create or modify field 'CD_createdByName' in record 'CD_Product' in production schema"
        let nested = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.invalidArguments.rawValue,
            userInfo: [NSLocalizedDescriptionKey: schemaMessage]
        )
        let partial = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Failed to modify some records",
                CKPartialErrorsByItemIDKey: ["product-1": nested],
            ]
        )
        let mirroring = NSError(
            domain: NSCocoaErrorDomain,
            code: 134_400,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "The operation couldn’t be completed. Request was aborted because the mirroring "
                    + "delegate never successfully initialized due to error: Partial Failure",
                NSUnderlyingErrorKey: partial,
            ]
        )
        XCTAssertTrue(CloudKitUserFacingError.isProductionSchemaFailure(mirroring))
        XCTAssertFalse(PersistenceController.isUserFacingCoreDataFailure(mirroring))
        XCTAssertEqual(
            CloudKitUserFacingError.message(for: mirroring),
            CloudKitUserFacingError.productionSchemaMissing
        )
    }

    func testProductReloadPolicyTriggersOnlyOnSuccessfulImport() {
        XCTAssertTrue(
            CloudKitProductReloadPolicy.shouldReloadProductsAfterEvent(
                type: .import,
                ended: true,
                error: nil
            )
        )
        XCTAssertFalse(
            CloudKitProductReloadPolicy.shouldReloadProductsAfterEvent(
                type: .export,
                ended: true,
                error: nil
            )
        )
        XCTAssertFalse(
            CloudKitProductReloadPolicy.shouldReloadProductsAfterEvent(
                type: .import,
                ended: false,
                error: nil
            )
        )
        let failure = NSError(domain: CKError.errorDomain, code: CKError.Code.networkUnavailable.rawValue)
        XCTAssertFalse(
            CloudKitProductReloadPolicy.shouldReloadProductsAfterEvent(
                type: .import,
                ended: true,
                error: failure
            )
        )
        XCTAssertFalse(
            CloudKitProductReloadPolicy.shouldReloadProductsAfterEvent(
                type: .setup,
                ended: true,
                error: nil
            )
        )
    }

    /// The process environment is the marker every successful load stamps; the raw values are
    /// what earlier builds stored, so the wipe check keeps matching them.
    func testCloudKitShareEnvironmentStampsProductionAndKnowsTheLegacyMarker() {
        XCTAssertEqual(CloudKitShareEnvironment.process, .production)
        XCTAssertEqual(CloudKitShareEnvironment.production.rawValue, "production")
        XCTAssertEqual(CloudKitShareEnvironment.development.rawValue, "development")
    }
}

extension CloudKitErrorMappingTests {
    func test_REQ_SHELL_050_networkAndSignInClassificationDoesNotDependOnTheLocalizedDescription() {
        let offlineText = NSError(
            domain: "com.example.custom",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "The device is offline; the request timed out"]
        )
        XCTAssertFalse(CloudKitUserFacingError.isNetworkError(offlineText))

        let posixTimeout = NSError(domain: NSPOSIXErrorDomain, code: Int(ETIMEDOUT))
        XCTAssertTrue(CloudKitUserFacingError.isNetworkError(posixTimeout))

        let signedOut = NSError(
            domain: NSCocoaErrorDomain,
            code: 134_400,
            userInfo: [
                NSLocalizedDescriptionKey: "Не удалось выполнить операцию",
                NSUnderlyingErrorKey: NSError(
                    domain: CKError.errorDomain,
                    code: CKError.Code.notAuthenticated.rawValue
                ),
            ]
        )
        XCTAssertEqual(
            CloudKitUserFacingError.message(for: signedOut),
            String(localized: "sync.sign_in_apple_account")
        )

        let notSignedInText = NSError(
            domain: "com.example.custom",
            code: 8,
            userInfo: [NSLocalizedDescriptionKey: "User is not signed in"]
        )
        XCTAssertEqual(CloudKitUserFacingError.message(for: notSignedInText), "User is not signed in")
    }
}
