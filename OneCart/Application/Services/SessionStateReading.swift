import Foundation

/// Read-only session state the screens observe; mutations go through the role protocols.
@MainActor
protocol SessionStateReading: AnyObject {
    var isReady: Bool { get }
    var needsWelcome: Bool { get }
    var account: OneCartAccount? { get }
    var activeFamilySpace: FamilySpace? { get }
    /// True when the active cart lives in the private store, i.e. is not a shared family cart.
    var isActiveFamilySpacePrivate: Bool { get }
    var familyMembers: [FamilyMember] { get }
    var access: FamilyAccess? { get }
    var canEdit: Bool { get }
    var isOnline: Bool { get }
    var isBusy: Bool { get }
    var isCartSyncing: Bool { get }
    var isFamilyMetadataLoading: Bool { get }
    var isDeletingAccount: Bool { get }
    /// Bumps after every content change so screens can react without diffing entities.
    var contentRevision: Int { get }
    var cartTitle: String { get }
    var activeLists: [ShoppingListEntity] { get }
    var preferences: DevicePreferences { get }
    func products(inListID listID: UUID) -> [ProductEntity]
}
