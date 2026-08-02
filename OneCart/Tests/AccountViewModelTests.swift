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
}
