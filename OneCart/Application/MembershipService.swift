import CoreData
import Foundation
import OSLog

struct MembershipDependencies {
    let persistence: PersistenceController
    let cloudSharing: any FamilyCloudSharing
    let families: any FamilyRepository
    let shareOrchestrator: FamilyShareOrchestrator
    let invitePreparer: InviteLinkPreparer
    let household: HouseholdCartCoordinator
    let clock: AppClock
}

/// The membership flows Settings starts: the invite link and revoking it, renaming the cart,
/// removing a member, and a guest leaving the shared cart with the recovery after a leave that
/// timed out. Owns the leave in flight and that recovery.
@MainActor
final class MembershipService {
    nonisolated static let leaveRecoveryPasses = 8
    nonisolated static let leaveRecoveryInterval: Duration = .milliseconds(1500)

    /// The purge triggers cloud reloads while the leave is in flight; they must not read the
    /// vanishing shared cart as one the owner removed.
    private(set) var isLeavingSharedCart = false
    /// Retries the fallback to the personal cart after a leave timed out; sign-out cancels it.
    private(set) var leaveRecoveryTask: Task<Void, Never>?
    /// Fallback passes run after a leave timed out; tests wait on it instead of yielding.
    private(set) var leaveRecoveryPassCount = 0

    private weak var context: (any MembershipContext)?
    private let dependencies: MembershipDependencies

    init(context: any MembershipContext, dependencies: MembershipDependencies) {
        self.context = context
        self.dependencies = dependencies
    }

    /// Replaces the running recovery, if any.
    func trackLeaveRecovery(_ task: Task<Void, Never>) {
        leaveRecoveryTask?.cancel()
        leaveRecoveryTask = task
    }

    func cancelLeaveRecovery() {
        leaveRecoveryTask?.cancel()
        leaveRecoveryTask = nil
    }

    private func isShared(_ family: FamilySpace) -> Bool {
        dependencies.persistence.scope(for: family) == .shared
    }
}

// MARK: - Invite door, name and members

extension MembershipService {
    func createFamilyInviteLink() async throws -> FamilyInviteLink {
        guard let context, let family = context.activeFamilySpace else {
            CartSyncLog.action.error("shareInvite denied noFamily")
            throw InviteLinkError.noCart
        }
        let shareOrchestrator = dependencies.shareOrchestrator
        return try await dependencies.invitePreparer.createInviteLink(
            family: family,
            isOnline: context.isOnline,
            fetch: {
                try await shareOrchestrator.createInviteLink(for: family)
            }
        )
    }

    func revokeInviteLink() async {
        guard let context, context.account != nil,
            let family = context.activeFamilySpace,
            context.access?.isOwner == true
        else {
            CartSyncLog.action.error("revokeInvite denied missingOwnerOrFamily")
            return
        }
        guard context.isOnline else {
            CartSyncLog.action.error("revokeInvite denied offline")
            context.presentAlert(String(localized: "alert.revoke_invite_need_network"), kind: .error, playHaptic: true)
            return
        }
        CartSyncLog.action.info("revokeInvite session begin")
        context.beginBusyOperation()
        defer { context.endBusyOperation() }
        do {
            try await dependencies.shareOrchestrator.revokeInviteLink(for: family)
            dependencies.invitePreparer.clear()
            await context.refreshFamilyMetadata(showErrors: false)
            CartSyncLog.action.info("revokeInvite session done")
            context.presentAlert(String(localized: "account.revoke_invite_done"), kind: .success, playHaptic: true)
        } catch {
            CartSyncLog.action.error(
                "revokeInvite session fail error=\(error.localizedDescription, privacy: .public)"
            )
            context.show(error)
        }
    }

    func renameActiveCart(_ rawName: String) async {
        guard let context, let family = context.activeFamilySpace,
            let familyID = family.id,
            context.access?.isOwner == true
        else { return }
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        context.beginBusyOperation()
        defer { context.endBusyOperation() }
        do {
            try await dependencies.families.renameFamilySpace(id: familyID, name: trimmed)
            try context.reload(preferredFamilySpaceID: familyID)
            dependencies.invitePreparer.clear()
            context.scheduleInviteLinkPreparation(delayNanoseconds: 1_500_000_000)
            CartHaptics.success()
        } catch {
            context.show(error)
        }
    }

    func removeMember(_ member: FamilyMember) async {
        guard let context, let family = context.activeFamilySpace,
            context.access?.isOwner == true,
            !member.isCurrentUser
        else { return }
        guard context.isOnline else {
            context.presentAlert(String(localized: "alert.members_need_network"), kind: .error, playHaptic: true)
            return
        }

        CartSyncLog.action.info("removeMember start id=\(member.id.uuidString, privacy: .public)")
        context.beginBusyOperation()
        defer { context.endBusyOperation() }
        do {
            try await dependencies.cloudSharing.removeMember(member, fromFamily: family.objectID)
            await context.refreshFamilyMetadata(showErrors: false)
            CartHaptics.success()
            CartSyncLog.action.info("removeMember done")
        } catch {
            CartSyncLog.action.error(
                "removeMember fail error=\(error.localizedDescription, privacy: .public)"
            )
            context.show(error)
        }
    }
}

// MARK: - Leave

extension MembershipService {
    func leaveCurrentFamily() async {
        guard let context, let account = context.account,
            let family = context.activeFamilySpace,
            context.access?.isParticipant == true
        else { return }
        let familyID = family.id

        CartSyncLog.action.info(
            "leaveFamily start family=\(familyID?.uuidString ?? "-", privacy: .public)"
        )
        context.beginBusyOperation()
        isLeavingSharedCart = true
        defer {
            isLeavingSharedCart = false
            context.endBusyOperation()
        }
        // Buffered, so a late purge that reports in before the recovery starts listening is kept.
        let (latePurgeCompletions, latePurgeSink) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        do {
            try await leave(family, id: familyID, of: account, latePurgeSink: latePurgeSink)
            CartHaptics.success()
            CartSyncLog.action.info("leaveFamily done")
        } catch {
            CartSyncLog.action.error(
                "leaveFamily fail error=\(error.localizedDescription, privacy: .public)"
            )
            context.show(error)
            handleLeaveFailure(error, family: family, latePurgeCompletions: latePurgeCompletions)
        }
    }

    /// `familyID` is read before the leave: a reload during it can reset the entity.
    private func leave(
        _ family: FamilySpace,
        id familyID: UUID?,
        of account: OneCartAccount,
        latePurgeSink: AsyncStream<Void>.Continuation
    ) async throws {
        let discardLeftovers = try await dependencies.cloudSharing.leaveFamily(objectID: family.objectID) {
            latePurgeSink.yield()
            latePurgeSink.finish()
        }
        if discardLeftovers, let familyID {
            do {
                try await dependencies.families.discardLocalSharedFamilySpace(id: familyID)
            } catch let error as RepositoryError where error == .familySpaceNotFound {
                CartSyncLog.action.info("leaveFamily local shared already gone")
            }
        }
        try await dependencies.household.reactivatePersonalCartIfNeeded(for: account)
        dependencies.household.forgetSharedCart()
        await context?.refreshFamilyMetadata(showErrors: false)
    }

    private func handleLeaveFailure(
        _ error: Error,
        family: FamilySpace,
        latePurgeCompletions: AsyncStream<Void>
    ) {
        let timedOut: Bool =
            if case OneCartCloudKitError.leaveTimedOut = error { true } else { false }
        dependencies.household.leaveFailed(cartStillShared: timedOut || isShared(family))
        guard timedOut else { return }
        trackLeaveRecovery(
            Task {
                await recoverAfterLeaveTimeout(latePurgeCompletions: latePurgeCompletions)
            })
    }

    private enum LeaveRecoveryEnd: Sendable {
        case recovered, passesSpent, latePurgeSpent
    }

    /// Retries the fallback to the personal cart until the shared cart is gone or the passes run
    /// out; each element of `latePurgeCompletions` (a purge that finished after the leave timed
    /// out) triggers one extra pass at once. A late purge that does not clear the cart leaves
    /// the timed passes running.
    func recoverAfterLeaveTimeout(latePurgeCompletions: AsyncStream<Void>) async {
        let clock = dependencies.clock
        await withTaskGroup(of: LeaveRecoveryEnd.self) { group in
            group.addTask {
                for _ in 0..<Self.leaveRecoveryPasses {
                    do {
                        try await clock.sleep(Self.leaveRecoveryInterval)
                    } catch {
                        return .passesSpent
                    }
                    if await self.attemptLeaveRecoveryPass() {
                        return .recovered
                    }
                }
                return .passesSpent
            }
            group.addTask {
                for await _ in latePurgeCompletions where await self.attemptLeaveRecoveryPass() {
                    return .recovered
                }
                return .latePurgeSpent
            }
            for await end in group where end != .latePurgeSpent {
                break
            }
            group.cancelAll()
        }
    }

    private func attemptLeaveRecoveryPass() async -> Bool {
        // Without the session there is nothing to check; never report a recovery that did not run.
        guard let context else { return false }
        do {
            try context.reload(preferredFamilySpaceID: nil)
            if case let .failed(error) = await dependencies.household.handleInviteeSharedCartGoneIfNeeded() {
                context.show(error)
            }
        } catch {
            CartSyncLog.action.error(
                "leaveFamily recovery reload fail error=\(error.localizedDescription, privacy: .public)"
            )
        }
        let hasShared = context.familySpaces.contains(where: isShared)
        if !hasShared {
            CartSyncLog.action.info("leaveFamily recovery shared gone")
        }
        leaveRecoveryPassCount += 1
        return !hasShared
    }
}
