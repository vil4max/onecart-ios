import CloudKit
import CoreData
import Foundation
import OSLog

/// Time limits of one invite-link request (REQ-SHARE-030).
enum FamilyInviteShareBudget {
    static let mirrorWaitSeconds: TimeInterval = 8
    static let createAttempts = 3
    static let createTimeoutNanoseconds: UInt64 = 12_000_000_000
    /// Backoff before retry N is N times this, unless CloudKit asks for `retryAfterSeconds`.
    static let createBackoffStepNanoseconds: UInt64 = 800_000_000
    static let persistTimeoutNanoseconds: UInt64 = 22_000_000_000
    /// What the user waits at most for a link. It is deliberately below the builder's worst
    /// case for a new share: mirror wait 8 s + 3 create attempts of 12 s + backoff 0.8 s and
    /// 1.6 s + door persist 22 s + URL persist 22 s, about 90 s, more when CloudKit asks for
    /// `retryAfterSeconds`. The deadline ends the wait; the CloudKit operation may still finish.
    static let inviteCeilingNanoseconds: UInt64 = 45_000_000_000
}

enum FamilyInviteLinkBuilder {
    static func existingInviteLink(
        persistence: PersistenceController,
        shareStore: any CloudKitShareStoring,
        objectID: NSManagedObjectID,
        displayName: String
    ) async throws -> FamilyInviteLink {
        guard let share = try await fetchShare(persistence: persistence, shareStore: shareStore, objectID: objectID)
        else {
            throw OneCartCloudKitError.stillSyncing
        }
        return try linkForOpenShare(share, displayName: displayName)
    }

    static func linkForOpenShare(_ share: CKShare, displayName: String) throws -> FamilyInviteLink {
        // Background preparation is read-only; only an explicit Share action can reopen access.
        guard share.publicPermission == .readWrite else {
            throw OneCartCloudKitError.inviteDoorClosed
        }
        guard let url = share.url else { throw OneCartCloudKitError.stillSyncing }
        return FamilyInviteLink(
            id: stableUUID(for: share.recordID.recordName),
            familyName: displayName,
            url: url
        )
    }

    static func makeInviteLink(
        persistence: PersistenceController,
        shareStore: any CloudKitShareStoring,
        objectID: NSManagedObjectID,
        displayName: String,
        clock: AppClock = .live
    ) async throws -> FamilyInviteLink {
        try Task.checkCancellation()

        // Fast path: reuse an existing share URL only after the invite door is
        // confirmed open (Revoke sets publicPermission=.none; Share must reopen it).
        if let existing = try await fetchShare(persistence: persistence, shareStore: shareStore, objectID: objectID),
            let url = existing.url
        {
            try await ensureInviteDoorOpen(existing, shareStore: shareStore)
            return FamilyInviteLink(
                id: stableUUID(for: existing.recordID.recordName),
                familyName: displayName,
                url: url
            )
        }

        // Nudge + brief wait help, but must not block invite forever when recordID
        // stays nil (common right after first household cart creation).
        try await nudgeCloudKitExport(persistence: persistence, objectID: objectID, clock: clock)
        await waitUntilMirroredIfPossible(
            shareStore: shareStore,
            objectID: objectID,
            timeoutSeconds: FamilyInviteShareBudget.mirrorWaitSeconds,
            clock: clock
        )

        if let existing = try await fetchShare(persistence: persistence, shareStore: shareStore, objectID: objectID),
            let url = existing.url
        {
            try await ensureInviteDoorOpen(existing, shareStore: shareStore)
            return FamilyInviteLink(
                id: stableUUID(for: existing.recordID.recordName),
                familyName: displayName,
                url: url
            )
        }

        if let existing = try await fetchShare(persistence: persistence, shareStore: shareStore, objectID: objectID) {
            return try await finalizeShare(
                existing,
                shareStore: shareStore,
                displayName: displayName
            )
        }

        // `share()` itself often finishes the first CloudKit export, so a CloudKit record ID
        // must not be required beforehand: waiting for it left the Invite spinner hanging.
        let created = try await createShareWithRetry(
            persistence: persistence,
            shareStore: shareStore,
            objectID: objectID,
            clock: clock
        )
        return try await finalizeShare(
            created,
            shareStore: shareStore,
            displayName: displayName
        )
    }

    /// Touches the family root so NSPersistentCloudKitContainer schedules an export.
    private static func nudgeCloudKitExport(
        persistence: PersistenceController,
        objectID: NSManagedObjectID,
        clock: AppClock
    ) async throws {
        try await persistence.performBackgroundTask(author: "OneCartShareNudge") { context in
            let object = try context.existingObject(with: objectID)
            if object.objectID.isTemporaryID {
                try context.obtainPermanentIDs(for: [object])
            }
            if let space = object as? FamilySpace {
                space.updatedAt = clock.now()
            }
        }
    }

    /// Best-effort wait for a mirrored CKRecord. Returns even if still syncing so
    /// callers can attempt `share()` instead of looping on stillSyncing alerts.
    private static func waitUntilMirroredIfPossible(
        shareStore: any CloudKitShareStoring,
        objectID: NSManagedObjectID,
        timeoutSeconds: TimeInterval,
        clock: AppClock
    ) async {
        let deadline = clock.now().addingTimeInterval(timeoutSeconds)
        while clock.now() < deadline {
            if Task.isCancelled {
                return
            }
            if shareStore.recordID(for: objectID) != nil {
                return
            }
            try? await clock.sleep(nanoseconds: 350_000_000)
        }
    }

    private static func createShareWithRetry(
        persistence: PersistenceController,
        shareStore: any CloudKitShareStoring,
        objectID: NSManagedObjectID,
        attempts: Int = FamilyInviteShareBudget.createAttempts,
        clock: AppClock
    ) async throws -> CKShare {
        var lastError: Error = OneCartCloudKitError.stillSyncing
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            if attempt > 0 {
                try? await nudgeCloudKitExport(persistence: persistence, objectID: objectID, clock: clock)
                let delayNanoseconds =
                    if let seconds = (lastError as? CKError)?.retryAfterSeconds, seconds > 0 {
                        UInt64(seconds * 1_000_000_000)
                    } else {
                        FamilyInviteShareBudget.createBackoffStepNanoseconds * UInt64(attempt)
                    }
                try await clock.sleep(nanoseconds: delayNanoseconds)
            }
            do {
                return try await createShare(shareStore: shareStore, objectID: objectID)
            } catch {
                lastError = error
                guard isRetryableShareFailure(error), attempt + 1 < attempts else {
                    throw mapShareFailure(error)
                }
            }
        }
        throw mapShareFailure(lastError)
    }

    /// Codes a few seconds of backoff can cure. Sign-in, quota and permission failures are not
    /// here: retrying cannot help, and they keep their own message instead of "still syncing".
    private static let transientShareFailureCodes: Set<CKError.Code> = [
        .zoneBusy, .serviceUnavailable, .requestRateLimited, .serverResponseLost,
        .networkUnavailable, .networkFailure,
    ]

    /// Decides by CloudKit code only; localized descriptions differ per device language. A
    /// per-attempt deadline is retried too: a first export of a new cart is often that slow.
    static func isRetryableShareFailure(_ error: Error) -> Bool {
        if case OneCartCloudKitError.stillSyncing = error { return true }
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .partialFailure {
            let leaves = (ckError.partialErrorsByItemID ?? [:]).values.compactMap { $0 as? CKError }
            return !leaves.isEmpty && leaves.allSatisfy { transientShareFailureCodes.contains($0.code) }
        }
        return transientShareFailureCodes.contains(ckError.code)
    }

    static func mapShareFailure(_ error: Error) -> Error {
        if error is OneCartCloudKitError {
            return error
        }
        if isRetryableShareFailure(error) {
            return OneCartCloudKitError.stillSyncing
        }
        return error
    }

    /// Checks the cart still exists first, so a deleted cart surfaces its Core Data failure
    /// rather than a missing share.
    private static func fetchShare(
        persistence: PersistenceController,
        shareStore: any CloudKitShareStoring,
        objectID: NSManagedObjectID
    ) async throws -> CKShare? {
        try await withCheckedThrowingContinuation { continuation in
            let context = persistence.newBackgroundContext(author: "OneCartShareLookup")
            context.perform {
                do {
                    _ = try context.existingObject(with: objectID)
                    continuation.resume(returning: try shareStore.fetchShare(for: objectID))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func createShare(
        shareStore: any CloudKitShareStoring,
        objectID: NSManagedObjectID
    ) async throws -> CKShare {
        try await CloudKitDeadline.run(
            timeoutNanoseconds: FamilyInviteShareBudget.createTimeoutNanoseconds,
            timeoutError: OneCartCloudKitError.stillSyncing
        ) {
            try await shareStore.share(objectWith: objectID)
        }
    }

    private static func finalizeShare(
        _ share: CKShare,
        shareStore: any CloudKitShareStoring,
        displayName: String
    ) async throws -> FamilyInviteLink {
        try await ensureInviteDoorOpen(share, shareStore: shareStore)

        if let url = share.url {
            return FamilyInviteLink(
                id: stableUUID(for: share.recordID.recordName),
                familyName: displayName,
                url: url
            )
        }

        let saved = try await shareStore.persistShare(share, in: .private)
        guard let url = saved.url ?? share.url else {
            throw OneCartCloudKitError.shareURLUnavailable
        }

        return FamilyInviteLink(
            id: stableUUID(for: saved.recordID.recordName),
            familyName: displayName,
            url: url
        )
    }
}

// MARK: - Invite door

extension FamilyInviteLinkBuilder {
    /// Revoke only closes the link door (`publicPermission = .none`). It is not a
    /// guest ban. Share must reopen and persist `.readWrite` before handing out URL.
    private static func ensureInviteDoorOpen(
        _ share: CKShare,
        shareStore: any CloudKitShareStoring
    ) async throws {
        let doorWasClosed = share.publicPermission == .none
        let saved = try await shareStore.applyReadWriteACL(to: share, reopenInviteDoor: true, in: .private)
        let permission = (saved ?? share).publicPermission
        guard permission == .readWrite else {
            CartSyncLog.shareACL.error(
                // swiftlint:disable:next line_length
                "invite door closed after persist=\(saved != nil, privacy: .public) permission=\(String(describing: permission), privacy: .public)"
            )
            throw OneCartCloudKitError.inviteDoorClosed
        }
        if saved != nil, doorWasClosed {
            CartSyncLog.shareACL.info("invite door repaired to readWrite")
        }
    }

    static func stableUUID(for value: String) -> UUID {
        OneCartStableID.uuid(for: value)
    }
}
