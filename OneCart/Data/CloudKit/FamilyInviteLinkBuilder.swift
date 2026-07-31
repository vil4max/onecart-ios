import CloudKit
import CoreData
import Foundation
import OSLog

/// CloudKit share creation must stay off the MainActor. Keeping this as a plain enum
/// avoids inheriting actor isolation from `CloudKitBackendService`.
enum ShareCreateRace: @unchecked Sendable {
    case share(CKShare)
}

enum FamilyInviteLinkBuilder {
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
            timeoutSeconds: 8
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
            if Task.isCancelled { return }
            if persistence.container.recordID(for: objectID) != nil {
                return
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
    }

    private static func createShareWithRetry(
        persistence: PersistenceController,
        objectID: NSManagedObjectID,
        attempts: Int = 3
    ) async throws -> CKShare {
        var lastError: Error = OneCartCloudKitError.stillSyncing
        for attempt in 0 ..< attempts {
            try Task.checkCancellation()
            if attempt > 0 {
                try? await nudgeCloudKitExport(persistence: persistence, objectID: objectID)
                let delayNanoseconds = if let seconds = (lastError as? CKError)?.retryAfterSeconds, seconds > 0 {
                    UInt64(seconds * 1_000_000_000)
                } else {
                    UInt64(800_000_000 * attempt)
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

    private static func isRetryableShareFailure(_ error: Error) -> Bool {
        if error is OneCartCloudKitError { return false }
        if let ckError = error as? CKError {
            switch ckError.code {
            case .zoneBusy, .serviceUnavailable, .requestRateLimited, .serverResponseLost,
                 .networkUnavailable, .networkFailure, .notAuthenticated,
                 .accountTemporarilyUnavailable, .partialFailure:
                return true
            default:
                break
            }
        }
        let text = (error as NSError).localizedDescription.lowercased()
        return text.contains("try again")
            || text.contains("not available")
            || text.contains("sync")
            || text.contains("busy")
    }

    private static func mapShareFailure(_ error: Error) -> Error {
        if error is OneCartCloudKitError { return error }
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
        try await withThrowingTaskGroup(of: ShareCreateRace.self) { group in
            group.addTask {
                let share = try await createShareUnscoped(
                    persistence: persistence,
                    objectID: objectID
                )
                return .share(share)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 12_000_000_000)
                throw OneCartCloudKitError.stillSyncing
            }
            do {
                guard case let .share(share) = try await group.next() else {
                    group.cancelAll()
                    throw OneCartCloudKitError.stillSyncing
                }
                group.cancelAll()
                return share
            } catch {
                group.cancelAll()
                throw error
            }
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

    /// Revoke only closes the link door (`publicPermission = .none`). It is not a
    /// guest ban. Share must reopen and persist `.readWrite` before handing out URL.
    private static func ensureInviteDoorOpen(
        _ share: CKShare,
        persistence: PersistenceController
    ) async throws {
        guard CloudKitShareEnvironment.canMutateInProcess(share) else {
            CartSyncLog.shareACL.error(
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
                "invite door persist reopen=\(doorWasClosed, privacy: .public) aclChanged=\(aclChanged, privacy: .public)"
            )
            let saved = try await persistShareRequired(share, persistence: persistence)
            guard saved.publicPermission == .readWrite else {
                CartSyncLog.shareACL.error(
                    "invite door persist returned closed permission=\(String(describing: saved.publicPermission), privacy: .public)"
                )
                throw OneCartCloudKitError.inviteDoorClosed
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
        timeoutNanoseconds: UInt64 = 22_000_000_000
    ) async throws -> CKShare {
        guard CloudKitShareEnvironment.canMutateInProcess(share) else {
            throw OneCartCloudKitError.shareEnvironmentMismatch
        }
        return try await withThrowingTaskGroup(of: CKShare.self) { group in
            group.addTask {
                try await persistShare(share, persistence: persistence)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw OneCartCloudKitError.shareTimedOut
            }
            do {
                let saved = try await group.next()!
                group.cancelAll()
                return saved
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private static func persistShare(
        _ share: CKShare,
        persistence: PersistenceController
    ) async throws -> CKShare {
        guard CloudKitShareEnvironment.canMutateInProcess(share) else {
            CartSyncLog.shareACL.error(
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
