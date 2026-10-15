import Foundation

/// Runs one invite share at a time for Settings (REQ-SHARE-030, REQ-SHARE-110): asks the session
/// for the invite link, hands it to the share sheet, and gives up after `timeout` on the injected
/// clock with the share-timed-out alert.
@MainActor
@Observable
final class InviteShareController {
    var sharePayload: CartSharePayload?
    var isSharing = false
    var alert: UserAlert?

    static let defaultTimeout: Duration = .seconds(48)

    private let membership: any MembershipManaging
    private let haptics: any HapticsPlaying
    private let clock: AppClock
    private let timeout: Duration
    /// Bumps when an attempt starts and when it is retired, so a watchdog or a late result of an
    /// older attempt sees a different value and leaves the newer share alone.
    private var generation = 0
    @ObservationIgnored private var watchdog: Task<Void, Never>?

    init(
        membership: any MembershipManaging,
        haptics: any HapticsPlaying = SystemHaptics(),
        clock: AppClock = .live,
        timeout: Duration = defaultTimeout
    ) {
        self.membership = membership
        self.haptics = haptics
        self.clock = clock
        self.timeout = timeout
    }

    func share() {
        guard !isSharing else { return }
        isSharing = true
        haptics.light()
        CartSyncLog.action.info("shareCart UI start")
        generation += 1
        let attempt = generation
        let work = Task { @MainActor in
            defer { finish(attempt) }
            do {
                let link = try await membership.createFamilyInviteLink()
                guard !Task.isCancelled else { return }
                sharePayload = CartSharePayload(link: link)
                haptics.success()
                CartSyncLog.action.info(
                    "shareCart UI done host=\(link.url.host ?? "-", privacy: .public)"
                )
            } catch is CancellationError {
                CartSyncLog.action.info("shareCart UI cancelled")
                return
            } catch {
                CartSyncLog.action.error(
                    "shareCart UI fail error=\(error.localizedDescription, privacy: .public)"
                )
                // A request the watchdog already timed out can still fail late with another
                // error; the timeout alert, or a newer share, stays in charge.
                guard attempt == generation, !Task.isCancelled else { return }
                haptics.error()
                if CloudKitUserFacingError.isProductionSchemaFailure(error) {
                    alert = .error(CloudKitUserFacingError.productionSchemaMissing)
                } else {
                    alert = .error(membership.userFacingMessage(for: error))
                }
            }
        }
        let clock = clock
        let timeout = timeout
        watchdog = Task { @MainActor in
            try? await clock.sleep(timeout)
            guard attempt == generation else { return }
            work.cancel()
            finish(attempt)
            CartSyncLog.action.error("shareCart UI timeout")
            if let message = OneCartCloudKitError.shareTimedOut.errorDescription {
                alert = .error(message)
            }
        }
    }

    /// Retires the attempt so its watchdog and a late-finishing cancelled task cannot touch a newer share.
    private func finish(_ attempt: Int) {
        guard attempt == generation else { return }
        generation += 1
        isSharing = false
        // A sleeping watchdog would keep this controller alive for the whole timeout.
        watchdog?.cancel()
        watchdog = nil
    }
}
