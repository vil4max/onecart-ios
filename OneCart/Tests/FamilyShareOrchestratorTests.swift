import CoreData
import Foundation
@testable import OneCart
import Testing

/// What the share orchestrator does around the iCloud calls: who triggers the ACL heal, that
/// pending edits reach the store before a share is built, and that cancelling the caller stops
/// the share work.
@Suite("FamilyShareOrchestrator", .removesStores)
@MainActor
struct FamilyShareOrchestratorTests {
    @Test("REQ-SHARE-070: only the owner heals the share ACL")
    func nonOwnerSkipsACLHeal() async throws {
        let fixture = try await CartFixture.make()
        let cloudSharing = RecordingFamilySharing(persistence: fixture.persistence)
        let orchestrator = makeOrchestrator(fixture, cloudSharing)
        let family = try fixture.family

        await orchestrator.ensureOwnerReadWriteACL(for: family, isOwner: false)
        #expect(cloudSharing.record.aclHealCount == 0)

        await orchestrator.ensureOwnerReadWriteACL(for: family, isOwner: true)
        #expect(cloudSharing.record.aclHealCount == 1)
    }

    @Test("REQ-SHARE-070: unsaved cart edits are saved before the invite share is built")
    func dirtyContextIsSavedBeforeSharing() async throws {
        let fixture = try await CartFixture.make()
        let cloudSharing = RecordingFamilySharing(persistence: fixture.persistence)
        let orchestrator = makeOrchestrator(fixture, cloudSharing)
        let family = try fixture.family
        family.name = "Семья"
        #expect(fixture.persistence.container.viewContext.hasChanges)

        let link = try await orchestrator.createInviteLink(for: family)

        #expect(cloudSharing.record.inviteLinkStarts == 1)
        #expect(cloudSharing.record.viewContextDirtyAtInvite == false)
        #expect(link.familyName == "Семья")
    }

    @Test("REQ-SHARE-030: cancelling the caller cancels invite creation and reports the cancellation")
    func cancellationReachesInviteCreation() async throws {
        let fixture = try await CartFixture.make()
        let cloudSharing = RecordingFamilySharing(persistence: fixture.persistence, holdsInviteLink: true)
        let orchestrator = makeOrchestrator(fixture, cloudSharing)
        let family = try fixture.family

        let task = Task { try await orchestrator.createInviteLink(for: family) }
        try await waitUntil { cloudSharing.record.inviteLinkStarts == 1 }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        try await waitUntil { cloudSharing.record.inviteLinkCancelled }
    }

    private func makeOrchestrator(
        _ fixture: CartFixture,
        _ cloudSharing: RecordingFamilySharing
    ) -> FamilyShareOrchestrator {
        FamilyShareOrchestrator(
            persistence: fixture.persistence,
            cloudSharing: cloudSharing
        )
    }

    /// Polls a condition the detached share worker sets; fails after about two seconds.
    private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("condition never became true", sourceLocation: sourceLocation)
    }
}
