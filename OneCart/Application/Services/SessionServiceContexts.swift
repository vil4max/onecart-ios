import Foundation

// What the session's services and coordinators read from the session and the session-level
// steps they ask for. The session conforms (`AppSession+Services.swift`,
// `AppSession+Coordinators.swift`); each collaborator takes it in `init` and holds it weakly,
// since the session owns them. No member writes session state; what a flow decides comes back
// as a return value or, for an observer, as a `CloudSyncEvent` (`CloudSyncContext` sits beside
// its coordinator with the events and results it carries).

/// For `HouseholdCartCoordinator`: the selection reload, the share accept and the members refresh
/// it runs between its own steps.
@MainActor
protocol HouseholdCartContext: AnyObject {
    var account: OneCartAccount? { get }
    var activeFamilySpace: FamilySpace? { get }
    var familySpaces: [FamilySpace] { get }
    /// A busy session or a pending cart write defers the personal-cart reconciliation.
    var isBusy: Bool { get }
    var pendingCartMutationCount: Int { get }
    /// A leave the user chose purges the shared zone itself; that is not a removal to report.
    var isLeavingSharedCart: Bool { get }
    func reload(preferredFamilySpaceID: UUID?) throws
    func acceptPendingCloudKitShares() async
    func refreshFamilyMetadata(showErrors: Bool) async
    func scheduleInviteLinkPreparation(delayNanoseconds: UInt64)
}

/// How a household setup or a shared-cart check ended; the caller shows a failure.
enum HouseholdCartOutcome {
    case done
    case failed(Error)
}

/// For `CartMutationService`.
@MainActor
protocol CartMutationContext: AnyObject {
    var account: OneCartAccount? { get }
    var canEdit: Bool { get }
    /// The name stamped on the lines this user adds or checks.
    var participantName: String? { get }
    var lastSyncError: String? { get }
    func reload(preferredFamilySpaceID: UUID?) throws
    func refreshProducts() throws
    func presentAlert(_ message: String, kind: UserAlertKind, playHaptic: Bool)
    func show(_ error: Error)
    func presentProductionSchemaAlertIfNeeded(_ message: String)
    func beginBusyOperation()
    func endBusyOperation()
}

/// For `WidgetPurchaseSync`: the snapshot it draws and the cart a queued purchase must match.
@MainActor
protocol WidgetPurchaseContext: AnyObject {
    var isReady: Bool { get }
    var account: OneCartAccount? { get }
    var activeFamilySpace: FamilySpace? { get }
    var familyMembers: [FamilyMember] { get }
    var canEdit: Bool { get }
    var cartTitle: String { get }
    var isCartSyncing: Bool { get }
    var participantName: String? { get }
    var preferences: DevicePreferences { get }
    func reload(preferredFamilySpaceID: UUID?) throws
    func show(_ error: Error)
}

/// For `CartIntentHandler`: the startup a Siri, widget or Live Activity request waits for.
@MainActor
protocol CartIntentSessionContext: AnyObject {
    var account: OneCartAccount? { get }
    var needsWelcome: Bool { get }
    var activeFamilySpace: FamilySpace? { get }
    var canEdit: Bool { get }
    /// The last start ended on the Welcome failure.
    var startFailed: Bool { get }
    var preferences: DevicePreferences { get }
    func start(retryingFailure: Bool) async
    func ensureHouseholdCartIfNeeded() async
}

/// For `MembershipService`: the active cart and the owner's or guest's role in it.
@MainActor
protocol MembershipContext: AnyObject {
    var account: OneCartAccount? { get }
    var activeFamilySpace: FamilySpace? { get }
    var familySpaces: [FamilySpace] { get }
    var access: FamilyAccess? { get }
    var isOnline: Bool { get }
    func reload(preferredFamilySpaceID: UUID?) throws
    func refreshFamilyMetadata(showErrors: Bool) async
    func scheduleInviteLinkPreparation(delayNanoseconds: UInt64)
    func presentAlert(_ message: String, kind: UserAlertKind, playHaptic: Bool)
    func show(_ error: Error)
    func beginBusyOperation()
    func endBusyOperation()
}

/// For `AccountDeletionService`: the shared cart a guest leaves first, and the cart state
/// dropped before the stores detach.
@MainActor
protocol AccountDeletionContext: AnyObject {
    var access: FamilyAccess? { get }
    var activeFamilySpace: FamilySpace? { get }
    func clearAccountData(endingShoppingTrip: Bool)
}
