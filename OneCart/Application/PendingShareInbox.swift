import Foundation

/// Invitations the delegates received and the session has not accepted yet. The composition root
/// creates one inbox and hands it to the delegates (which fill it) and to the session (which
/// drains it), so no queue outlives its graph or leaks between tests.
@MainActor
protocol PendingShareInbox: AnyObject {
    func enqueue(_ invitation: PendingShareInvitation)
    /// Every queued invitation, oldest first; the inbox is empty afterwards.
    func takeAll() -> [PendingShareInvitation]
    /// Puts back invitations whose accept failed, so the next attempt retries them.
    func requeue(_ invitations: [PendingShareInvitation])
}

/// Main-actor isolated like the delegates, so every enqueue and take is serialized.
@MainActor
final class LivePendingShareInbox: PendingShareInbox {
    private var invitations: [PendingShareInvitation] = []

    func enqueue(_ invitation: PendingShareInvitation) {
        invitations.append(invitation)
    }

    func takeAll() -> [PendingShareInvitation] {
        defer { invitations.removeAll() }
        return invitations
    }

    func requeue(_ invitations: [PendingShareInvitation]) {
        self.invitations.append(contentsOf: invitations)
    }
}
