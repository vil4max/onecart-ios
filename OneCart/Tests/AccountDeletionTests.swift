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
        XCTAssertGreaterThanOrEqual(stores.attachCount, 1)
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

    func test_deleteAccount_whenAttachFailsAfterCloudSuccess_stillSignsOut() async throws {
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
        XCTAssertEqual(apple.clearCount, 1)
        XCTAssertNil(session.account)
        XCTAssertTrue(session.needsWelcome)
        XCTAssertNil(session.userAlert)
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
