import CloudKit
import Foundation
@testable import OneCart
import Testing

/// The participant decisions behind removing a member and the read-write ACL, driven through
/// `ShareParticipantHandle` because `CKShare.Participant` cannot be built in a test.
@Suite("ShareParticipantRules")
struct ShareParticipantRulesTests {
    private final class FakeParticipant: ShareParticipantHandle {
        let userRecordName: String?
        let lookupEmailAddress: String?
        let isOwner: Bool
        var permission: CKShare.ParticipantPermission

        init(
            recordName: String? = nil,
            email: String? = nil,
            isOwner: Bool = false,
            permission: CKShare.ParticipantPermission = .readOnly
        ) {
            userRecordName = recordName
            lookupEmailAddress = email
            self.isOwner = isOwner
            self.permission = permission
        }
    }

    private static func memberID(for key: String) -> UUID {
        FamilyInviteLinkBuilder.stableUUID(for: key)
    }

    // MARK: - REQ-SHARE-040 remove member

    @Test("REQ-SHARE-040: the member row resolves to the participant with the same record name")
    func removalFindsParticipantByRecordName() {
        let owner = FakeParticipant(recordName: "_owner", isOwner: true)
        let anna = FakeParticipant(recordName: "_anna")
        let igor = FakeParticipant(recordName: "_igor")

        let match = ShareParticipantRules.participant(
            forMemberID: Self.memberID(for: "_igor"),
            in: [owner, anna, igor]
        )

        #expect(match === igor)
    }

    @Test("REQ-SHARE-040: without a record name the lookup email identifies the participant")
    func removalFallsBackToLookupEmail() {
        let invited = FakeParticipant(email: "guest@example.com")
        let named = FakeParticipant(recordName: "_named", email: "named@example.com")

        #expect(
            ShareParticipantRules.participant(
                forMemberID: Self.memberID(for: "guest@example.com"),
                in: [named, invited]
            ) === invited
        )
        // The record name wins over the email, so the email alone does not match a named one.
        #expect(
            ShareParticipantRules.participant(
                forMemberID: Self.memberID(for: "named@example.com"),
                in: [named, invited]
            ) == nil
        )
    }

    @Test("REQ-SHARE-040: a member who already left, or a participant without identity, is not found")
    func removalReportsMissingParticipant() {
        let owner = FakeParticipant(recordName: "_owner", isOwner: true)
        let anonymous = FakeParticipant()

        #expect(
            ShareParticipantRules.participant(
                forMemberID: Self.memberID(for: "_gone"),
                in: [owner, anonymous]
            ) == nil
        )
        #expect(
            ShareParticipantRules.participant(
                forMemberID: Self.memberID(for: "_gone"),
                in: [FakeParticipant]()
            ) == nil
        )
    }

    // MARK: - REQ-SHARE-020 everyone who joined can edit

    @Test("REQ-SHARE-020: read-only and unknown participants become read-write; the owner is left alone")
    func readWriteGrantSkipsOwner() {
        let owner = FakeParticipant(recordName: "_owner", isOwner: true, permission: .readOnly)
        let readOnly = FakeParticipant(recordName: "_anna", permission: .readOnly)
        let unknown = FakeParticipant(recordName: "_igor", permission: .unknown)

        #expect(ShareParticipantRules.grantReadWrite(to: [owner, readOnly, unknown]))

        #expect(readOnly.permission == .readWrite)
        #expect(unknown.permission == .readWrite)
        #expect(owner.permission == .readOnly)
    }

    @Test("REQ-SHARE-020: participants who already edit report no change, so nothing is saved")
    func readWriteGrantIsIdempotent() {
        let owner = FakeParticipant(recordName: "_owner", isOwner: true, permission: .readWrite)
        let member = FakeParticipant(recordName: "_anna", permission: .readWrite)

        #expect(!ShareParticipantRules.grantReadWrite(to: [owner, member]))
        #expect(member.permission == .readWrite)
        #expect(!ShareParticipantRules.grantReadWrite(to: [FakeParticipant]()))
    }

    @Test("REQ-SHARE-020: a share with only its owner reports no change")
    func readWriteGrantOwnerOnly() {
        let owner = FakeParticipant(recordName: "_owner", isOwner: true, permission: .readOnly)

        #expect(!ShareParticipantRules.grantReadWrite(to: [owner]))
        #expect(owner.permission == .readOnly)
    }

    @Test("REQ-SHARE-020: the CloudKit owner participant goes through the same seam untouched")
    func realShareOwnerIsExcluded() throws {
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        let owner = try #require(share.participants.first)
        let permission = owner.permission

        #expect(owner.isOwner)
        #expect(!ShareParticipantRules.grantReadWrite(to: share.participants))
        #expect(owner.permission == permission)
    }
}
