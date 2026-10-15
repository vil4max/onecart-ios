import Foundation
@testable import OneCart

@MainActor
@Observable
final class FakeSessionState: SessionStateReading {
    var isReady = true
    var needsWelcome = false
    var account: OneCartAccount?
    var activeFamilySpace: FamilySpace?
    var isActiveFamilySpacePrivate = false
    var familyMembers: [FamilyMember] = []
    var access: FamilyAccess?
    var canEdit = true
    var isOnline = true
    var isBusy = false
    var isCartSyncing = false
    var isFamilyMetadataLoading = false
    var isDeletingAccount = false
    var contentRevision = 0
    var cartTitle = "Family"
    var cartLists: [CartList] = []
    var hasActiveCartLists = false
    let preferences: DevicePreferences
    var itemsByListID: [UUID: [CartItem]] = [:]

    init(preferences: DevicePreferences) {
        self.preferences = preferences
    }

    func cartItems(inListID listID: UUID) -> [CartItem] {
        itemsByListID[listID] ?? []
    }
}
