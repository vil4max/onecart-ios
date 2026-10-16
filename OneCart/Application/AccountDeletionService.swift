import Foundation
import OSLog

struct AccountDeletionDependencies {
    let persistence: PersistenceController
    let cloudSharing: any FamilyCloudSharing
    let families: any FamilyRepository
    let household: HouseholdCartCoordinator
    let localStores: any AccountLocalStorePreparing
    let cloudData: any AccountCloudDataDeleting
    let widgetStore: any WidgetSnapshotStoring
}

/// What a deletion attempt has to do, read once before it starts.
struct AccountDeletionPlan {
    /// An earlier attempt deleted the iCloud data; only the local cleanup is left.
    let cloudAlreadyDeleted: Bool
    let requiresNetwork: Bool
}

enum AccountDeletionOutcome {
    case deleted
    /// The local stores are back in place; the session restores the rest of its state.
    case failed(Error, didLeaveShared: Bool)
}

/// Deletes the account's data: leaves a shared cart the user is a guest of, deletes the private
/// iCloud zone and replaces the local stores with empty ones, then clears the widget data. A
/// failed attempt puts the detached stores back before it reports. Shared carts owned by this
/// user go with the private zone; member carts stay for the others.
@MainActor
final class AccountDeletionService {
    private weak var context: (any AccountDeletionContext)?
    private let dependencies: AccountDeletionDependencies

    init(context: any AccountDeletionContext, dependencies: AccountDeletionDependencies) {
        self.context = context
        self.dependencies = dependencies
    }

    func plan() -> AccountDeletionPlan {
        let persistence = dependencies.persistence
        let cloudAlreadyDeleted = (try? persistence.readAccountDeletionPhase()) == .cloudDeleted
        return AccountDeletionPlan(
            cloudAlreadyDeleted: cloudAlreadyDeleted,
            requiresNetwork: persistence.cloudKitEnabled && !cloudAlreadyDeleted
        )
    }

    /// The steps a failed deletion has to undo.
    private struct Progress {
        var didLeaveShared = false
        var didDetachLocalStores = false
    }

    func deleteAccountData(_ plan: AccountDeletionPlan) async -> AccountDeletionOutcome {
        var progress = Progress()
        do {
            try await runDeletion(plan, progress: &progress)
            return .deleted
        } catch {
            CartSyncLog.action.error(
                "deleteAccount fail error=\(error.localizedDescription, privacy: .public)"
            )
            if progress.didDetachLocalStores {
                try? await dependencies.localStores.restoreLocalStoresAfterFailedCloudAccountDeletion()
            }
            return .failed(error, didLeaveShared: progress.didLeaveShared)
        }
    }

    private func runDeletion(_ plan: AccountDeletionPlan, progress: inout Progress) async throws {
        if !plan.cloudAlreadyDeleted {
            progress.didLeaveShared = try await leaveSharedCartIfParticipant()
            // Keep account and SIWA until both cloud deletion and local cleanup succeed.
            context?.clearAccountData(endingShoppingTrip: true)
            try await dependencies.localStores.detachLocalStoresForCloudAccountDeletion()
            progress.didDetachLocalStores = true
            try await dependencies.cloudData.deletePrivateAccountCloudData()
        }
        try await dependencies.localStores.attachEmptyLocalStoresAfterCloudAccountDeletion()
        try dependencies.widgetStore.clear()
    }

    private func leaveSharedCartIfParticipant() async throws -> Bool {
        guard let context, context.access?.isParticipant == true,
            let family = context.activeFamilySpace,
            let familyID = family.id
        else { return false }

        CartSyncLog.action.info(
            "deleteAccount leaveShared family=\(familyID.uuidString, privacy: .public)"
        )
        let discardLeftovers = try await dependencies.cloudSharing.leaveFamily(objectID: family.objectID)
        if discardLeftovers {
            do {
                try await dependencies.families.discardLocalSharedFamilySpace(id: familyID)
            } catch let error as RepositoryError where error == .familySpaceNotFound {
                CartSyncLog.action.info("deleteAccount leaveShared local already gone")
            }
        }
        dependencies.household.forgetSharedCart()
        return true
    }
}
