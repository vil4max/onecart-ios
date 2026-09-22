import Foundation
@testable import OneCart

@MainActor
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
    var activeLists: [ShoppingListEntity] = []
    let preferences: DevicePreferences
    var productsByListID: [UUID: [ProductEntity]] = [:]

    init(preferences: DevicePreferences) {
        self.preferences = preferences
    }

    func products(inListID listID: UUID) -> [ProductEntity] {
        productsByListID[listID] ?? []
    }
}
