import CoreData
import Foundation
import Observation
import OSLog

/// Creates, adopts and restores the household cart and falls a guest back to the personal cart
/// when the shared one is gone. Owns the setup and reconciliation flags the cart screen reads and
/// whether the last active cart was shared.
@MainActor
@Observable
final class HouseholdCartCoordinator {
    private(set) var isEnsuringHouseholdCart = false
    private(set) var householdCartBootstrapFailed = false
    private(set) var isReconcilingPersonalCart = false
    /// Only the shared-gone handler, a deliberate leave and sign-out clear it: a reload that falls
    /// back to the private cart because the shared one vanished must keep it, or the handler that
    /// runs after that reload could never tell the guest what happened.
    private(set) var lastActiveFamilyWasShared = false
    private(set) var sharedCartRemovedMessage: String?

    @ObservationIgnored private weak var context: (any HouseholdCartContext)?
    @ObservationIgnored private let persistence: PersistenceController
    @ObservationIgnored private let families: any FamilyRepository
    @ObservationIgnored private let personalCartRestorer: any PersonalCartRestorer
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isRunningEnsure = false
    /// Callers that arrived while this coordinator's setup was running; resumed when it ends.
    @ObservationIgnored private var ensureWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        context: any HouseholdCartContext,
        persistence: PersistenceController,
        families: any FamilyRepository,
        personalCartRestorer: any PersonalCartRestorer,
        defaults: UserDefaults
    ) {
        self.context = context
        self.persistence = persistence
        self.families = families
        self.personalCartRestorer = personalCartRestorer
        self.defaults = defaults
    }

    /// Sign-out, a failed startup and account deletion drop the account's cart state.
    func reset() {
        lastActiveFamilyWasShared = false
        householdCartBootstrapFailed = false
        isEnsuringHouseholdCart = false
    }

    func rememberSharedCartSelected() {
        lastActiveFamilyWasShared = true
    }

    /// A leave or an account deletion left the shared cart on purpose.
    func forgetSharedCart() {
        lastActiveFamilyWasShared = false
    }

    /// A failed leave keeps the guest on the shared cart while it is still there.
    func leaveFailed(cartStillShared: Bool) {
        lastActiveFamilyWasShared = cartStillShared
    }

    func dismissSharedCartRemovedMessage() {
        sharedCartRemovedMessage = nil
    }

    private func isShared(_ family: FamilySpace) -> Bool {
        persistence.scope(for: family) == .shared
    }
}

// MARK: - Ensure

extension HouseholdCartCoordinator {
    func ensureHouseholdCartIfNeeded() async -> HouseholdCartOutcome {
        guard let context else { return .done }
        guard let account = context.account else {
            if context.activeFamilySpace == nil {
                householdCartBootstrapFailed = true
            }
            CartSyncLog.action.error("ensureHousehold denied noAccount")
            return .done
        }
        guard !isEnsuringHouseholdCart else {
            await waitForRunningEnsure()
            return .done
        }

        if context.activeFamilySpace != nil {
            householdCartBootstrapFailed = false
            do {
                try await offerSharedCartJoinIfNeeded(for: account)
            } catch {
                return .failed(error)
            }
            return .done
        }

        CartSyncLog.action.info("ensureHousehold start")
        isEnsuringHouseholdCart = true
        householdCartBootstrapFailed = false
        isRunningEnsure = true
        defer {
            isEnsuringHouseholdCart = false
            finishRunningEnsure()
        }

        do {
            try await runEnsure(context: context, account: account)
        } catch {
            guard !Task.isCancelled else { return .done }
            householdCartBootstrapFailed = true
            CartSyncLog.action.error(
                "ensureHousehold fail error=\(error.localizedDescription, privacy: .public)"
            )
            return .failed(error)
        }
        return .done
    }

    private func runEnsure(context: any HouseholdCartContext, account: OneCartAccount) async throws {
        await context.acceptPendingCloudKitShares()
        guard !Task.isCancelled else { return }
        try context.reload(preferredFamilySpaceID: nil)
        try await offerSharedCartJoinIfNeeded(for: account)
        guard !Task.isCancelled else { return }

        if context.activeFamilySpace != nil {
            try await adoptSharedFamilyCartIfNeeded(for: account)
            await finishEnsure(context: context)
            return
        }

        if context.familySpaces.isEmpty {
            CartSyncLog.action.info("ensureHousehold create empty")
            _ = try await createProvisionalPersonalCart(for: account)
            guard !Task.isCancelled else { return }
            try context.reload(preferredFamilySpaceID: nil)
        }

        if context.activeFamilySpace == nil {
            householdCartBootstrapFailed = true
            CartSyncLog.action.error("ensureHousehold fail noActiveFamily")
            return
        }

        await finishEnsure(context: context)
    }

    private func finishEnsure(context: any HouseholdCartContext) async {
        await context.refreshFamilyMetadata(showErrors: false)
        context.scheduleInviteLinkPreparation(delayNanoseconds: 1_500_000_000)
        CartSyncLog.action.info(
            "ensureHousehold done family=\(context.activeFamilySpace?.id?.uuidString ?? "-", privacy: .public)"
        )
    }

    /// A caller that needs the cart (Siri) must see the result of the running setup, not an
    /// empty cart. A flag this coordinator did not raise has nothing to wait for.
    private func waitForRunningEnsure() async {
        guard isRunningEnsure else {
            CartSyncLog.action.info("ensureHousehold skip alreadyRunning")
            return
        }
        CartSyncLog.action.info("ensureHousehold wait alreadyRunning")
        await withCheckedContinuation { ensureWaiters.append($0) }
    }

    private func finishRunningEnsure() {
        isRunningEnsure = false
        let waiters = ensureWaiters
        ensureWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func retryHouseholdCartBootstrap() async -> HouseholdCartOutcome {
        householdCartBootstrapFailed = false
        return await ensureHouseholdCartIfNeeded()
    }

    func finishFamilyCartSetup(for account: OneCartAccount) async throws {
        guard let context else { return }
        try context.reload(preferredFamilySpaceID: restoredPersonalFamilyID(accountID: account.id))
        if context.familySpaces.isEmpty {
            _ = try await createProvisionalPersonalCart(for: account)
            try context.reload(preferredFamilySpaceID: nil)
        }
        try await offerSharedCartJoinIfNeeded(for: account)
    }

    func offerSharedCartJoinIfNeeded(for account: OneCartAccount) async throws {
        try await reconcileProvisionalPersonalCartIfNeeded(for: account)
        try await adoptSharedFamilyCartIfNeeded(for: account)
    }
}

// MARK: - Personal cart

extension HouseholdCartCoordinator {
    func reconcileProvisionalPersonalCartIfNeeded(for account: OneCartAccount) async throws {
        guard let context, context.account?.id == account.id,
            !isReconcilingPersonalCart, !context.isBusy,
            context.pendingCartMutationCount == 0,
            let sourceID = defaults.string(forKey: Self.provisionalFamilyKey(accountID: account.id))
                .flatMap(UUID.init(uuidString:))
        else { return }

        let spaces = try families.fetchFamilySpaces(for: account.id)
        guard !spaces.contains(where: isShared),
            let source = spaces.first(where: { $0.id == sourceID }),
            persistence.scope(for: source) == .private,
            let sourceDate = source.createdAt
        else { return }
        guard let destinationID = olderPrivateCarts(in: spaces, than: sourceDate, excluding: sourceID).first?.id
        else { return }

        isReconcilingPersonalCart = true
        defer { isReconcilingPersonalCart = false }
        let restored = try await personalCartRestorer.restoreProvisionalPersonalContent(
            from: sourceID,
            into: destinationID,
            accountID: account.id
        )
        guard restored, !Task.isCancelled, context.account?.id == account.id else { return }
        // Share acceptance can change the active family while the copy is saving.
        if let active = context.activeFamilySpace, isShared(active) {
            return
        }
        try context.reload(preferredFamilySpaceID: destinationID)
        guard context.activeFamilySpace?.id == destinationID else { return }
        defaults.set(destinationID.uuidString, forKey: Self.restoredPersonalFamilyKey(accountID: account.id))
        defaults.removeObject(forKey: Self.provisionalFamilyKey(accountID: account.id))
        CartSyncLog.cart.info("restored existing personal cart=\(destinationID.uuidString, privacy: .public)")
    }

    /// Private carts created before the provisional one, oldest first; the oldest receives its content.
    private func olderPrivateCarts(
        in spaces: [FamilySpace],
        than sourceDate: Date,
        excluding sourceID: UUID
    ) -> [FamilySpace] {
        spaces.filter { space in
            guard space.id != sourceID, persistence.scope(for: space) == .private,
                let createdAt = space.createdAt
            else { return false }
            return createdAt < sourceDate
        }.sorted { lhs, rhs in
            if lhs.createdDate != rhs.createdDate {
                return lhs.createdDate < rhs.createdDate
            }
            return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
        }
    }

    private func createProvisionalPersonalCart(for account: OneCartAccount) async throws -> UUID {
        guard context != nil else { throw RepositoryError.familySpaceNotFound }
        let familyID = UUID()
        let key = Self.provisionalFamilyKey(accountID: account.id)
        // Persist provenance before the first save so a restart can still adopt a late import.
        defaults.set(familyID.uuidString, forKey: key)
        do {
            return try await families.createFamilySpace(
                id: familyID,
                name: AppSession.householdCartName(for: account),
                createdAt: nil,
                cachedForUserID: account.id,
                isHouseholdDefault: true
            )
        } catch {
            if defaults.string(forKey: key) == familyID.uuidString {
                defaults.removeObject(forKey: key)
            }
            throw error
        }
    }

    func reactivatePersonalCartIfNeeded(for account: OneCartAccount) async throws {
        guard let context else { return }
        try context.reload(preferredFamilySpaceID: nil)
        guard !context.familySpaces.contains(where: isShared) else { return }

        let privateSpaces = context.familySpaces.filter {
            persistence.scope(for: $0) == .private && $0.cachedForUserID == account.id
        }
        let restoredID = restoredPersonalFamilyID(accountID: account.id)
        if let privateID = (privateSpaces.first(where: { $0.id == restoredID }) ?? privateSpaces.first)?.id {
            defaults.set(privateID.uuidString, forKey: AppSession.activeFamilyKey(accountID: account.id))
            try context.reload(preferredFamilySpaceID: privateID)
            return
        }

        let newID = try await createProvisionalPersonalCart(for: account)
        defaults.set(newID.uuidString, forKey: AppSession.activeFamilyKey(accountID: account.id))
        try context.reload(preferredFamilySpaceID: newID)
    }

    func restoredPersonalFamilyID(accountID: UUID) -> UUID? {
        defaults.string(forKey: Self.restoredPersonalFamilyKey(accountID: accountID))
            .flatMap(UUID.init(uuidString:))
    }
}

// MARK: - Shared cart

extension HouseholdCartCoordinator {
    func handleInviteeSharedCartGoneIfNeeded() async -> HouseholdCartOutcome {
        guard let context, let account = context.account else { return .done }
        let hasShared = context.familySpaces.contains(where: isShared)
        // A leave the user chose purges the shared zone itself; that is not a removal to report.
        guard !context.isLeavingSharedCart, !hasShared, lastActiveFamilyWasShared else { return .done }

        do {
            try await reactivatePersonalCartIfNeeded(for: account)
        } catch {
            return .failed(error)
        }
        lastActiveFamilyWasShared = false
        if sharedCartRemovedMessage == nil {
            sharedCartRemovedMessage = String(localized: "cart.shared_removed_message")
        }
        CartSyncLog.cart.info("invitee shared cart gone; fell back to private")
        return .done
    }

    private func adoptSharedFamilyCartIfNeeded(for account: OneCartAccount) async throws {
        guard let context else { return }
        // With shared spaces present this reload already activates the stored shared cart, or the first one.
        try context.reload(preferredFamilySpaceID: nil)

        let sharedIDs = context.familySpaces.filter(isShared).compactMap(\.id)
        guard !sharedIDs.isEmpty else { return }

        // This runs on every cloud import and spaces arrive sorted by `updatedAt`, so picking the
        // first shared space would flip the active cart to whichever family was edited last.
        // Only a shared space this device has not seen yet (a fresh join) may take over.
        let knownKey = Self.knownSharedFamiliesKey(accountID: account.id)
        let knownIDs = Set(defaults.stringArray(forKey: knownKey) ?? [])
        defaults.set(sharedIDs.map(\.uuidString), forKey: knownKey)

        if let joinedID = sharedIDs.first(where: { !knownIDs.contains($0.uuidString) }),
            joinedID != context.activeFamilySpace?.id
        {
            defaults.set(joinedID.uuidString, forKey: AppSession.activeFamilyKey(accountID: account.id))
            // Other shared families remain intact; selection must never mutate their mirrored data.
            try context.reload(preferredFamilySpaceID: joinedID)
        }
        await context.refreshFamilyMetadata(showErrors: false)
        let activeID = context.activeFamilySpace?.id?.uuidString ?? "-"
        CartSyncLog.cart.info("adoptShared active=\(activeID, privacy: .public) personalKeptHidden")
    }
}

// MARK: - Stored keys

extension HouseholdCartCoordinator {
    static func provisionalFamilyKey(accountID: UUID) -> String {
        "onecart.provisional-family-space-id.\(accountID.uuidString)"
    }

    private static func restoredPersonalFamilyKey(accountID: UUID) -> String {
        "onecart.restored-personal-family-space-id.\(accountID.uuidString)"
    }

    private static func knownSharedFamiliesKey(accountID: UUID) -> String {
        "onecart.known-shared-family-space-ids.\(accountID.uuidString)"
    }

    /// Account deletion only: sign-out keeps the provenance so signing back in can still
    /// reconcile the provisional cart with a late import.
    static func clearPersonalCartKeys(accountID: UUID, defaults: UserDefaults) {
        defaults.removeObject(forKey: provisionalFamilyKey(accountID: accountID))
        defaults.removeObject(forKey: restoredPersonalFamilyKey(accountID: accountID))
    }

    /// Sign-out keeps the known set so signing back in does not switch carts again;
    /// account deletion removes it with the rest of the account's local state.
    static func clearKnownSharedFamilies(accountID: UUID, defaults: UserDefaults) {
        defaults.removeObject(forKey: knownSharedFamiliesKey(accountID: accountID))
    }
}
