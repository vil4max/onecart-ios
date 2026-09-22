import Foundation
@testable import OneCart
import Testing

/// The notifiers' stored baselines. Notification delivery itself goes through
/// `UNUserNotificationCenter` and is not observable from a unit test; the diff rules are
/// covered by `CartActivityDiffTests` and `MemberJoinDiffTests`.
@Suite("Activity notifier storage")
@MainActor
struct ActivityNotifierStorageTests {
    private func snapshotKey(_ cartID: UUID) -> String {
        "onecart.cart-activity-snapshot.\(cartID.uuidString)"
    }

    private func storedSnapshot(_ cartID: UUID, in defaults: UserDefaults) throws -> [CartItemSnapshot] {
        let data = try #require(defaults.data(forKey: snapshotKey(cartID)))
        return try JSONDecoder().decode([CartItemSnapshot].self, from: data)
    }

    @Test("REQ-WIDGET-030: the first observation of a shared cart only seeds the stored baseline")
    func firstObservationSeedsBaseline() throws {
        let isolated = try IsolatedPreferences()
        let cartID = UUID()
        let items = [
            CartItemSnapshot(id: UUID(), name: "Хлеб", isPurchased: false, createdByName: "Maria"),
            CartItemSnapshot(id: UUID(), name: "Молоко", isPurchased: true, createdByName: "Alex"),
        ]

        CartActivityNotifier.notifyIfNeeded(
            cartID: cartID,
            previous: [],
            current: items,
            currentUserName: "Alex",
            isSharedCart: true,
            defaults: isolated.defaults
        )

        #expect(try storedSnapshot(cartID, in: isolated.defaults) == items)
    }

    @Test("REQ-WIDGET-030: a single-user cart still stores its snapshot for the day it becomes shared")
    func singleUserCartStoresSnapshot() throws {
        let isolated = try IsolatedPreferences()
        let cartID = UUID()
        let items = [CartItemSnapshot(id: UUID(), name: "Хлеб", isPurchased: false, createdByName: "Alex")]

        CartActivityNotifier.notifyIfNeeded(
            cartID: cartID,
            previous: [],
            current: items,
            currentUserName: "Alex",
            isSharedCart: false,
            defaults: isolated.defaults
        )

        #expect(try storedSnapshot(cartID, in: isolated.defaults) == items)
    }

    @Test("The stored baseline is replaced by each observation and kept per cart")
    func storedBaselineFollowsObservationsPerCart() throws {
        let isolated = try IsolatedPreferences()
        let cartID = UUID()
        let otherCartID = UUID()
        let bread = CartItemSnapshot(id: UUID(), name: "Хлеб", isPurchased: false, createdByName: "Maria")
        let milk = CartItemSnapshot(id: UUID(), name: "Молоко", isPurchased: false, createdByName: "Alex")

        CartActivityNotifier.notifyIfNeeded(
            cartID: cartID,
            previous: [],
            current: [bread],
            currentUserName: "Alex",
            isSharedCart: true,
            defaults: isolated.defaults
        )
        CartActivityNotifier.notifyIfNeeded(
            cartID: cartID,
            previous: [],
            current: [bread, milk],
            currentUserName: "Alex",
            isSharedCart: true,
            defaults: isolated.defaults
        )

        #expect(try storedSnapshot(cartID, in: isolated.defaults) == [bread, milk])
        #expect(isolated.defaults.data(forKey: snapshotKey(otherCartID)) == nil)
    }

    @Test("A corrupt stored snapshot is treated as a first observation")
    func corruptSnapshotIsReplaced() throws {
        let isolated = try IsolatedPreferences()
        let cartID = UUID()
        isolated.defaults.set(Data("not json".utf8), forKey: snapshotKey(cartID))
        let items = [CartItemSnapshot(id: UUID(), name: "Хлеб", isPurchased: false, createdByName: "Maria")]

        CartActivityNotifier.notifyIfNeeded(
            cartID: cartID,
            previous: [],
            current: items,
            currentUserName: "Alex",
            isSharedCart: true,
            defaults: isolated.defaults
        )

        #expect(try storedSnapshot(cartID, in: isolated.defaults) == items)
    }

    @Test("REQ-WIDGET-030: the first member list seeds the seen set, which sign-out clears")
    func memberSeenSetIsSeededAndCleared() throws {
        let isolated = try IsolatedPreferences()
        let accountID = UUID()
        let seenKey = "onecart.seen-member-ids.\(accountID.uuidString)"
        let me = FamilyMember(
            id: accountID,
            displayName: "Alex",
            access: .owner,
            joinedAt: Date(),
            isCurrentUser: true,
            avatarURL: nil,
            bannerURL: nil
        )
        let guest = FamilyMember(
            id: UUID(),
            displayName: "Sam",
            access: .member,
            joinedAt: Date(),
            isCurrentUser: false,
            avatarURL: nil,
            bannerURL: nil
        )

        MemberJoinNotifier.notifyNewMembersIfNeeded(
            previousIDs: [],
            current: [me, guest],
            accountID: accountID,
            defaults: isolated.defaults
        )
        let stored = Set(isolated.defaults.array(forKey: seenKey) as? [String] ?? [])
        #expect(stored == [me.id.uuidString, guest.id.uuidString])

        MemberJoinNotifier.notifyNewMembersIfNeeded(
            previousIDs: [me.id, guest.id],
            current: [me, guest],
            accountID: accountID,
            defaults: isolated.defaults
        )
        #expect(Set(isolated.defaults.array(forKey: seenKey) as? [String] ?? []) == stored)

        MemberJoinNotifier.clearSeenMembers(accountID: accountID, defaults: isolated.defaults)
        #expect(isolated.defaults.array(forKey: seenKey) == nil)
    }
}
