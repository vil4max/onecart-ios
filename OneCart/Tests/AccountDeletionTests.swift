import AuthenticationServices
import CloudKit
import CoreData
import Foundation
@testable import OneCart
import XCTest

@MainActor
final class AccountDeletionTests: XCTestCase {
    func test_deleteAccount_whenCloudSucceeds_signsOutAndClearsLocalState() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let apple = TrackingAppleSignIn()
        let cloud = RecordingAccountCloudDeleter()
        let stores = RecordingLocalStorePreparer()
        cloud.storeRecorder = stores
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults,
            appleSignIn: apple,
            accountCloudDataDeleter: cloud,
            accountLocalStorePreparer: stores
        )

        let account = OneCartAccount(id: UUID(), displayName: "Max")
        session.account = account
        session.needsWelcome = false
        session.preferences.participantDisplayName = "Max"
        defaults.set(
            UUID().uuidString,
            forKey: session.activeFamilyKey(accountID: account.id)
        )
        defaults.set(["a"], forKey: "onecart.seen-member-ids.\(account.id.uuidString)")

        await session.deleteAccount()

        XCTAssertEqual(stores.detachCount, 1)
        XCTAssertEqual(cloud.callCount, 1)
        XCTAssertEqual(stores.attachCount, 1)
        XCTAssertEqual(stores.events, ["detach", "cloud", "attach"])
        XCTAssertNil(session.account)
        XCTAssertTrue(session.needsWelcome)
        XCTAssertEqual(session.welcomePhase, .signIn)
        XCTAssertEqual(apple.clearCount, 1)
        XCTAssertTrue(session.preferences.participantDisplayName.isEmpty)
        XCTAssertNil(defaults.string(forKey: session.activeFamilyKey(accountID: account.id)))
        XCTAssertNil(defaults.array(forKey: "onecart.seen-member-ids.\(account.id.uuidString)"))
        XCTAssertFalse(session.isDeletingAccount)
        XCTAssertNil(session.userAlert)
    }

    func test_deleteAccount_whenCloudFails_keepsSignedInAndLocalState() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let apple = TrackingAppleSignIn()
        let cloud = RecordingAccountCloudDeleter()
        cloud.errorToThrow = TestAccountDeletionError.simulated
        let stores = RecordingLocalStorePreparer()
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults,
            appleSignIn: apple,
            accountCloudDataDeleter: cloud,
            accountLocalStorePreparer: stores
        )

        let account = OneCartAccount(id: UUID(), displayName: "Max")
        session.account = account
        session.needsWelcome = false
        session.preferences.participantDisplayName = "Max"
        defaults.set("keep", forKey: session.activeFamilyKey(accountID: account.id))

        await session.deleteAccount()

        XCTAssertEqual(stores.detachCount, 1)
        XCTAssertEqual(cloud.callCount, 1)
        XCTAssertEqual(stores.restoreCount, 1)
        XCTAssertEqual(stores.attachCount, 0)
        XCTAssertEqual(session.account?.id, account.id)
        XCTAssertFalse(session.needsWelcome)
        XCTAssertEqual(apple.clearCount, 0)
        XCTAssertEqual(session.preferences.participantDisplayName, "Max")
        XCTAssertEqual(session.userAlert?.kind, .error)
        XCTAssertEqual(session.userAlert?.message, String(localized: "account.delete_failed"))
        XCTAssertFalse(session.isDeletingAccount)
    }

    func test_deleteAccount_whenLocalDetachFails_doesNotCallCloudOrClearCredentials() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let apple = TrackingAppleSignIn()
        let cloud = RecordingAccountCloudDeleter()
        let stores = RecordingLocalStorePreparer()
        stores.detachError = TestAccountDeletionError.simulated
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults,
            appleSignIn: apple,
            accountCloudDataDeleter: cloud,
            accountLocalStorePreparer: stores
        )
        session.account = OneCartAccount(id: UUID(), displayName: "Max")
        session.needsWelcome = false

        await session.deleteAccount()

        XCTAssertEqual(stores.detachCount, 1)
        XCTAssertEqual(cloud.callCount, 0)
        XCTAssertEqual(apple.clearCount, 0)
        XCTAssertNotNil(session.account)
        XCTAssertFalse(session.needsWelcome)
        XCTAssertEqual(session.userAlert?.message, String(localized: "account.delete_failed"))
    }

    func test_deleteAccount_whenAttachFailsAfterCloudSuccess_keepsRetryAvailable() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let apple = TrackingAppleSignIn()
        let cloud = RecordingAccountCloudDeleter()
        let stores = RecordingLocalStorePreparer()
        stores.attachError = TestAccountDeletionError.simulated
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults,
            appleSignIn: apple,
            accountCloudDataDeleter: cloud,
            accountLocalStorePreparer: stores
        )
        session.account = OneCartAccount(id: UUID(), displayName: "Max")
        session.needsWelcome = false

        await session.deleteAccount()

        XCTAssertEqual(cloud.callCount, 1)
        XCTAssertEqual(apple.clearCount, 0)
        XCTAssertNotNil(session.account)
        XCTAssertFalse(session.needsWelcome)
        XCTAssertEqual(session.userAlert?.kind, .error)
        XCTAssertEqual(session.syncState, .failed)

        stores.attachError = nil
        await session.deleteAccount()
        XCTAssertNil(session.account)
        XCTAssertEqual(apple.clearCount, 1)
    }

    func test_deleteAccount_ignoresDuplicateWhileInFlight() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let apple = TrackingAppleSignIn()
        let cloud = RecordingAccountCloudDeleter()
        cloud.delayNanoseconds = 200_000_000
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults,
            appleSignIn: apple,
            accountCloudDataDeleter: cloud
        )
        session.account = OneCartAccount(id: UUID(), displayName: "Max")
        session.needsWelcome = false

        async let first: Void = session.deleteAccount()
        try await Task.sleep(nanoseconds: 20_000_000)
        async let second: Void = session.deleteAccount()
        _ = await (first, second)

        XCTAssertEqual(cloud.callCount, 1)
        XCTAssertNil(session.account)
    }

    func test_deleteAccount_whenOffline_doesNotCallCloudOrSignOut() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: true)
        try await persistence.load()
        let defaults = try makeDefaults()
        let apple = TrackingAppleSignIn()
        let cloud = RecordingAccountCloudDeleter()
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults,
            appleSignIn: apple,
            accountCloudDataDeleter: cloud
        )
        session.account = OneCartAccount(id: UUID(), displayName: "Max")
        session.needsWelcome = false
        session.online = false

        await session.deleteAccount()

        XCTAssertEqual(cloud.callCount, 0)
        XCTAssertNotNil(session.account)
        XCTAssertFalse(session.needsWelcome)
        XCTAssertEqual(apple.clearCount, 0)
        XCTAssertEqual(session.userAlert?.message, String(localized: "account.delete_need_network"))
    }

    func test_deleteAccount_whenMember_leavesSharedBeforeCloudDelete() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let apple = TrackingAppleSignIn()
        let cloud = RecordingAccountCloudDeleter()
        let account = OneCartAccount(id: UUID(), displayName: "Tim")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let privateID = try await repository.createFamilySpace(
            name: "Personal",
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        let sharedID = UUID()
        try await persistence.performBackgroundTask { context in
            let space = FamilySpace(context: context)
            try persistence.assign(space, to: .shared, in: context)
            space.id = sharedID
            space.name = "Family"
            space.createdAt = Date()
            space.updatedAt = Date()
        }
        persistence.container.viewContext.processPendingChanges()
        defaults.set(privateID.uuidString, forKey: "onecart.active-family-space-id.\(account.id.uuidString)")

        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults,
            appleSignIn: apple,
            accountCloudDataDeleter: cloud
        )
        try session.bootstrapTestingSession(account: account)
        try await session.offerSharedCartJoinIfNeededForTesting()
        XCTAssertEqual(session.access, .member)
        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)

        await session.deleteAccount()

        XCTAssertEqual(cloud.callCount, 1)
        XCTAssertNil(session.account)
        XCTAssertTrue(session.needsWelcome)
        let sharedStillPresent = try persistence.container.viewContext.fetch(
            familySpaceRequest(id: sharedID)
        )
        XCTAssertTrue(sharedStillPresent.isEmpty)
    }

    func test_deleteAccount_whenICloudUnavailable_showsSpecificMessage() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: true)
        try await persistence.load()
        let defaults = try makeDefaults()
        let apple = TrackingAppleSignIn()
        let cloud = RecordingAccountCloudDeleter()
        cloud.errorToThrow = OneCartCloudKitError.accountUnavailable(.noAccount)
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults,
            appleSignIn: apple,
            accountCloudDataDeleter: cloud
        )
        session.account = OneCartAccount(id: UUID(), displayName: "Max")
        session.needsWelcome = false
        session.online = true

        await session.deleteAccount()

        XCTAssertNotNil(session.account)
        XCTAssertEqual(apple.clearCount, 0)
        XCTAssertEqual(
            session.userAlert?.message,
            OneCartCloudKitError.accountUnavailable(.noAccount).errorDescription
        )
    }

    func test_deleteAccount_whenCloudFails_preservesUnsyncedDiskProduct() async throws {
        let fixture = try await makeDiskDeletionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.persistence.storeDirectoryURL) }
        fixture.cloud.errorToThrow = TestAccountDeletionError.simulated

        await fixture.session.deleteAccount()

        XCTAssertEqual(fixture.session.account?.id, fixture.account.id)
        XCTAssertEqual(fixture.session.syncState, .failed)
        XCTAssertTrue(fixture.persistence.accountDeletionRecoveryRequired)
        XCTAssertNotNil(fetchProduct(id: fixture.productID, repository: fixture.repository))
        XCTAssertTrue(fixture.persistence.container.persistentStoreDescriptions.allSatisfy {
            $0.cloudKitContainerOptions == nil
        })

        fixture.cloud.errorToThrow = nil
        await fixture.session.deleteAccount()

        XCTAssertEqual(fixture.cloud.callCount, 2)
        XCTAssertNil(fixture.session.account)
        XCTAssertNil(fetchProduct(id: fixture.productID, repository: fixture.repository))
    }

    func test_deleteAccount_whenCloudSucceeds_removesDiskProduct() async throws {
        let fixture = try await makeDiskDeletionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.persistence.storeDirectoryURL) }

        await fixture.session.deleteAccount()

        XCTAssertNil(fixture.session.account)
        XCTAssertTrue(fixture.persistence.isLoaded)
        XCTAssertFalse(fixture.persistence.accountDeletionRecoveryRequired)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.persistence.accountDeletionMarkerURL.path))
        XCTAssertNil(fetchProduct(id: fixture.productID, repository: fixture.repository))
    }

    func test_detachAccountStores_preservesFilesAndRejectsLoadUntilRecovery() async throws {
        let fixture = try await makeDiskDeletionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.persistence.storeDirectoryURL) }
        let privateURL = fixture.persistence.storeDirectoryURL.appendingPathComponent("OneCart-private.sqlite")

        try await fixture.persistence.detachLocalStoresForCloudAccountDeletion()

        XCTAssertTrue(FileManager.default.fileExists(atPath: privateURL.path))
        XCTAssertTrue(fixture.persistence.container.persistentStoreCoordinator.persistentStores.isEmpty)
        do {
            try await fixture.persistence.load()
            XCTFail("Loading must remain blocked while cloud deletion is in flight")
        } catch {
            guard case PersistenceController.AccountDeletionStoreError.deletionInProgress = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        try await fixture.persistence.restoreLocalStoresAfterFailedCloudAccountDeletion()
        XCTAssertNotNil(fetchProduct(id: fixture.productID, repository: fixture.repository))
    }

    func test_deleteAccount_afterConfirmedCloudDeletion_retriesLocalCleanupWithoutCloud() async throws {
        let fixture = try await makeDiskDeletionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.persistence.storeDirectoryURL) }
        try await fixture.persistence.detachLocalStoresForCloudAccountDeletion()
        try fixture.persistence.writeAccountDeletionPhase(.cloudDeleted)
        XCTAssertThrowsError(try fixture.persistence.destroyDetachedAccountStores { _ in
            throw TestAccountDeletionError.simulated
        })
        fixture.session.online = false

        await fixture.session.deleteAccount()

        XCTAssertEqual(fixture.cloud.callCount, 0)
        XCTAssertNil(fixture.session.account)
        XCTAssertNil(fetchProduct(id: fixture.productID, repository: fixture.repository))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.persistence.accountDeletionMarkerURL.path))
    }

    func test_load_whenCleanupPreviouslyFailed_finishesDeletionBeforeOpeningStores() async throws {
        let fixture = try await makeDiskDeletionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.persistence.storeDirectoryURL) }
        try await fixture.persistence.detachLocalStoresForCloudAccountDeletion()
        try fixture.persistence.writeAccountDeletionPhase(.cloudDeleted)

        XCTAssertThrowsError(try fixture.persistence.destroyDetachedAccountStores { _ in
            throw TestAccountDeletionError.simulated
        })
        XCTAssertEqual(try fixture.persistence.readAccountDeletionPhase(), .cloudDeleted)
        let relaunched = PersistenceController(
            storeDirectoryURL: fixture.persistence.storeDirectoryURL,
            cloudKitEnabled: false
        )
        try await relaunched.load()
        let repository = FamilySpaceRepository(
            persistence: relaunched,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )

        XCTAssertNil(fetchProduct(id: fixture.productID, repository: repository))
        XCTAssertFalse(FileManager.default.fileExists(atPath: relaunched.accountDeletionMarkerURL.path))
    }

    func test_start_afterInterruptedDeletion_restoresLocalCartAndLeavesDeletionRetryAvailable() async throws {
        let fixture = try await makeDiskDeletionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.persistence.storeDirectoryURL) }
        try await fixture.persistence.detachLocalStoresForCloudAccountDeletion()
        let relaunched = PersistenceController(
            storeDirectoryURL: fixture.persistence.storeDirectoryURL,
            cloudKitEnabled: true
        )
        let defaults = try makeDefaults()
        let cloud = RecordingAccountCloudDeleter()
        let session = AppSession(
            persistence: relaunched,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults,
            appleSignIn: fixture.apple,
            accountCloudDataDeleter: cloud
        )

        await session.start()

        XCTAssertEqual(session.account?.id, fixture.account.id)
        XCTAssertFalse(session.needsWelcome)
        XCTAssertEqual(session.syncState, .failed)
        XCTAssertFalse(session.isDeletingAccount)
        XCTAssertEqual(session.activeFamilySpace?.id, fixture.familyID)
        XCTAssertTrue(relaunched.container.persistentStoreDescriptions.allSatisfy {
            $0.cloudKitContainerOptions == nil
        })
        XCTAssertEqual(cloud.callCount, 0)
    }

    private func makeDiskDeletionFixture() async throws -> (
        persistence: PersistenceController,
        repository: FamilySpaceRepository,
        session: AppSession,
        cloud: RecordingAccountCloudDeleter,
        apple: TrackingAppleSignIn,
        account: OneCartAccount,
        familyID: UUID,
        productID: UUID
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OneCartAccountDeletion-\(UUID().uuidString)", isDirectory: true)
        let persistence = PersistenceController(storeDirectoryURL: directory, cloudKitEnabled: false)
        try await persistence.load()
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let apple = TrackingAppleSignIn()
        let account = try OneCartAccount(
            id: XCTUnwrap(apple.storedCredential()).accountID,
            displayName: "Max"
        )
        let familyID = try await repository.createFamilySpace(
            name: "Personal",
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        let listID = try XCTUnwrap(repository.fetchFamilySpace(id: familyID)?.activeLists.first?.id)
        let productID = try await repository.addProduct(to: listID, draft: productDraft(name: "Unsynced milk"))
        let defaults = try makeDefaults()
        let cloud = RecordingAccountCloudDeleter()
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults,
            appleSignIn: apple,
            accountCloudDataDeleter: cloud
        )
        try session.bootstrapTestingSession(account: account)
        session.needsWelcome = false
        return (persistence, repository, session, cloud, apple, account, familyID, productID)
    }

    func test_recordZoneIDsForAccountDeletion_skipsDefaultZone() {
        let defaultZone = CKRecordZone.default()
        let custom = CKRecordZone(zoneName: "com.apple.coredata.cloudkit.zone")
        let ids = CloudKitBackendService.recordZoneIDsForAccountDeletion(
            from: [defaultZone, custom]
        )
        XCTAssertEqual(ids, [custom.zoneID])
    }

    func test_isIdempotentAccountDeletionFailure_acceptsZoneNotFoundOnly() {
        let zoneGone = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.zoneNotFound.rawValue
        )
        XCTAssertTrue(CloudKitBackendService.isIdempotentAccountDeletionFailure(zoneGone))

        let shareLeaveText = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.unknownItem.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Item Unavailable. The owner stopped sharing, or your account doesn't have permission.",
            ]
        )
        // unknownItem alone is treated as already-deleted zone for account purge.
        XCTAssertTrue(CloudKitBackendService.isIdempotentAccountDeletionFailure(shareLeaveText))

        let network = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.networkFailure.rawValue
        )
        XCTAssertFalse(CloudKitBackendService.isIdempotentAccountDeletionFailure(network))
    }

    func test_validateAccountDeletionResults_whenEveryZoneSucceeds_completes() {
        let first = CKRecordZone(zoneName: "first").zoneID
        let second = CKRecordZone(zoneName: "second").zoneID

        XCTAssertNoThrow(try CloudKitBackendService.validateAccountDeletionResults(
            [first: .success(()), second: .success(())],
            requestedZoneIDs: [first, second]
        ))
    }

    func test_validateAccountDeletionResults_whenOneZoneFails_propagatesFailure() {
        let first = CKRecordZone(zoneName: "first").zoneID
        let second = CKRecordZone(zoneName: "second").zoneID
        let failure = NSError(domain: CKError.errorDomain, code: CKError.Code.zoneBusy.rawValue)

        XCTAssertThrowsError(try CloudKitBackendService.validateAccountDeletionResults(
            [first: .success(()), second: .failure(failure)],
            requestedZoneIDs: [first, second]
        )) { error in
            XCTAssertEqual(error as NSError, failure)
        }
    }

    func test_validateAccountDeletionResults_whenZonesAlreadyGone_completes() {
        let codes: [CKError.Code] = [.zoneNotFound, .userDeletedZone, .unknownItem]
        let zoneIDs = codes.map { CKRecordZone(zoneName: "gone-\($0.rawValue)").zoneID }
        let results = Dictionary(uniqueKeysWithValues: zip(zoneIDs, codes).map { zoneID, code in
            (zoneID, Result<Void, Error>.failure(NSError(domain: CKError.errorDomain, code: code.rawValue)))
        })

        XCTAssertNoThrow(try CloudKitBackendService.validateAccountDeletionResults(
            results,
            requestedZoneIDs: zoneIDs
        ))
    }

    func test_validateAccountDeletionResults_whenResultMissing_throws() {
        let first = CKRecordZone(zoneName: "first").zoneID
        let missing = CKRecordZone(zoneName: "missing").zoneID

        XCTAssertThrowsError(try CloudKitBackendService.validateAccountDeletionResults(
            [first: .success(())],
            requestedZoneIDs: [first, missing]
        )) { error in
            XCTAssertEqual(
                error as? CloudKitBackendService.AccountDeletionResultError,
                .missingZoneResult
            )
        }
    }

    func test_validateAccountDeletionResults_whenPartialFailureContainsAnotherError_throws() {
        let zoneID = CKRecordZone(zoneName: "partial").zoneID
        let failure = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: [
                "gone": NSError(domain: CKError.errorDomain, code: CKError.Code.zoneNotFound.rawValue),
                "denied": NSError(domain: CKError.errorDomain, code: CKError.Code.permissionFailure.rawValue),
            ]]
        )

        XCTAssertThrowsError(try CloudKitBackendService.validateAccountDeletionResults(
            [zoneID: .failure(failure)],
            requestedZoneIDs: [zoneID]
        )) { error in
            XCTAssertEqual(error as NSError, failure)
        }
    }

    func test_isIdempotentAccountDeletionFailure_whenInspectionLimitExceeded_rejectsUnverifiedResults() {
        let partialErrors = Dictionary(uniqueKeysWithValues: (0 ..< 25).map { index in
            ("zone-\(index)", NSError(domain: CKError.errorDomain, code: CKError.Code.zoneNotFound.rawValue))
        })
        let failure = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: partialErrors]
        )

        XCTAssertFalse(CloudKitBackendService.isIdempotentAccountDeletionFailure(failure))
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
}

private enum TestAccountDeletionError: Error {
    case simulated
}

private final class RecordingAccountCloudDeleter: AccountCloudDataDeleting {
    var callCount = 0
    var errorToThrow: Error?
    var delayNanoseconds: UInt64 = 0
    weak var storeRecorder: RecordingLocalStorePreparer?

    func deletePrivateAccountCloudData() async throws {
        callCount += 1
        storeRecorder?.events.append("cloud")
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let errorToThrow {
            throw errorToThrow
        }
    }
}

private final class RecordingLocalStorePreparer: AccountLocalStorePreparing {
    var detachCount = 0
    var attachCount = 0
    var restoreCount = 0
    var detachError: Error?
    var attachError: Error?
    var events: [String] = []

    func detachLocalStoresForCloudAccountDeletion() async throws {
        detachCount += 1
        events.append("detach")
        if let detachError {
            throw detachError
        }
    }

    func attachEmptyLocalStoresAfterCloudAccountDeletion() async throws {
        attachCount += 1
        events.append("attach")
        if let attachError {
            throw attachError
        }
    }

    func restoreLocalStoresAfterFailedCloudAccountDeletion() async throws {
        restoreCount += 1
        events.append("restore")
    }
}

private final class TrackingAppleSignIn: AppleSignInAuthenticating {
    private var credential: AppleSignInCredential? = AppleSignInCredential(
        userID: "delete-account-user",
        email: nil,
        givenName: "Max",
        familyName: nil
    )
    private(set) var clearCount = 0

    func storedCredential() -> AppleSignInCredential? {
        credential
    }

    func save(_ credential: AppleSignInCredential) {
        self.credential = credential
    }

    func clearCredential() {
        clearCount += 1
        credential = nil
    }

    func credentialState(for _: String) async -> AppleSignInCredentialState {
        .authorized
    }

    func signIn() async throws -> AppleSignInCredential {
        try XCTUnwrap(credential)
    }

    func makeCredential(from _: ASAuthorization) throws -> AppleSignInCredential {
        try XCTUnwrap(credential)
    }
}
