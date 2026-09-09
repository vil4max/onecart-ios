import CoreData
import Foundation
import OSLog

@MainActor
protocol HouseholdCartHost: AnyObject {
    var account: OneCartAccount? { get }
    var activeFamilySpace: FamilySpace? { get }
    var familySpaces: [FamilySpace] { get }
    var access: FamilyAccess? { get }
    var isBusy: Bool { get }
    var pendingCartMutationCount: Int { get }
    var isReconcilingPersonalCart: Bool { get set }
    var isEnsuringHouseholdCart: Bool { get }
    var lastActiveFamilyWasShared: Bool { get set }
    var sharedCartRemovedMessage: String? { get set }

    func applyEnsuringHouseholdCart(_ value: Bool)
    func applyHouseholdCartBootstrapFailed(_ value: Bool)
    func acceptPendingCloudKitShares() async
    func reloadHousehold(preferredFamilySpaceID: UUID?) throws
    func refreshFamilyMetadata(showErrors: Bool) async
    func scheduleInviteLinkPreparation()
    func presentHouseholdError(_ error: Error)
    func activeFamilyKey(accountID: UUID) -> String
    func householdDisplayName(for account: OneCartAccount) -> String
}

@MainActor
final class HouseholdCartCoordinator {
    private let persistence: PersistenceController
    private let repository: FamilySpaceRepository
    private let defaults: UserDefaults
    private weak var host: (any HouseholdCartHost)?

    init(
        persistence: PersistenceController,
        repository: FamilySpaceRepository,
        defaults: UserDefaults
    ) {
        self.persistence = persistence
        self.repository = repository
        self.defaults = defaults
    }

    func bind(host: any HouseholdCartHost) {
        self.host = host
    }

    func ensureHouseholdCartIfNeeded() async {
        guard let host else { return }
        guard let account = host.account else {
            if host.activeFamilySpace == nil {
                host.applyHouseholdCartBootstrapFailed(true)
            }
            CartSyncLog.action.error("ensureHousehold denied noAccount")
            return
        }
        guard !host.isEnsuringHouseholdCart else {
            CartSyncLog.action.info("ensureHousehold skip alreadyRunning")
            return
        }

        if host.activeFamilySpace != nil {
            host.applyHouseholdCartBootstrapFailed(false)
            do {
                try await offerSharedCartJoinIfNeeded(for: account)
            } catch {
                host.presentHouseholdError(error)
            }
            return
        }

        CartSyncLog.action.info("ensureHousehold start")
        host.applyEnsuringHouseholdCart(true)
        host.applyHouseholdCartBootstrapFailed(false)
        defer { host.applyEnsuringHouseholdCart(false) }

        do {
            await host.acceptPendingCloudKitShares()
            guard !Task.isCancelled else { return }
            try host.reloadHousehold(preferredFamilySpaceID: nil)
            try await offerSharedCartJoinIfNeeded(for: account)
            guard !Task.isCancelled else { return }

            if host.activeFamilySpace != nil {
                try await adoptSharedFamilyCartIfNeeded(for: account)
                await host.refreshFamilyMetadata(showErrors: false)
                host.scheduleInviteLinkPreparation()
                CartSyncLog.action.info(
                    "ensureHousehold done family=\(host.activeFamilySpace?.id?.uuidString ?? "-", privacy: .public)"
                )
                return
            }

            if host.familySpaces.isEmpty {
                CartSyncLog.action.info("ensureHousehold create empty")
                _ = try await createProvisionalPersonalCart(for: account)
                guard !Task.isCancelled else { return }
                try host.reloadHousehold(preferredFamilySpaceID: nil)
            }

            if host.activeFamilySpace == nil {
                host.applyHouseholdCartBootstrapFailed(true)
                CartSyncLog.action.error("ensureHousehold fail noActiveFamily")
                return
            }

            await host.refreshFamilyMetadata(showErrors: false)
            host.scheduleInviteLinkPreparation()
            CartSyncLog.action.info(
                "ensureHousehold done family=\(host.activeFamilySpace?.id?.uuidString ?? "-", privacy: .public)"
            )
        } catch {
            guard !Task.isCancelled else { return }
            host.applyHouseholdCartBootstrapFailed(true)
            CartSyncLog.action.error(
                "ensureHousehold fail error=\(error.localizedDescription, privacy: .public)"
            )
            host.presentHouseholdError(error)
        }
    }

    func retryHouseholdCartBootstrap() async {
        host?.applyHouseholdCartBootstrapFailed(false)
        await ensureHouseholdCartIfNeeded()
    }

    func finishFamilyCartSetup(for account: OneCartAccount) async throws {
        guard let host else { return }
        try host.reloadHousehold(preferredFamilySpaceID: restoredPersonalFamilyID(accountID: account.id))
        if host.familySpaces.isEmpty {
            _ = try await createProvisionalPersonalCart(for: account)
            try host.reloadHousehold(preferredFamilySpaceID: nil)
        }
        try await offerSharedCartJoinIfNeeded(for: account)
    }

    func offerSharedCartJoinIfNeeded(for account: OneCartAccount) async throws {
        try await reconcileProvisionalPersonalCartIfNeeded(for: account)
        try await adoptSharedFamilyCartIfNeeded(for: account)
    }

    func reconcileProvisionalPersonalCartIfNeeded(for account: OneCartAccount) async throws {
        guard let host, host.account?.id == account.id,
              !host.isReconcilingPersonalCart, !host.isBusy,
              host.pendingCartMutationCount == 0,
              let sourceID = defaults.string(forKey: Self.provisionalFamilyKey(accountID: account.id))
              .flatMap(UUID.init(uuidString:))
        else { return }

        let spaces = try repository.fetchFamilySpaces(for: account.id)
        guard !spaces.contains(where: { persistence.scope(for: $0) == .shared }),
              let source = spaces.first(where: { $0.id == sourceID }),
              persistence.scope(for: source) == .private,
              let sourceDate = source.createdAt
        else { return }
        let candidates = spaces.filter { space in
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
        guard let destinationID = candidates.first?.id else { return }

        host.isReconcilingPersonalCart = true
        defer { host.isReconcilingPersonalCart = false }
        let restored = try await repository.restoreProvisionalPersonalContent(
            from: sourceID,
            into: destinationID,
            accountID: account.id
        )
        guard restored, !Task.isCancelled, host.account?.id == account.id else { return }
        // Share acceptance can change the active family while the copy is saving.
        if let active = host.activeFamilySpace, persistence.scope(for: active) == .shared {
            return
        }
        try host.reloadHousehold(preferredFamilySpaceID: destinationID)
        guard host.activeFamilySpace?.id == destinationID else { return }
        defaults.set(destinationID.uuidString, forKey: Self.restoredPersonalFamilyKey(accountID: account.id))
        defaults.removeObject(forKey: Self.provisionalFamilyKey(accountID: account.id))
        CartSyncLog.cart.info("restored existing personal cart=\(destinationID.uuidString, privacy: .public)")
    }

    private func createProvisionalPersonalCart(for account: OneCartAccount) async throws -> UUID {
        guard let host else { throw RepositoryError.familySpaceNotFound }
        let familyID = UUID()
        let key = Self.provisionalFamilyKey(accountID: account.id)
        // Persist provenance before the first save so a restart can still adopt a late import.
        defaults.set(familyID.uuidString, forKey: key)
        do {
            return try await repository.createFamilySpace(
                id: familyID,
                name: host.householdDisplayName(for: account),
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

    static func provisionalFamilyKey(accountID: UUID) -> String {
        "onecart.provisional-family-space-id.\(accountID.uuidString)"
    }

    private static func restoredPersonalFamilyKey(accountID: UUID) -> String {
        "onecart.restored-personal-family-space-id.\(accountID.uuidString)"
    }

    func restoredPersonalFamilyID(accountID: UUID) -> UUID? {
        defaults.string(forKey: Self.restoredPersonalFamilyKey(accountID: accountID))
            .flatMap(UUID.init(uuidString:))
    }

    func reactivatePersonalCartIfNeeded(for account: OneCartAccount) async throws {
        guard let host else { return }
        try host.reloadHousehold(preferredFamilySpaceID: nil)
        let hasShared = host.familySpaces.contains { persistence.scope(for: $0) == .shared }
        guard !hasShared else { return }

        let privateSpaces = host.familySpaces.filter {
            persistence.scope(for: $0) == .private && $0.cachedForUserID == account.id
        }
        let restoredID = restoredPersonalFamilyID(accountID: account.id)
        if let privateID = (privateSpaces.first(where: { $0.id == restoredID }) ?? privateSpaces.first)?.id {
            defaults.set(privateID.uuidString, forKey: host.activeFamilyKey(accountID: account.id))
            try host.reloadHousehold(preferredFamilySpaceID: privateID)
            return
        }

        let newID = try await createProvisionalPersonalCart(for: account)
        defaults.set(newID.uuidString, forKey: host.activeFamilyKey(accountID: account.id))
        try host.reloadHousehold(preferredFamilySpaceID: newID)
    }

    func handleInviteeSharedCartGoneIfNeeded() async {
        guard let host, let account = host.account else { return }
        let hasShared = host.familySpaces.contains { persistence.scope(for: $0) == .shared }
        guard !hasShared, host.lastActiveFamilyWasShared || host.access?.isParticipant == true else { return }

        do {
            try await reactivatePersonalCartIfNeeded(for: account)
        } catch {
            host.presentHouseholdError(error)
            return
        }
        host.lastActiveFamilyWasShared = false
        if host.sharedCartRemovedMessage == nil {
            host.sharedCartRemovedMessage = String(localized: "cart.shared_removed_message")
        }
        CartSyncLog.cart.info("invitee shared cart gone; fell back to private")
    }

    private func adoptSharedFamilyCartIfNeeded(for account: OneCartAccount) async throws {
        guard let host else { return }
        try host.reloadHousehold(preferredFamilySpaceID: nil)

        guard let sharedFamily = host.familySpaces.first(where: {
            persistence.scope(for: $0) == .shared
        }), let sharedID = sharedFamily.id else {
            return
        }

        defaults.set(
            sharedID.uuidString,
            forKey: host.activeFamilyKey(accountID: account.id)
        )
        try host.reloadHousehold(preferredFamilySpaceID: sharedID)

        // Other shared families remain intact; selection must never mutate their mirrored data.
        try host.reloadHousehold(preferredFamilySpaceID: sharedID)
        await host.refreshFamilyMetadata(showErrors: false)
        CartSyncLog.cart.info(
            "adoptShared active=\(sharedID.uuidString, privacy: .public) personalKeptHidden"
        )
    }
}
