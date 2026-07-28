import AuthenticationServices
import CloudKit
import CoreData
@testable import OneCart
import XCTest

final class FragileStoreLoadTests: XCTestCase {
    func testLoadFailureDoesNotDestroyStoreFiles() async throws {
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
            throw XCTSkip("Load unexpectedly succeeded with a directory occupying the sqlite path")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: privateURL.path))
        }
    }

    func testDiagnosticsSnapshotCreatedBeforeExplicitHardReset() async throws {
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

    func testIsUserFacingCoreDataFailureIgnoresCloudKit() {
        let ckError = NSError(domain: CKError.errorDomain, code: CKError.Code.networkFailure.rawValue)
        XCTAssertFalse(PersistenceController.isUserFacingCoreDataFailure(ckError))

        let cocoa = NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)
        XCTAssertTrue(PersistenceController.isUserFacingCoreDataFailure(cocoa))
    }

    @MainActor
    func testRetryWelcomeDoesNotWipeUnlessCoreDataFailure() async throws {
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
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults,
            appleSignIn: SoftRetryAppleSignIn()
        )
        session.reportWelcomeFailure("network blip")
        await session.retryWelcome()

        XCTAssertTrue(FileManager.default.fileExists(atPath: privateURL.path))
    }
}

private final class SoftRetryAppleSignIn: AppleSignInAuthenticating {
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
