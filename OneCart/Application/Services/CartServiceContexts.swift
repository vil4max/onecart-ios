import Foundation

// What the session's cart services read from the session and the session-level effects they
// ask for. The session conforms (`AppSession+Services.swift`); each service takes it in `init`
// and holds it weakly, since the session owns the services. No member writes session state.

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
