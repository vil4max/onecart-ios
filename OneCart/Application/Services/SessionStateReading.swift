import Foundation

/// Read-only session state the screens observe; mutations go through the role protocols.
@MainActor
protocol SessionStateReading: AnyObject {
    var isReady: Bool { get }
    var needsWelcome: Bool { get }
    var account: OneCartAccount? { get }
    /// Still a Core Data entity: the screens only test it for presence, and moving it to a value
    /// touches every membership path.
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
    var cartLists: [CartList] { get }
    /// True when the active cart has active lists, even when `cartLists` is empty because the
    /// primary one has no stable ID.
    var hasActiveCartLists: Bool { get }
    var preferences: DevicePreferences { get }
    /// The list's lines in cart order: newest to-buy first, then completed (REQ-SHELL-010).
    func cartItems(inListID listID: UUID) -> [CartItem]
}
