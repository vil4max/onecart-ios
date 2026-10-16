import Foundation

/// State derived from the session's own properties and its collaborators.
extension AppSession {
    var alertMessage: String? {
        userAlert?.message
    }

    var lists: [ShoppingListEntity] {
        cartContent.lists
    }

    var activeLists: [ShoppingListEntity] {
        cartContent.activeLists
    }

    var products: [ProductEntity] {
        cartContent.products
    }

    var history: [PurchaseHistoryEntity] {
        cartContent.history
    }

    var historyHasMore: Bool {
        cartContent.historyHasMore
    }

    var preparedInviteLink: FamilyInviteLink? {
        invitePreparer.preparedInviteLink
    }

    var canEdit: Bool {
        !isReconcilingPersonalCart && !isDeletingAccount && activeFamilySpace != nil && (access?.canEdit ?? false)
    }

    var isOnline: Bool {
        online
    }

    var isCartSyncing: Bool {
        cartSync.isCartSyncing
    }

    var contentRevision: Int {
        cartSync.contentRevision
    }

    var pendingCartMutationCount: Int {
        cartMutations.pendingCartMutationCount
    }

    var cartTitle: String {
        activeFamilySpace?.displayName
            ?? account.map { Self.householdCartName(for: $0) }
            ?? Self.defaultFamilyName
    }

    /// The name stamped on the lines this user adds or checks.
    var participantName: String? {
        Self.participantName(preferences: preferences, account: account)
    }

    var currentUserRecordName: String? {
        guard let knownUserRecordName,
            knownUserRecordName.generation == cloudUserIdentity.identityGeneration
        else { return nil }
        return knownUserRecordName.name
    }

    /// The record name is nil until the iCloud identity lookup finishes; lines written before
    /// then carry only the name, and notifications fall back to comparing names for them.
    var cartAuthor: CartAuthor {
        CartAuthor(displayName: participantName, recordName: currentUserRecordName)
    }

    static func householdCartName(for account: OneCartAccount) -> String {
        let trimmed = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            !ParticipantDisplayName.isPlaceholder(trimmed)
        else {
            return defaultFamilyName
        }
        return String(localized: "cart.personal_title \(trimmed)")
    }
}
