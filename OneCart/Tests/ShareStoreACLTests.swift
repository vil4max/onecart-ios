import CloudKit
@testable import OneCart
import Testing

/// `CloudKitShareStoring.applyReadWriteACL(to:reopenInviteDoor:in:)`, the step the owner ACL heal
/// and the invite door share: what it changes on the share and when it saves it.
@Suite("Share ACL save")
struct ShareStoreACLTests {
    /// A share that already carries the branding, so only the ACL decides whether it changes.
    private func brandedShare(publicPermission: CKShare.ParticipantPermission) -> CKShare {
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        share.publicPermission = publicPermission
        OneCartShareBranding.apply(to: share, thumbnail: FixedShareThumbnail())
        return share
    }

    @Test("REQ-SHARE-060: the owner heal on a revoked share neither saves it nor reopens the invite door")
    func healOnRevokedShareKeepsTheDoorClosed() async throws {
        let store = FakeCloudKitShareStore()
        let share = brandedShare(publicPermission: .none)

        let saved = try await store.applyReadWriteACL(to: share, reopenInviteDoor: false, in: .private)

        #expect(saved == nil)
        #expect(share.publicPermission == .none)
        #expect(store.persistedScopes.isEmpty)
    }

    @Test("REQ-SHARE-070: an invite reopens a revoked door and saves the share once")
    func inviteReopensTheDoorAndSaves() async throws {
        let store = FakeCloudKitShareStore()
        let share = brandedShare(publicPermission: .none)

        let saved = try await store.applyReadWriteACL(to: share, reopenInviteDoor: true, in: .private)

        #expect(saved?.publicPermission == .readWrite)
        #expect(share.publicPermission == .readWrite)
        #expect(store.persistedScopes == [.private])
    }

    @Test("REQ-SHARE-070: an open, branded share is returned as nil and not saved")
    func unchangedShareIsNotSaved() async throws {
        let store = FakeCloudKitShareStore()
        let share = brandedShare(publicPermission: .readWrite)

        let saved = try await store.applyReadWriteACL(to: share, reopenInviteDoor: true, in: .private)

        #expect(saved == nil)
        #expect(store.persistedScopes.isEmpty)
    }

    @Test("REQ-SHARE-070: a share without the branding is branded and saved even when the ACL holds")
    func missingBrandingIsSaved() async throws {
        let store = FakeCloudKitShareStore()
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        share.publicPermission = .readWrite

        let saved = try await store.applyReadWriteACL(to: share, reopenInviteDoor: false, in: .shared)

        #expect(saved?[CKShare.SystemFieldKey.title] as? String == OneCartShareBranding.title)
        #expect(saved?[CKShare.SystemFieldKey.thumbnailImageData] as? Data == FixedShareThumbnail.data)
        #expect(store.persistedScopes == [.shared])
    }

    @Test("REQ-SHARE-070: the branding never redraws a thumbnail, and stamps none without a renderer")
    func brandingKeepsAnExistingThumbnailAndNeedsARenderer() {
        let unbranded = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        #expect(OneCartShareBranding.apply(to: unbranded, thumbnail: nil))
        #expect(unbranded[CKShare.SystemFieldKey.thumbnailImageData] == nil)

        let existing = Data([1, 2, 3])
        let stamped = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        stamped[CKShare.SystemFieldKey.title] = OneCartShareBranding.title as CKRecordValue
        stamped[CKShare.SystemFieldKey.thumbnailImageData] = existing as CKRecordValue
        #expect(!OneCartShareBranding.apply(to: stamped, thumbnail: FixedShareThumbnail()))
        #expect(stamped[CKShare.SystemFieldKey.thumbnailImageData] as? Data == existing)
    }
}
