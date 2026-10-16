import CoreData
import Foundation
@testable import OneCart
import Testing

/// Activity notifications tell the user from a partner by CloudKit identity, with the display
/// name as the fallback for lines that carry none (REQ-WIDGET-030).
@MainActor
@Suite("Cart author identity", .removesStores)
struct CartAuthorIdentityTests {
    private let baselineItem = CartItemSnapshot(id: UUID(), name: "Хлеб", isPurchased: false)

    private func evaluate(
        previous: [CartItemSnapshot],
        current: [CartItemSnapshot],
        userRecordName: String? = "_alex"
    ) -> CartActivityDiff.Result {
        CartActivityDiff.evaluate(
            previous: previous,
            stored: previous,
            current: current,
            currentUserName: "Alex",
            currentUserRecordName: userRecordName,
            isSharedCart: true
        )
    }

    @Test("REQ-WIDGET-030: a partner with the user's display name notifies an addition")
    func samenamePartnerAdditionNotifies() {
        let added = CartItemSnapshot(
            id: UUID(), name: "Молоко", isPurchased: false, createdByName: "Alex", createdByRecordName: "_sam"
        )

        let diff = evaluate(previous: [baselineItem], current: [baselineItem, added])

        #expect(diff.shouldNotify)
        #expect(diff.events == [.itemsAdded(author: "Alex", itemNames: ["Молоко"])])
    }

    @Test("REQ-WIDGET-030: a partner with the user's display name notifies the last check")
    func samenamePartnerCompletionNotifies() {
        let completed = CartItemSnapshot(
            id: baselineItem.id, name: "Хлеб", isPurchased: true,
            purchasedByName: "Alex", purchasedByRecordName: "_sam"
        )

        let diff = evaluate(previous: [baselineItem], current: [completed])

        #expect(diff.events == [.allPurchased(author: "Alex")])
    }

    @Test("REQ-WIDGET-030: the user's own lines never notify, even under another display name")
    func selfActionsDoNotNotify() {
        let added = CartItemSnapshot(
            id: UUID(), name: "Молоко", isPurchased: true,
            createdByName: "Папа", purchasedByName: "Папа",
            createdByRecordName: "_alex", purchasedByRecordName: "_alex"
        )
        let completed = CartItemSnapshot(
            id: baselineItem.id, name: "Хлеб", isPurchased: true,
            purchasedByName: "Alex", purchasedByRecordName: "_alex"
        )

        let diff = evaluate(previous: [baselineItem], current: [completed, added])

        #expect(diff.shouldNotify == false)
        #expect(diff.events.isEmpty)
    }

    @Test("REQ-WIDGET-030: without a record name on either side the display names decide")
    func missingRecordNamesFallBackToDisplayNames() {
        let mine = CartItemSnapshot(id: UUID(), name: "Сыр", isPurchased: false, createdByName: " alex ")
        let partner = CartItemSnapshot(id: UUID(), name: "Чай", isPurchased: false, createdByName: "Maria")
        let unknownUser = CartItemSnapshot(
            id: UUID(), name: "Мёд", isPurchased: false, createdByName: "Alex", createdByRecordName: "_sam"
        )

        let olderClient = evaluate(previous: [baselineItem], current: [baselineItem, mine, partner])
        let lookupPending = evaluate(
            previous: [baselineItem], current: [baselineItem, unknownUser], userRecordName: nil
        )

        #expect(olderClient.events == [.itemsAdded(author: "Maria", itemNames: ["Чай"])])
        #expect(lookupPending.shouldNotify == false)
    }

    @Test("REQ-WIDGET-030: a snapshot stored before record names existed still decodes")
    func storedSnapshotWithoutRecordNamesDecodes() throws {
        let json = #"[{"id":"\#(UUID().uuidString)","name":"Хлеб","isPurchased":false,"createdByName":"Maria"}]"#
        let decoded = try JSONDecoder().decode([CartItemSnapshot].self, from: Data(json.utf8))

        #expect(decoded.first?.createdByName == "Maria")
        #expect(decoded.first?.createdByRecordName == nil)
    }

    @Test("REQ-WIDGET-030: adding and checking stamp the user's record name; unchecking clears it")
    func sessionStampsAndClearsRecordNames() async throws {
        let fixture = try await MembershipSessionFixture.owner(
            displayName: "Alex",
            cloudUserIdentity: FakeCloudUserIdentity(recordName: "_alex")
        )
        await fixture.session.updateParticipantDisplayName("Alex")
        #expect(fixture.session.currentUserRecordName == "_alex")
        let listID = try #require(fixture.session.activeLists.first?.id)
        let id = try #require(await fixture.session.addProduct(toListID: listID, draft: .nameOnly("Молоко")))
        #expect(try await authors(of: id, in: fixture) == Authors(created: "_alex", purchased: nil))

        await fixture.session.setPurchased(productID: id, isPurchased: true)
        #expect(try await authors(of: id, in: fixture) == Authors(created: "_alex", purchased: "_alex"))

        await fixture.session.setPurchased(productID: id, isPurchased: false)
        #expect(try await authors(of: id, in: fixture) == Authors(created: "_alex", purchased: nil))
    }

    private struct Authors: Equatable, Sendable {
        let created: String?
        let purchased: String?
    }

    private func authors(of id: UUID, in fixture: MembershipSessionFixture) async throws -> Authors {
        try await fixture.persistence.performBackgroundTask { context in
            let product = try RepositoryFetch.product(id: id, in: context)
            return Authors(created: product?.createdByRecordName, purchased: product?.purchasedByRecordName)
        }
    }
}
