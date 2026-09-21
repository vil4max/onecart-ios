import AuthenticationServices
import CloudKit
import CoreData
@testable import OneCart
import XCTest

@MainActor
final class FragileStoreLoadTests: XCTestCase {
    func test_REQ_AUTH_080_loadFailureDoesNotDestroyStoreFiles() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OneCartFragileLoad-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let privateURL = directory.appendingPathComponent("OneCart-private.sqlite")
        try FileManager.default.createDirectory(at: privateURL, withIntermediateDirectories: true)
        let sentinel = directory.appendingPathComponent("sentinel-keep.txt")
        try Data("keep".utf8).write(to: sentinel)

        let persistence = PersistenceController(
            inMemory: false,
            storeDirectoryURL: directory,
            cloudKitEnabled: false
        )

        do {
            try await persistence.load()
            // A fixture that stops failing would leave invariant F1 untested behind a green run.
            XCTFail("Load must fail while a directory occupies the sqlite path")
        } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: privateURL.path))
    }

    func test_REQ_AUTH_080_partialLoadFailureAllowsRetryInSameProcess() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OneCartFragilePartial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Only the shared path is blocked, so the private store loads and the shared one fails.
        let privateURL = directory.appendingPathComponent("OneCart-private.sqlite")
        let sharedURL = directory.appendingPathComponent("OneCart-shared.sqlite")
        try FileManager.default.createDirectory(at: sharedURL, withIntermediateDirectories: true)

        let persistence = PersistenceController(
            inMemory: false,
            storeDirectoryURL: directory,
            cloudKitEnabled: false
        )

        do {
            try await persistence.load()
            XCTFail("Load must fail while a directory occupies the shared sqlite path")
        } catch {}
        XCTAssertFalse(persistence.isLoaded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: privateURL.path))
        XCTAssertTrue(
            persistence.container.persistentStoreCoordinator.persistentStores.isEmpty,
            "A failed load must not leave a half-loaded coordinator behind"
        )

        try FileManager.default.removeItem(at: sharedURL)
        try await persistence.load()

        XCTAssertTrue(persistence.isLoaded)
        XCTAssertNoThrow(try persistence.store(for: .private))
        XCTAssertNoThrow(try persistence.store(for: .shared))
    }

    func test_REQ_AUTH_080_diagnosticsSnapshotCreatedBeforeExplicitHardReset() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OneCartFragileDiag-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = PersistenceController(
            inMemory: false,
            storeDirectoryURL: directory,
            cloudKitEnabled: false
        )
        try await persistence.load()

        let privateURL = directory.appendingPathComponent("OneCart-private.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: privateURL.path))

        let snapshot = try persistence.copyStoreFilesForDiagnostics()
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.path))
        let snapshotPrivate = snapshot.appendingPathComponent("OneCart-private.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotPrivate.path))

        try persistence.hardResetPersistentStores()
        XCTAssertFalse(FileManager.default.fileExists(atPath: privateURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotPrivate.path))
    }

    func test_REQ_AUTH_010_isUserFacingCoreDataFailureIgnoresCloudKit() {
        let ckError = NSError(domain: CKError.errorDomain, code: CKError.Code.networkFailure.rawValue)
        XCTAssertFalse(PersistenceController.isUserFacingCoreDataFailure(ckError))

        let cocoa = NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)
        XCTAssertTrue(PersistenceController.isUserFacingCoreDataFailure(cocoa))
    }

    func test_REQ_AUTH_010_wrappedLoadFailureWithNonEnglishDescriptionIsStoreLoadFailure() {
        let underlying = NSError(
            domain: NSCocoaErrorDomain,
            code: NSPersistentStoreIncompatibleVersionHashError,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Das zum Anlegen des Speichers verwendete Modell passt nicht zum aktuellen Modell.",
            ]
        )
        XCTAssertTrue(
            PersistenceController.isUserFacingCoreDataFailure(
                PersistenceError.loadFailed(underlying: underlying)
            )
        )
    }

    func test_REQ_AUTH_010_postLoadCocoaSaveErrorDoesNotArmHardReset() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OneCartFragilePostLoad-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = PersistenceController(
            inMemory: false,
            storeDirectoryURL: directory,
            cloudKitEnabled: false
        )
        try await persistence.load()
        let containerBeforeRetry = persistence.container

        let defaults = try makeDefaults()
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults,
            appleSignIn: SoftRetryAppleSignIn()
        )
        let saveError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSValidationMissingMandatoryPropertyError
        )
        session.reportWelcomeFailure(session.userFacingMessage(for: saveError))
        await session.retryWelcome()

        // A hard reset replaces the container; the same instance proves the stores were kept.
        XCTAssertTrue(persistence.container === containerBeforeRetry)
    }

    func testShouldWipeLocalStoresWhenCloudKitEnvironmentChanges() {
        XCTAssertFalse(
            PersistenceController.shouldWipeLocalStoresForCloudKitEnvironment(
                previous: "production",
                current: "production",
                storeFilesExist: true,
                isDebugProcess: true
            )
        )
        XCTAssertTrue(
            PersistenceController.shouldWipeLocalStoresForCloudKitEnvironment(
                previous: "development",
                current: "production",
                storeFilesExist: true,
                isDebugProcess: true
            )
        )
        XCTAssertFalse(
            PersistenceController.shouldWipeLocalStoresForCloudKitEnvironment(
                previous: nil,
                current: "production",
                storeFilesExist: true,
                isDebugProcess: true
            )
        )
        XCTAssertFalse(
            PersistenceController.shouldWipeLocalStoresForCloudKitEnvironment(
                previous: nil,
                current: "production",
                storeFilesExist: true,
                isDebugProcess: false
            )
        )
    }

    func test_REQ_AUTH_010_shouldHardResetStoresOnlyForCoreDataWelcomeFailure() {
        XCTAssertFalse(SessionBootstrapper.shouldHardResetStores(for: .signIn, cause: .storeLoad))
        XCTAssertFalse(SessionBootstrapper.shouldHardResetStores(for: .connecting, cause: .storeLoad))
        XCTAssertFalse(
            SessionBootstrapper.shouldHardResetStores(for: .failed("network blip"), cause: .other)
        )
        // The localized Core Data message alone must not arm the wipe.
        XCTAssertFalse(
            SessionBootstrapper.shouldHardResetStores(
                for: .failed(String(localized: "welcome.core_data_failed")),
                cause: .other
            )
        )
        XCTAssertTrue(
            SessionBootstrapper.shouldHardResetStores(
                for: .failed(String(localized: "welcome.core_data_failed")),
                cause: .storeLoad
            )
        )
    }

    func test_REQ_AUTH_010_failureCauseArmsOnlyForStoreLoadCodes() {
        let incompatible = PersistenceError.loadFailed(
            underlying: NSError(
                domain: NSCocoaErrorDomain,
                code: NSPersistentStoreIncompatibleVersionHashError
            )
        )
        XCTAssertEqual(SessionBootstrapper.failureCause(forLoadError: incompatible), .storeLoad)

        let timeout = PersistenceError.loadFailed(
            underlying: NSError(domain: NSCocoaErrorDomain, code: NSPersistentStoreTimeoutError)
        )
        XCTAssertEqual(SessionBootstrapper.failureCause(forLoadError: timeout), .other)

        for code in [
            NSValidationMissingMandatoryPropertyError,
            NSManagedObjectMergeError,
            NSManagedObjectConstraintMergeError,
            NSPersistentStoreSaveError,
        ] {
            let saveError = NSError(domain: NSCocoaErrorDomain, code: code)
            XCTAssertFalse(PersistenceController.isUserFacingCoreDataFailure(saveError), "code \(code)")
        }
    }

    func test_REQ_AUTH_010_storeLoadFailureArmsHardResetAndRetryRecovers() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OneCartFragileArm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // A directory occupying the sqlite path makes `load()` fail with a Cocoa file-read error.
        let privateURL = directory.appendingPathComponent("OneCart-private.sqlite")
        try FileManager.default.createDirectory(at: privateURL, withIntermediateDirectories: true)

        let persistence = PersistenceController(
            inMemory: false,
            storeDirectoryURL: directory,
            cloudKitEnabled: false
        )
        let defaults = try makeDefaults()
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults,
            appleSignIn: SoftRetryAppleSignIn()
        )

        await session.start()
        guard case .failed = session.welcomePhase else {
            return XCTFail("Expected a failed welcome phase, got \(session.welcomePhase)")
        }
        XCTAssertEqual(session.bootstrapper.lastFailureCause, .storeLoad)
        XCTAssertTrue(session.bootstrapper.willHardResetStores(for: session.welcomePhase))
        XCTAssertFalse(persistence.isLoaded)

        await session.retryWelcome()

        XCTAssertTrue(persistence.isLoaded)
        XCTAssertEqual(session.bootstrapper.lastFailureCause, .other)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: privateURL.path, isDirectory: &isDirectory))
        XCTAssertFalse(isDirectory.boolValue)
    }

    func test_REQ_AUTH_010_retryWelcomeDoesNotWipeUnlessCoreDataFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OneCartFragileRetry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = PersistenceController(
            inMemory: false,
            storeDirectoryURL: directory,
            cloudKitEnabled: false
        )
        try await persistence.load()
        let privateURL = directory.appendingPathComponent("OneCart-private.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: privateURL.path))

        let defaults = try makeDefaults()
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults,
            appleSignIn: SoftRetryAppleSignIn()
        )
        session.reportWelcomeFailure("network blip")
        await session.retryWelcome()

        XCTAssertTrue(FileManager.default.fileExists(atPath: privateURL.path))
    }
}

private final class SoftRetryAppleSignIn: AppleSignInAuthenticating, @unchecked Sendable {
    private let credential = AppleSignInCredential(
        userID: "fragile-retry-user",
        email: nil,
        givenName: "Test",
        familyName: nil
    )

    func storedCredential() -> AppleSignInCredential? {
        credential
    }

    func save(_: AppleSignInCredential) {}

    func clearCredential() {}

    func credentialState(for _: String) async -> AppleSignInCredentialState {
        .authorized
    }

    func signIn() async throws -> AppleSignInCredential {
        credential
    }

    func makeCredential(from _: ASAuthorization) throws -> AppleSignInCredential {
        credential
    }
}
