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
        case .owner: "Владелец группы"
        case .member: "Участник группы"
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
        case .synchronized: "Все изменения сохранены"
        case .syncing: "Синхронизация…"
        case .offline: "Офлайн — изменения сохранены"
        case .failed: "Синхронизация приостановлена"
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
        "OneCart\nПрисоединяйтесь к группе «\(familyName)»\n\n\(url.absoluteString)"
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
                "Для синхронизации нужен iCloud на этом iPhone (Настройки → Apple Account → iCloud). Входа через Apple недостаточно."
            case .restricted:
                "iCloud ограничен на этом устройстве — синхронизация и шаринг корзины недоступны."
            case .temporarilyUnavailable:
                "iCloud временно недоступен. Проверьте сеть и повторите — вход через Apple уже сохранён."
            default:
                "Не удалось проверить iCloud на устройстве. Синхронизация требует доступный iCloud-аккаунт."
            }
        case .familyNotShared:
            "Группа ещё не опубликована."
        case .shareURLUnavailable:
            "Не удалось создать ссылку общего доступа. Попробуйте ещё раз."
        case .participantNotFound:
            "Участник больше не найден в общем доступе."
        case .stillSyncing:
            "Группа ещё синхронизируется с iCloud. Подождите несколько секунд и попробуйте снова."
        case .shareTimedOut:
            "Не удалось создать ссылку вовремя. Проверьте сеть и синхронизацию iCloud, затем повторите."
        }
    }
}

/// Maps CloudKit / Core Data sync failures to short Russian copy for alerts.
enum CloudKitUserFacingError {
    static let genericSyncFailure =
        "Не удалось синхронизировать с iCloud. Проверьте сеть и место в iCloud, затем повторите."

    static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription?.nilIfBlank,
           !(error is CKError)
        {
            return description
        }

        for candidate in flattened(error) {
            if let message = message(forCKError: candidate) {
                return message
            }
            if let message = message(forCocoaError: candidate) {
                return message
            }
        }

        let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || looksLikeOpaqueCloudKitCode(raw) {
            return genericSyncFailure
        }
        if raw.lowercased().contains("not authenticated") || raw.lowercased().contains("not signed in") {
            return "Войдите в Apple Account в Настройках iPhone и повторите попытку."
        }
        return raw
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
            return "Войдите в Apple Account в Настройках iPhone и повторите попытку."
        case .networkUnavailable, .networkFailure:
            return "Нет соединения с сервисом синхронизации. Изменения останутся на устройстве и синхронизируются позже."
        case .quotaExceeded:
            return "В iCloud закончилось место. Освободите место в Настройках iPhone и повторите."
        case .accountTemporarilyUnavailable:
            return "Синхронизация временно недоступна. Попробуйте ещё раз позже."
        case .permissionFailure:
            return "Нет доступа к общей группе в iCloud. Попросите владельца пригласить вас снова."
        case .serverRejectedRequest, .invalidArguments, .incompatibleVersion:
            return genericSyncFailure
        case .zoneNotFound, .userDeletedZone:
            return "Облачная зона OneCart недоступна. Перезапустите приложение и проверьте iCloud."
        case .limitExceeded, .requestRateLimited, .zoneBusy, .serviceUnavailable:
            return "iCloud временно перегружен. Подождите немного — синхронизация продолжится сама."
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
            return "В iCloud закончилось место. Освободите место в Настройках iPhone и повторите."
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
                displayName: displayName?.nilIfBlank ?? "Пользователь"
            )
        }

        let status = try await accountStatus()
        guard status == .available else {
            throw OneCartCloudKitError.accountUnavailable(status)
        }
        return OneCartAccount(
            id: OneCartStableID.uuid(for: "apple:\(appleUserID)"),
            displayName: displayName?.nilIfBlank ?? "Пользователь"
        )
    }

    func access(for family: FamilySpace) -> FamilyAccess {
        persistence.scope(for: family) == .shared ? .member : .owner
    }

    func createFamilyInviteLink(for family: FamilySpace) async throws -> FamilyInviteLink {
        let objectID = family.objectID
        let displayName = family.displayName

        if persistence.inMemory {
            return FamilyInviteLink(
                id: UUID(),
                familyName: displayName,
                url: URL(string: "https://www.icloud.com/share/onecart-preview")!
            )
        }

        // Flush local edits on the view context (caller is typically MainActor).
        let viewContext = persistence.container.viewContext
        if viewContext.hasChanges {
            try viewContext.save()
        }

        let persistence = persistence
        // Detached + nonisolated builder: share/persist must not run on MainActor or the UI freezes.
        return try await withThrowingTaskGroup(of: FamilyInviteLink.self) { group in
            group.addTask {
                try await Task.detached(priority: .userInitiated) {
                    try await FamilyInviteLinkBuilder.makeInviteLink(
                        persistence: persistence,
                        objectID: objectID,
                        displayName: displayName
                    )
                }.value
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 35_000_000_000)
                throw OneCartCloudKitError.shareTimedOut
            }
            let link = try await group.next()!
            group.cancelAll()
            return link
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
                displayName: name ?? (isCurrent ? account.displayName : "Участник"),
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
private enum FamilyInviteLinkBuilder {
    static func makeInviteLink(
        persistence: PersistenceController,
        objectID: NSManagedObjectID,
        displayName: String
    ) async throws -> FamilyInviteLink {
        try Task.checkCancellation()

        // Fast path: reuse an existing share URL without persistUpdatedShare (can stall).
        if let existing = try await fetchShare(persistence: persistence, objectID: objectID),
           let url = existing.url
        {
            refreshBrandingInBackground(existing, persistence: persistence)
            return FamilyInviteLink(
                id: stableUUID(for: existing.recordID.recordName),
                familyName: displayName,
                url: url
            )
        }

        try await waitUntilMirrored(persistence: persistence, objectID: objectID)

        if let existing = try await fetchShare(persistence: persistence, objectID: objectID),
           let url = existing.url
        {
            refreshBrandingInBackground(existing, persistence: persistence)
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

        let created = try await createShare(persistence: persistence, objectID: objectID)
        return try await finalizeShare(
            created,
            persistence: persistence,
            displayName: displayName
        )
    }

    /// CloudKit must own a CKRecord for the family root before `share` can succeed.
    private static func waitUntilMirrored(
        persistence: PersistenceController,
        objectID: NSManagedObjectID,
        timeoutSeconds: TimeInterval = 20
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            try Task.checkCancellation()
            if persistence.container.recordID(for: objectID) != nil {
                return
            }
            try await Task.sleep(nanoseconds: 400_000_000)
        }
        throw OneCartCloudKitError.stillSyncing
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
        try await withCheckedThrowingContinuation { continuation in
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
                            continuation.resume(throwing: error)
                        } else if let share {
                            continuation.resume(returning: share)
                        } else {
                            continuation.resume(throwing: OneCartCloudKitError.shareURLUnavailable)
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func finalizeShare(
        _ share: CKShare,
        persistence: PersistenceController,
        displayName: String
    ) async throws -> FamilyInviteLink {
        // RC10: private invites only — no public join-via-URL ACL (Apple Family is UX positioning, not Family Sharing APIs).
        share.publicPermission = .none
        OneCartShareBranding.apply(to: share)
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

    /// Keep invite UI snappy: update OneCart title/logo on an already-published share off the hot path.
    private static func refreshBrandingInBackground(
        _ share: CKShare,
        persistence: PersistenceController
    ) {
        guard OneCartShareBranding.apply(to: share) else { return }
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
