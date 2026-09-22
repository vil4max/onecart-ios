import CloudKit
import Foundation
@testable import OneCart
import Testing

/// How the members list names each share participant (REQ-AUTH-040): the shared profile, then
/// the iCloud name, then a numbered label; the current user always sees their own name.
@Suite("FamilyMemberNamingTests")
struct FamilyMemberNamingTests {
    private let account = OneCartAccount(id: UUID(), displayName: "Alex")
    private let joinedAt = Date(timeIntervalSinceReferenceDate: 0)

    private func participant(
        _ recordName: String,
        identityName: String? = nil,
        isOwner: Bool = false,
        isCurrentUser: Bool = false
    ) -> ShareParticipantSummary {
        ShareParticipantSummary(
            recordName: recordName,
            identityName: identityName,
            isOwner: isOwner,
            isCurrentUser: isCurrentUser
        )
    }

    private func names(
        _ participants: [ShareParticipantSummary],
        profiles: [String: String] = [:],
        currentUserRecordName: String? = nil
    ) -> [String: String] {
        let members = FamilyMemberNaming.members(
            participants: participants,
            profileNames: profiles,
            currentUserRecordName: currentUserRecordName,
            account: account,
            joinedAt: joinedAt
        )
        var byRecord: [String: String] = [:]
        for participant in participants {
            let id = FamilyInviteLinkBuilder.stableUUID(for: participant.recordName)
            byRecord[participant.recordName] = members.first { $0.id == id }?.displayName
        }
        return byRecord
    }

    @Test("REQ-AUTH-040: a participant's shared profile name wins over the iCloud name")
    func profileNameWinsOverIdentityName() {
        let result = names(
            [
                participant(CKCurrentUserDefaultName, isOwner: true, isCurrentUser: true),
                participant("_sam", identityName: "Samuel Appleseed"),
            ],
            profiles: ["_sam": "Sam"]
        )
        #expect(result["_sam"] == "Sam")
    }

    @Test("REQ-AUTH-040: without a profile the iCloud name is used, then a numbered label")
    func identityNameThenNumberedFallback() {
        let result = names([
            participant(CKCurrentUserDefaultName, isOwner: true, isCurrentUser: true),
            participant("_bea", identityName: "Bea"),
            participant("_cid"),
        ])
        #expect(result["_bea"] == "Bea")
        #expect(result["_cid"] == String(localized: "members.numbered_fallback \(3)"))
        #expect(result["_cid"]?.hasPrefix("members.") == false)
        #expect(result["_cid"]?.contains("3") == true)
    }

    @Test("REQ-AUTH-040: numbered labels are distinct and do not depend on the participant order")
    func numberedLabelsAreStable() {
        let owner = participant("_owner", isOwner: true)
        let first = participant("_aaa")
        let second = participant("_bbb")
        let current = participant("_me", isCurrentUser: true)

        let forward = names([owner, first, second, current])
        let reversed = names([current, second, first, owner])

        #expect(forward == reversed)
        let labels = [forward["_owner"], forward["_aaa"], forward["_bbb"]].compactMap(\.self)
        #expect(Set(labels).count == 3)
        #expect(forward["_owner"] == String(localized: "members.numbered_fallback \(1)"))
        #expect(forward["_me"] == "Alex")
    }

    @Test("REQ-AUTH-040: the current user keeps the account name, also as the default owner or by record name")
    func currentUserKeepsAccountName() {
        let asDefaultOwner = names(
            [participant(CKCurrentUserDefaultName, isOwner: true), participant("_sam")],
            profiles: [CKCurrentUserDefaultName: "Stale", "_sam": "Sam"]
        )
        #expect(asDefaultOwner[CKCurrentUserDefaultName] == "Alex")

        let byRecordName = names(
            [participant("_owner", isOwner: true), participant("_alex")],
            profiles: ["_alex": "Old name", "_owner": "Mom"],
            currentUserRecordName: "_alex"
        )
        #expect(byRecordName["_alex"] == "Alex")
        #expect(byRecordName["_owner"] == "Mom")
    }

    @Test("REQ-AUTH-040: the owner leads the list and marks exactly one current user")
    func ownerLeadsAndOneCurrentUser() {
        let members = FamilyMemberNaming.members(
            participants: [
                participant("_zed", identityName: "Zed"),
                participant("_owner", isOwner: true),
                participant("_alex", isCurrentUser: true),
            ],
            profileNames: ["_owner": "Mom"],
            currentUserRecordName: "_alex",
            account: account,
            joinedAt: joinedAt
        )
        #expect(members.first?.displayName == "Mom")
        #expect(members.first?.access == .owner)
        #expect(members.filter(\.isCurrentUser).map(\.displayName) == ["Alex"])
        #expect(members.count == 3)
    }
}
