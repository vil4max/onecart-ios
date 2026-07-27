import CloudKit
import CoreData
import CryptoKit
import Foundation
import UIKit

struct OneCartAccount: Equatable {
    let id: UUID
    let displayName: String
    let avatarURL: String?
    let bannerURL: String?

    init(
        id: UUID,
        displayName: String,
        avatarURL: String? = nil,
        bannerURL: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.bannerURL = bannerURL
    }
}

enum FamilyAccess: String, Equatable {
    case owner
    case member

    var title: String {
        switch self {
        case .owner: String(localized: "cart.owner_role")
        case .member: String(localized: "cart.member_role")
        }
    }

    var canEdit: Bool {
        true
    }

    var isOwner: Bool {
        self == .owner
    }

    var isParticipant: Bool {
        self == .member
    }
}

enum OneCartSyncState: Equatable {
    case synchronized
    case syncing
    case offline
    case failed

    var title: String {
        switch self {
        case .synchronized: String(localized: "sync.synchronized")
        case .syncing: String(localized: "sync.syncing")
        case .offline: String(localized: "sync.offline")
        case .failed: String(localized: "sync.failed")
        }
    }

    var systemImage: String {
        switch self {
        case .synchronized: "checkmark.circle.fill"
        case .syncing: "arrow.triangle.2.circlepath"
        case .offline: "wifi.slash"
        case .failed: "exclamationmark.circle.fill"
        }
    }
}

struct FamilyMember: Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let access: FamilyAccess
    let joinedAt: Date
    let isCurrentUser: Bool
    let avatarURL: String?
    let bannerURL: String?
}

struct FamilyInviteLink: Identifiable, Equatable {
    let id: UUID
    let familyName: String
    let url: URL

    var expiresAt: Date {
        .distantFuture
    }

    var shareMessage: String {
        String(format: String(localized: "share.message"), familyName, url.absoluteString)
    }

    var shareTitle: String {
        OneCartShareBranding.title
    }
}

enum OneCartShareBranding {
    static let title = "OneCart"

    /// Applies CloudKit share card branding. Returns `true` when the share was mutated.
    @discardableResult
    static func apply(to share: CKShare) -> Bool {
        var changed = false
        if (share[CKShare.SystemFieldKey.title] as? String) != title {
            share[CKShare.SystemFieldKey.title] = title as CKRecordValue
            changed = true
        }
        if share[CKShare.SystemFieldKey.thumbnailImageData] == nil {
            share[CKShare.SystemFieldKey.thumbnailImageData] = thumbnailImageData as CKRecordValue
            changed = true
        }
        return changed
    }

    static let thumbnailImage: UIImage = {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(red: 52 / 255, green: 120 / 255, blue: 91 / 255, alpha: 1).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 112).fill()

            let config = UIImage.SymbolConfiguration(pointSize: 220, weight: .semibold)
            guard let symbol = UIImage(systemName: "cart.fill", withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            else { return }
            let origin = CGPoint(
                x: (size.width - symbol.size.width) / 2,
                y: (size.height - symbol.size.height) / 2
            )
            symbol.draw(at: origin)
        }
    }()

    static let thumbnailImageData: Data = thumbnailImage.pngData() ?? Data()
}

enum OneCartShareLinkJoin {
    @discardableResult
    static func applyReadWriteACL(to share: CKShare) -> Bool {
        guard share.publicPermission != .readWrite else { return false }
        share.publicPermission = .readWrite
        return true
    }
}

enum OneCartCloudKitError: LocalizedError {
    case accountUnavailable(CKAccountStatus)
    case familyNotShared
    case shareURLUnavailable
    case participantNotFound
    case stillSyncing
    case shareTimedOut

    var errorDescription: String? {
        switch self {
        case let .accountUnavailable(status):
            switch status {
            case .noAccount:
                String(localized: "sync.icloud_no_account")
            case .restricted:
                String(localized: "sync.icloud_restricted")
            case .temporarilyUnavailable:
                String(localized: "sync.icloud_temp_unavailable")
            default:
                String(localized: "sync.icloud_check_failed")
            }
        case .familyNotShared:
            String(localized: "sync.family_not_shared")
        case .shareURLUnavailable:
            String(localized: "sync.share_url_unavailable")
        case .participantNotFound:
            String(localized: "sync.participant_not_found")
        case .stillSyncing:
            String(localized: "sync.still_syncing")
        case .shareTimedOut:
            String(localized: "sync.share_timed_out")
        }
    }
}

enum CloudKitUserFacingError {
    static var genericSyncFailure: String {
        String(localized: "sync.generic_failure")
    }

    /// TestFlight / App Store use CloudKit Production — new Core Data types must be
    /// deployed from Development in CloudKit Console before they can sync.
    /// This cannot be fixed in the binary alone; the container owner must Deploy Schema.
    static var productionSchemaMissing: String {
        String(localized: "sync.production_schema_missing")
    }

    static func isProductionSchemaFailure(_ error: Error) -> Bool {
        for candidate in flattened(error) {
            if productionSchemaMessage(in: candidate) != nil {
                return true
            }
        }
        return productionSchemaMessage(in: error) != nil
    }

    static func message(for error: Error) -> String {
        // Prefer known CloudKit/Core Data reasons over opaque NSError dumps
        // (mirroring delegate aborts often surface as LocalizedError with English CK text).
        for candidate in flattened(error) {
            if let schema = productionSchemaMessage(in: candidate) {
                return schema
            }
            if let message = message(forCKError: candidate) {
                return message
            }
            if let message = message(forCocoaError: candidate) {
                return message
            }
        }

        if let schema = productionSchemaMessage(in: error) {
            return schema
        }

        if let localized = error as? LocalizedError,
           let description = localized.errorDescription?.nilIfBlank,
           !(error is CKError),
           !looksLikeOpaqueCloudKitCode(description)
        {
            return description
        }

        let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || looksLikeOpaqueCloudKitCode(raw) {
            return genericSyncFailure
        }
        if raw.lowercased().contains("not authenticated") || raw.lowercased().contains("not signed in") {
            return String(localized: "sync.sign_in_apple_account")
        }
        return raw
    }

    private static func productionSchemaMessage(in error: Error) -> String? {
        let text = diagnosticText(for: error)
        if text.contains("production schema")
            || text.contains("cannot create new type cd_")
            || (text.contains("cannot create new type") && text.contains("schema"))
            || (text.contains("cd_shoppinglist") && text.contains("schema"))
        {
            return productionSchemaMissing
        }
        return nil
    }

    /// Collects localized + userInfo string crumbs — CK nesting often hides the real reason.
    private static func diagnosticText(for error: Error) -> String {
        let nsError = error as NSError
        var parts: [String] = [
            nsError.localizedDescription,
            nsError.localizedFailureReason ?? "",
            nsError.localizedRecoverySuggestion ?? "",
        ]
        for value in nsError.userInfo.values {
            if let string = value as? String {
                parts.append(string)
            } else if let nested = value as? Error {
                parts.append(nested.localizedDescription)
            }
        }
        return parts.joined(separator: "\n").lowercased()
    }

    static func isNetworkError(_ error: Error) -> Bool {
        for candidate in flattened(error) {
            let nsError = candidate as NSError
            if nsError.domain == NSURLErrorDomain {
                return true
            }
            if let ckError = candidate as? CKError {
                switch ckError.code {
                case .networkUnavailable, .networkFailure, .serviceUnavailable, .zoneBusy,
                     .requestRateLimited, .serverResponseLost:
                    return true
                default:
                    break
                }
            }
            let text = candidate.localizedDescription.lowercased()
            if text.contains("network connection")
                || text.contains("internet connection")
                || text.contains("timed out")
                || text.contains("could not connect")
                || text.contains("offline")
            {
                return true
            }
        }
        return false
    }

    private static func message(forCKError error: Error) -> String? {
        guard let ckError = error as? CKError else { return nil }
        switch ckError.code {
        case .notAuthenticated:
            return String(localized: "sync.sign_in_apple_account")
        case .networkUnavailable, .networkFailure:
            return String(localized: "sync.network_deferred")
        case .quotaExceeded:
            return String(localized: "sync.quota_exceeded")
        case .accountTemporarilyUnavailable:
            return String(localized: "sync.temporarily_unavailable")
        case .permissionFailure:
            return String(localized: "sync.share_access_denied")
        case .serverRejectedRequest, .invalidArguments, .incompatibleVersion:
            // Schema / argument detail may still be in userInfo — checked earlier via
            // productionSchemaMessage. Fall back only when no specific mapping matched.
            return genericSyncFailure
        case .zoneNotFound, .userDeletedZone:
            return String(localized: "sync.zone_unavailable")
        case .limitExceeded, .requestRateLimited, .zoneBusy, .serviceUnavailable:
            return String(localized: "sync.icloud_overloaded")
        case .partialFailure:
            // Nested item errors carry the real reason; outer code 2 is opaque.
            return nil
        default:
            return nil
        }
    }

    private static func message(forCocoaError error: Error) -> String? {
        let nsError = error as NSError
        guard nsError.domain == NSCocoaErrorDomain else { return nil }
        // 133021 = NSManagedObjectConstraintMergeError (unique constraint vs CloudKit import).
        if nsError.code == NSManagedObjectConstraintMergeError {
            return genericSyncFailure
        }
        if nsError.code == NSCloudSharingQuotaExceededError {
            return String(localized: "sync.quota_exceeded")
        }
        return nil
    }

    private static func flattened(_ error: Error) -> [Error] {
        var result: [Error] = []
        var queue: [Error] = [error]
        var depth = 0

        while let current = queue.first, depth < 24 {
            queue.removeFirst()
            depth += 1
            result.append(current)

            let nsError = current as NSError
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                queue.append(underlying)
            }
            if let detailed = nsError.userInfo[NSDetailedErrorsKey] as? [Error] {
                queue.append(contentsOf: detailed)
            }
            if let partial = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                queue.append(contentsOf: partial.values)
            } else if let ckError = current as? CKError, let partial = ckError.partialErrorsByItemID {
                queue.append(contentsOf: partial.values)
            }
        }
        return result
    }

    private static func looksLikeOpaqueCloudKitCode(_ raw: String) -> Bool {
        let normalized = raw.lowercased()
        return normalized.contains("ckerrordomain")
            || normalized.contains("ckerror")
            || normalized.contains("mirroring delegate")
            || normalized.contains("partial failure")
            || normalized.contains("failed to modify some records")
            || (normalized.contains("couldn't be completed") && normalized.contains("error"))
            || (normalized.contains("could not be completed") && normalized.contains("error"))
    }
}

final class CloudKitPermissionAuthorizer: PermissionAuthorizing {
    private let persistence: PersistenceController

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    func canUpdate(_ objectID: NSManagedObjectID) -> Bool {
        guard !persistence.inMemory else { return true }
        guard persistence.scope(for: objectID) == .shared else { return true }
        return persistence.container.canUpdateRecord(forManagedObjectWith: objectID)
    }

    func canDelete(_ objectID: NSManagedObjectID) -> Bool {
        guard !persistence.inMemory else { return true }
        guard persistence.scope(for: objectID) == .shared else { return true }
        return persistence.container.canDeleteRecord(forManagedObjectWith: objectID)
    }
}

final class CloudKitBackendService {
    private let persistence: PersistenceController
    private let cloudContainer: CKContainer

    init(
        persistence: PersistenceController,
        cloudContainer: CKContainer? = nil
    ) {
        self.persistence = persistence
        self.cloudContainer = cloudContainer ?? CKContainer(
            identifier: PersistenceController.cloudKitContainerIdentifier
        )
    }

    func restoredAccount(
        appleUserID: String,
        displayName: String?
    ) async throws -> OneCartAccount {
        if persistence.inMemory {
            return OneCartAccount(
                id: OneCartStableID.uuid(for: "onecart.in-memory-user"),
                displayName: displayName?.nilIfBlank ?? String(localized: "common.default_user")
            )
        }

        let status = try await accountStatus()
        guard status == .available else {
            throw OneCartCloudKitError.accountUnavailable(status)
        }
        return OneCartAccount(
            id: OneCartStableID.uuid(for: "apple:\(appleUserID)"),
            displayName: displayName?.nilIfBlank ?? String(localized: "common.default_user")
        )
    }

    func access(for family: FamilySpace) -> FamilyAccess {
        persistence.scope(for: family) == .shared ? .member : .owner
    }

    func createFamilyInviteLink(for family: FamilySpace) async throws -> FamilyInviteLink {
        try await createFamilyInviteLink(
            objectID: family.objectID,
            displayName: family.displayName
        )
    }

    /// Prefer calling this after flushing the view context and reading `objectID` / name
    /// on the MainActor so CloudKit work does not hold the UI actor.
    func createFamilyInviteLink(
        objectID: NSManagedObjectID,
        displayName: String
    ) async throws -> FamilyInviteLink {
        if persistence.inMemory {
            return FamilyInviteLink(
                id: UUID(),
                familyName: displayName,
                url: URL(string: "https://www.icloud.com/share/onecart-preview")!
            )
        }

        let persistence = persistence
        // Builder is nonisolated; keep a hard ceiling so Invite UI cannot spin forever
        // if `share` / `persistUpdatedShare` never calls back.
        return try await withThrowingTaskGroup(of: FamilyInviteLink.self) { group in
            group.addTask {
                try await FamilyInviteLinkBuilder.makeInviteLink(
                    persistence: persistence,
                    objectID: objectID,
                    displayName: displayName
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 22_000_000_000)
                throw OneCartCloudKitError.shareTimedOut
            }
            do {
                let link = try await group.next()!
                group.cancelAll()
                return link
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    func familyMembers(for family: FamilySpace, account: OneCartAccount) throws -> [FamilyMember] {
        guard let share = try share(for: family) else {
            return [
                FamilyMember(
                    id: account.id,
                    displayName: account.displayName,
                    access: .owner,
                    joinedAt: family.createdDate,
                    isCurrentUser: true,
                    avatarURL: nil,
                    bannerURL: nil
                ),
            ]
        }

        let currentRecordName = share.currentUserParticipant?
            .userIdentity.userRecordID?.recordName
        return share.participants.compactMap { participant -> FamilyMember? in
            let recordName = participant.userIdentity.userRecordID?.recordName
                ?? participant.userIdentity.lookupInfo?.emailAddress
                ?? participant.userIdentity.lookupInfo?.phoneNumber
            guard let recordName, !recordName.isEmpty else { return nil }
            let name = participant.userIdentity.nameComponents.map {
                PersonNameComponentsFormatter.localizedString(
                    from: $0,
                    style: .default,
                    options: []
                )
            }?.nilIfBlank
            let isCurrent = recordName == currentRecordName
            return FamilyMember(
                id: FamilyInviteLinkBuilder.stableUUID(for: recordName),
                displayName: name ?? (isCurrent ? account.displayName : String(localized: "common.default_member")),
                access: participant.role == .owner ? .owner : .member,
                joinedAt: family.createdDate,
                isCurrentUser: isCurrent,
                avatarURL: nil,
                bannerURL: nil
            )
        }
        .sorted {
            if $0.access != $1.access { return $0.access == .owner }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func removeMember(_ member: FamilyMember, from family: FamilySpace) async throws {
        let objectID = family.objectID
        guard let share = try share(forObjectID: objectID) else {
            throw OneCartCloudKitError.familyNotShared
        }
        guard let participant = share.participants.first(where: {
            let recordName = $0.userIdentity.userRecordID?.recordName
                ?? $0.userIdentity.lookupInfo?.emailAddress
            return recordName.map(FamilyInviteLinkBuilder.stableUUID(for:)) == member.id
        }) else {
            throw OneCartCloudKitError.participantNotFound
        }
        share.removeParticipant(participant)
        let store = try persistence.store(for: .private)
        _ = try await persist(share, in: store)
    }

    func leaveFamily(_ family: FamilySpace) async throws {
        let objectID = family.objectID
        guard let share = try share(forObjectID: objectID) else {
            throw OneCartCloudKitError.familyNotShared
        }
        let sharedStore = try persistence.store(for: .shared)
        try await withCheckedThrowingContinuation { (
            continuation: CheckedContinuation<Void, Error>
        ) in
            persistence.container.purgeObjectsAndRecordsInZone(
                with: share.recordID.zoneID,
                in: sharedStore
            ) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func share(for family: FamilySpace) throws -> CKShare? {
        try share(forObjectID: family.objectID)
    }

    private func share(forObjectID objectID: NSManagedObjectID) throws -> CKShare? {
        try persistence.container.fetchShares(matching: [objectID])[objectID]
    }

    private func persist(_ share: CKShare, in store: NSPersistentStore) async throws -> CKShare {
        try await withCheckedThrowingContinuation { continuation in
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

    private func accountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            cloudContainer.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }
}

/// CloudKit share creation must stay off the MainActor. Keeping this as a plain enum
/// avoids inheriting actor isolation from `CloudKitBackendService`.
private enum ShareCreateRace: @unchecked Sendable {
    case share(CKShare)
}

private enum FamilyInviteLinkBuilder {
    static func makeInviteLink(
        persistence: PersistenceController,
        objectID: NSManagedObjectID,
        displayName: String
    ) async throws -> FamilyInviteLink {
        try Task.checkCancellation()

        // Fast path: reuse an existing share URL without blocking on persistUpdatedShare.
        if let existing = try await fetchShare(persistence: persistence, objectID: objectID),
           let url = existing.url
        {
            refreshLinkJoinShareInBackground(existing, persistence: persistence)
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
            refreshLinkJoinShareInBackground(existing, persistence: persistence)
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
                try await Task.sleep(nanoseconds: UInt64(800_000_000 * attempt))
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
        OneCartShareLinkJoin.applyReadWriteACL(to: share)
        OneCartShareBranding.apply(to: share)

        // `persistUpdatedShare` is known to stall; if CloudKit already minted a URL,
        // return it immediately and persist branding/permissions in the background.
        if let url = share.url {
            let shareToPersist = share
            let persistence = persistence
            Task.detached(priority: .utility) {
                _ = try? await persistShare(shareToPersist, persistence: persistence)
            }
            return FamilyInviteLink(
                id: stableUUID(for: share.recordID.recordName),
                familyName: displayName,
                url: url
            )
        }

        let saved = try await persistShare(share, persistence: persistence)
        guard let url = saved.url ?? share.url else {
            throw OneCartCloudKitError.shareURLUnavailable
        }

        return FamilyInviteLink(
            id: stableUUID(for: saved.recordID.recordName),
            familyName: displayName,
            url: url
        )
    }

    private static func refreshLinkJoinShareInBackground(
        _ share: CKShare,
        persistence: PersistenceController
    ) {
        var needsPersist = false
        if OneCartShareLinkJoin.applyReadWriteACL(to: share) {
            needsPersist = true
        }
        if OneCartShareBranding.apply(to: share) {
            needsPersist = true
        }
        guard needsPersist else { return }
        Task.detached(priority: .utility) {
            _ = try? await persistShare(share, persistence: persistence)
        }
    }

    private static func persistShare(
        _ share: CKShare,
        persistence: PersistenceController
    ) async throws -> CKShare {
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
