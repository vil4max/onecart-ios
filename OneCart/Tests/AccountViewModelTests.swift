@testable import OneCart
import XCTest

@MainActor
final class AccountViewModelTests: XCTestCase {
    func testOwnerGatesEnableRenameAndRevoke() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        session.account = OneCartAccount(id: UUID(), displayName: "Owner")
        session.access = .owner

        let viewModel = AccountViewModel(session: session)
        XCTAssertTrue(viewModel.canRenameCart)
        XCTAssertTrue(viewModel.canRevokeInvite)
        XCTAssertTrue(viewModel.canOwnerManageMembers)
        XCTAssertFalse(viewModel.canLeaveCart)
    }

    func testMemberGatesEnableLeaveOnly() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        session.account = OneCartAccount(id: UUID(), displayName: "Guest")
        session.access = .member

        let viewModel = AccountViewModel(session: session)
        XCTAssertFalse(viewModel.canRenameCart)
        XCTAssertFalse(viewModel.canRevokeInvite)
        XCTAssertFalse(viewModel.canOwnerManageMembers)
        XCTAssertTrue(viewModel.canLeaveCart)
    }

    func testFinishedShareWatchdogDoesNotTimeOutNextShare() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        let viewModel = AccountViewModel(session: session, shareTimeoutNanoseconds: 200_000_000)

        // Without an active family the first share fails immediately.
        viewModel.shareCart()
        for _ in 0 ..< 50 where viewModel.isSharing {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertFalse(viewModel.isSharing)
        XCTAssertNotNil(viewModel.shareAlert)

        // Stand in for a second share that is still in flight when the first deadline passes.
        viewModel.shareAlert = nil
        viewModel.isSharing = true
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertTrue(viewModel.isSharing)
        XCTAssertNil(viewModel.shareAlert)
    }
}
