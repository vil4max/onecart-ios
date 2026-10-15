import Foundation
@testable import OneCart
import Synchronization

/// Records each accept call and succeeds or throws the configured error, standing in for the
/// container's `acceptShareInvitations`.
final class FakeShareInvitationAccepter: ShareInvitationAccepting {
    private struct State {
        var error: (any Error & Sendable)?
        var acceptedShareNames: [[String]] = []
    }

    private let state = Mutex(State())

    init(failingWith error: (any Error & Sendable)? = nil) {
        state.withLock { $0.error = error }
    }

    /// The share record names of each call, in call order.
    var acceptedShareNames: [[String]] {
        state.withLock { $0.acceptedShareNames }
    }

    func acceptShareInvitations(_ invitations: [PendingShareInvitation]) async throws {
        let error = state.withLock { state in
            state.acceptedShareNames.append(invitations.map(\.shareRecordName))
            return state.error
        }
        if let error {
            throw error
        }
    }
}
