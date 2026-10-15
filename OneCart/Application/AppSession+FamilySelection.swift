import CoreData
import Foundation

extension AppSession {
    /// `endingShoppingTrip` is false when nobody signed out: a failed startup or a reload before
    /// the account is restored keeps the trip for the next start to adopt (REQ-WIDGET-060).
    func clearAccountData(endingShoppingTrip: Bool = true) {
        clearPreparedInviteLink()
        cancelAllCategoryRefinements()
        leaveRecoveryTask?.cancel()
        leaveRecoveryTask = nil
        familySpaces = []
        activeFamilySpace = nil
        cartContent.clearContent()
        familyMembers = []
        access = nil
        lastActiveFamilyWasShared = false
        householdCartBootstrapFailed = false
        isEnsuringHouseholdCart = false
        // Sign out and account deletion end the trip (REQ-WIDGET-060). Queued even without an
        // active trip: a start still waiting in the queue has no active trip yet.
        if endingShoppingTrip {
            shoppingTrip.end()
        }
    }

    func reload(preferredFamilySpaceID: UUID? = nil) throws {
        guard let account else {
            clearAccountData(endingShoppingTrip: false)
            return
        }

        let context = persistence.container.viewContext
        context.processPendingChanges()
        let previousID = activeFamilySpace?.id
        let fetchedSpaces = try repository.fetchFamilySpaces(for: account.id)
        let sharedSpaces = fetchedSpaces.filter { persistence.scope(for: $0) == .shared }
        familySpaces = sharedSpaces.isEmpty ? fetchedSpaces : sharedSpaces

        let storedID =
            preferredFamilySpaceID
            ?? defaults.string(forKey: activeFamilyKey(accountID: account.id))
            .flatMap(UUID.init(uuidString:))
        let selected: FamilySpace? =
            if sharedSpaces.isEmpty {
                storedID.flatMap { id in
                    fetchedSpaces.first { $0.id == id }
                } ?? fetchedSpaces.first
            } else {
                storedID.flatMap { id in
                    sharedSpaces.first { $0.id == id }
                } ?? sharedSpaces.first
            }

        activeFamilySpace = selected
        // Only the shared-gone handler, a deliberate leave and sign-out clear the flag: a reload
        // that falls back to the private cart because the shared one vanished must keep it, or
        // the handler that runs after this reload could never tell the guest what happened.
        if let selected, persistence.scope(for: selected) == .shared {
            lastActiveFamilyWasShared = true
        }
        if let selected, let selectedID = selected.id {
            defaults.set(
                selectedID.uuidString,
                forKey: activeFamilyKey(accountID: account.id)
            )
            try cartContent.reloadContent(familySpaceID: selectedID)
            access = cloudSharing.access(for: selected)
            if previousID != selectedID {
                familyMembers = []
            }
            if invitePreparer.shouldClearCache(forSelectedFamilyID: selectedID) {
                clearPreparedInviteLink()
            }
        } else {
            defaults.removeObject(forKey: activeFamilyKey(accountID: account.id))
            cartContent.clearContent()
            familyMembers = []
            access = nil
            clearPreparedInviteLink()
        }
        updateWidgetSnapshot()
    }

    func refreshProducts() throws {
        guard let selectedID = activeFamilySpace?.id else { return }
        try cartContent.refreshProducts(familySpaceID: selectedID)
        updateWidgetSnapshot()
    }
}
