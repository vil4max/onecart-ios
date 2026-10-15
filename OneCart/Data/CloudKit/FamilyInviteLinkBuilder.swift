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
        objectID: NSManagedObjectID,
        displayName: String
    ) async throws -> FamilyInviteLink {
        guard let share = try await fetchShare(persistence: persistence, objectID: objectID) else {
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
        objectID: NSManagedObjectID,
        displayName: String
    ) async throws -> FamilyInviteLink {
        try Task.checkCancellation()

        // Fast path: reuse an existing share URL only after the invite door is
        // confirmed open (Revoke sets publicPermission=.none; Share must reopen it).
        if let existing = try await fetchShare(persistence: persistence, objectID: objectID),
            let url = existing.url
        {
            try await ensureInviteDoorOpen(existing, persistence: persistence)
            return FamilyInviteLink(
                id: stableUUID(for: existing.recordID.recordName),
                familyName: displayName,
                url: url
            )
        }

        // Nudge + brief wait help, but must not block invite forever when recordID
        // stays nil (common right after first household cart creation).
        try await nudgeCloudKitExport(persistence: persistence, objectID: objectID)
        await waitUntilMirroredIfPossible(
            persistence: persistence,
            objectID: objectID,
            timeoutSeconds: FamilyInviteShareBudget.mirrorWaitSeconds
        )

        if let existing = try await fetchShare(persistence: persistence, objectID: objectID),
            let url = existing.url
        {
            try await ensureInviteDoorOpen(existing, persistence: persistence)
            return FamilyInviteLink(
                id: stableUUID(for: existing.recordID.recordName),
                familyName: displayName,
                url: url
            )
        }

        if let existing = try await fetchShare(persistence: persistence, objectID: objectID) {
            return try await finalizeShare(
                existing,
                persistence: persistence,
                displayName: displayName
            )
        }

        // `share()` itself often finishes the first CloudKit export — do not require
        // recordID beforehand (that gate caused a stuck Invite spinner loop).
        let created = try await createShareWithRetry(
            persistence: persistence,
            objectID: objectID
        )
        return try await finalizeShare(
            created,
            persistence: persistence,
            displayName: displayName
        )
    }

    /// Touches the family root so NSPersistentCloudKitContainer schedules an export.
    private static func nudgeCloudKitExport(
        persistence: PersistenceController,
        objectID: NSManagedObjectID
    ) async throws {
        try await persistence.performBackgroundTask(author: "OneCartShareNudge") { context in
            let object = try context.existingObject(with: objectID)
            if object.objectID.isTemporaryID {
                try context.obtainPermanentIDs(for: [object])
            }
            if let space = object as? FamilySpace {
                space.updatedAt = Date()
            }
        }
    }

    /// Best-effort wait for a mirrored CKRecord. Returns even if still syncing so
    /// callers can attempt `share()` instead of looping on stillSyncing alerts.
    private static func waitUntilMirroredIfPossible(
        persistence: PersistenceController,
        objectID: NSManagedObjectID,
        timeoutSeconds: TimeInterval
    ) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled {
                return
            }
            if persistence.container.recordID(for: objectID) != nil {
                return
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
    }

    private static func createShareWithRetry(
        persistence: PersistenceController,
        objectID: NSManagedObjectID,
        attempts: Int = FamilyInviteShareBudget.createAttempts
    ) async throws -> CKShare {
        var lastError: Error = OneCartCloudKitError.stillSyncing
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            if attempt > 0 {
                try? await nudgeCloudKitExport(persistence: persistence, objectID: objectID)
                let delayNanoseconds =
                    if let seconds = (lastError as? CKError)?.retryAfterSeconds, seconds > 0 {
                        UInt64(seconds * 1_000_000_000)
                    } else {
                        FamilyInviteShareBudget.createBackoffStepNanoseconds * UInt64(attempt)
                    }
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            do {
                return try await createShare(persistence: persistence, objectID: objectID)
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

    /// Decides by CloudKit code only; localized descriptions differ per device language.
    static func isRetryableShareFailure(_ error: Error) -> Bool {
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

    private static func fetchShare(
        persistence: PersistenceController,
        objectID: NSManagedObjectID
    ) async throws -> CKShare? {
        try await withCheckedThrowingContinuation { continuation in
            let context = persistence.newBackgroundContext(author: "OneCartShareLookup")
            context.perform {
                do {
                    _ = try context.existingObject(with: objectID)
                    let share = try persistence.container.fetchShares(matching: [objectID])[objectID]
                    continuation.resume(returning: share)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func createShare(
        persistence: PersistenceController,
        objectID: NSManagedObjectID
    ) async throws -> CKShare {
        try await CloudKitDeadline.run(
            timeoutNanoseconds: FamilyInviteShareBudget.createTimeoutNanoseconds,
            timeoutError: OneCartCloudKitError.stillSyncing
        ) {
            try await createShareUnscoped(persistence: persistence, objectID: objectID)
        }
    }

    private static func createShareUnscoped(
        persistence: PersistenceController,
        objectID: NSManagedObjectID
    ) async throws -> CKShare {
        try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var resumed = false
            func resume(_ result: Result<CKShare, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            let context = persistence.newBackgroundContext(author: "OneCartShareCreate")
            context.perform {
                do {
                    let object = try context.existingObject(with: objectID)
                    if object.objectID.isTemporaryID {
                        try context.obtainPermanentIDs(for: [object])
                        try context.save()
                    }
                    persistence.container.share([object], to: nil) { _, share, _, error in
                        if let error {
                            resume(.failure(error))
                        } else if let share {
                            resume(.success(share))
                        } else {
                            resume(.failure(OneCartCloudKitError.shareURLUnavailable))
                        }
                    }
                } catch {
                    resume(.failure(error))
                }
            }
        }
    }

    private static func finalizeShare(
        _ share: CKShare,
        persistence: PersistenceController,
        displayName: String
    ) async throws -> FamilyInviteLink {
        try await ensureInviteDoorOpen(share, persistence: persistence)

        if let url = share.url {
            return FamilyInviteLink(
                id: stableUUID(for: share.recordID.recordName),
                familyName: displayName,
                url: url
            )
        }

        let saved = try await persistShareRequired(share, persistence: persistence)
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

// MARK: - Invite door and share persistence

extension FamilyInviteLinkBuilder {
    /// Revoke only closes the link door (`publicPermission = .none`). It is not a
    /// guest ban. Share must reopen and persist `.readWrite` before handing out URL.
    private static func ensureInviteDoorOpen(
        _ share: CKShare,
        persistence: PersistenceController
    ) async throws {
        guard CloudKitShareEnvironment.canMutateInProcess(share) else {
            CartSyncLog.shareACL.error(
                // swiftlint:disable:next line_length
                "invite door skip incompatible shareEnv=\(CloudKitShareEnvironment.of(share).rawValue, privacy: .public) process=\(CloudKitShareEnvironment.process.rawValue, privacy: .public)"
            )
            throw OneCartCloudKitError.shareEnvironmentMismatch
        }

        let doorWasClosed = share.publicPermission == .none
        let aclChanged = OneCartShareLinkJoin.applyReadWriteACL(
            to: share,
            reopenInviteDoor: true
        )
        let brandingChanged = OneCartShareBranding.apply(to: share)

        if aclChanged || brandingChanged || doorWasClosed {
            CartSyncLog.shareACL.info(
                // swiftlint:disable:next line_length
                "invite door persist reopen=\(doorWasClosed, privacy: .public) aclChanged=\(aclChanged, privacy: .public) brandingChanged=\(brandingChanged, privacy: .public)"
            )
            let saved = try await persistShareRequired(share, persistence: persistence)
            guard saved.publicPermission == .readWrite else {
                CartSyncLog.shareACL.error(
                    // swiftlint:disable:next line_length
                    "invite door persist returned closed permission=\(String(describing: saved.publicPermission), privacy: .public)"
                )
                throw OneCartCloudKitError.inviteDoorClosed
            }
            if doorWasClosed {
                CartSyncLog.shareACL.info("invite door repaired to readWrite")
            }
            return
        }

        guard share.publicPermission == .readWrite else {
            CartSyncLog.shareACL.error(
                "invite door still closed permission=\(String(describing: share.publicPermission), privacy: .public)"
            )
            throw OneCartCloudKitError.inviteDoorClosed
        }
    }

    private static func persistShareRequired(
        _ share: CKShare,
        persistence: PersistenceController,
        timeoutNanoseconds: UInt64 = FamilyInviteShareBudget.persistTimeoutNanoseconds
    ) async throws -> CKShare {
        guard CloudKitShareEnvironment.canMutateInProcess(share) else {
            throw OneCartCloudKitError.shareEnvironmentMismatch
        }
        return try await CloudKitDeadline.run(timeoutNanoseconds: timeoutNanoseconds) {
            try await persistShare(share, persistence: persistence)
        }
    }

    private static func persistShare(
        _ share: CKShare,
        persistence: PersistenceController
    ) async throws -> CKShare {
        guard CloudKitShareEnvironment.canMutateInProcess(share) else {
            CartSyncLog.shareACL.error(
                // swiftlint:disable:next line_length
                "persistShare skip incompatible shareEnv=\(CloudKitShareEnvironment.of(share).rawValue, privacy: .public)"
            )
            throw OneCartCloudKitError.shareEnvironmentMismatch
        }
        let store = try persistence.store(for: .private)
        return try await withCheckedThrowingContinuation { continuation in
            persistence.container.persistUpdatedShare(share, in: store) { savedShare, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let savedShare {
                    continuation.resume(returning: savedShare)
                } else {
                    continuation.resume(throwing: OneCartCloudKitError.shareURLUnavailable)
                }
            }
        }
    }

    static func stableUUID(for value: String) -> UUID {
        OneCartStableID.uuid(for: value)
    }
}
