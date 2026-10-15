#if DEBUG
    import CoreData
    import Foundation
    import Synchronization

    /// iCloud without iCloud, for unit tests and the DEBUG welcome demo: no `CKContainer` is ever
    /// created. It answers the way the app did on an ephemeral store before this seam existed:
    /// one fixed account, scope-based access, a cart without a `CKShare`, a preview invite link,
    /// and leave, revoke and account-data deletion that succeed without a server.
    final class InMemoryFamilySharing: FamilyCloudSharing {
        static let previewInviteURL = URL(string: "https://www.icloud.com/share/onecart-preview")

        private let persistence: PersistenceController
        /// Mirrors the live cache so sign-out and account-deletion tests can watch it being forgotten.
        let userRecordNameCache = Mutex(UserRecordNameCache())

        init(persistence: PersistenceController) {
            self.persistence = persistence
        }

        // MARK: CloudUserIdentifying

        var identityGeneration: UInt64 {
            userRecordNameCache.withLock { $0.generation }
        }

        /// No iCloud user to ask, as when iCloud cannot tell.
        func currentUserRecordName() async -> String? {
            nil
        }

        func resetCachedUserRecordName() {
            userRecordNameCache.withLock { $0.reset() }
        }

        // MARK: AccountCloudDataDeleting

        func deletePrivateAccountCloudData() async throws {}

        // MARK: FamilyCloudSharing

        func restoredAccount(appleUserID _: String, displayName: String?) async throws -> OneCartAccount {
            OneCartAccount(
                id: OneCartStableID.uuid(for: "onecart.in-memory-user"),
                displayName: displayName?.nilIfBlank ?? String(localized: "common.default_user")
            )
        }

        func access(for family: FamilySpace) -> FamilyAccess {
            persistence.scope(for: family) == .shared ? .member : .owner
        }

        func familyMembers(
            for family: FamilySpace,
            account: OneCartAccount,
            currentUserRecordName _: String?
        ) throws -> [FamilyMember] {
            let currentUser = FamilyMember(
                id: account.id,
                displayName: account.displayName,
                access: access(for: family),
                joinedAt: family.createdDate,
                isCurrentUser: true,
                avatarURL: nil,
                bannerURL: nil
            )
            return [currentUser]
        }

        func createFamilyInviteLink(objectID _: NSManagedObjectID, displayName: String) async throws
            -> FamilyInviteLink
        {
            guard let url = Self.previewInviteURL else {
                throw OneCartCloudKitError.shareURLUnavailable
            }
            return FamilyInviteLink(id: UUID(), familyName: displayName, url: url)
        }

        func revokeInviteLink(objectID _: NSManagedObjectID) async throws {}

        func ensureReadWriteACL(objectID _: NSManagedObjectID) async throws -> Bool {
            false
        }

        func removeMember(_: FamilyMember, fromFamily _: NSManagedObjectID) async throws {
            throw OneCartCloudKitError.familyNotShared
        }

        func leaveFamily(objectID _: NSManagedObjectID) async throws -> Bool {
            true
        }
    }
#endif
