import CoreData
import Foundation
import OSLog

@MainActor
protocol HouseholdCartHost: AnyObject {
    var account: OneCartAccount? { get }
    var activeFamilySpace: FamilySpace? { get }
    var familySpaces: [FamilySpace] { get }
    var access: FamilyAccess? { get }
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
            if needsSharedCartConsolidation(for: account) {
                CartSyncLog.action.info("ensureHousehold consolidateShared")
                do {
                    try await adoptSharedFamilyCartIfNeeded(for: account)
                } catch {
                    host.presentHouseholdError(error)
                }
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
            try await adoptSharedFamilyCartIfNeeded(for: account)
            guard !Task.isCancelled else { return }

            if host.activeFamilySpace != nil {
                if needsSharedCartConsolidation(for: account) {
                    try await adoptSharedFamilyCartIfNeeded(for: account)
                }
                await host.refreshFamilyMetadata(showErrors: false)
                host.scheduleInviteLinkPreparation()
                CartSyncLog.action.info(
                    "ensureHousehold done family=\(host.activeFamilySpace?.id?.uuidString ?? "-", privacy: .public)"
                )
                return
            }

            if host.familySpaces.isEmpty {
                CartSyncLog.action.info("ensureHousehold create empty")
                _ = try await repository.createFamilySpace(
                    name: host.householdDisplayName(for: account),
                    cachedForUserID: account.id,
                    isHouseholdDefault: true
                )
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
        try host.reloadHousehold(preferredFamilySpaceID: nil)
        if host.familySpaces.isEmpty {
            _ = try await repository.createFamilySpace(
                name: host.householdDisplayName(for: account),
                cachedForUserID: account.id,
                isHouseholdDefault: true
            )
            try host.reloadHousehold(preferredFamilySpaceID: nil)
        }
        try await adoptSharedFamilyCartIfNeeded(for: account)
    }

    func offerSharedCartJoinIfNeeded(for account: OneCartAccount) async throws {
        try await adoptSharedFamilyCartIfNeeded(for: account)
    }

    func reactivatePersonalCartIfNeeded(for account: OneCartAccount) async throws {
        guard let host else { return }
        try host.reloadHousehold(preferredFamilySpaceID: nil)
        let hasShared = host.familySpaces.contains { persistence.scope(for: $0) == .shared }
        guard !hasShared else { return }

        if let privateID = host.familySpaces.first(where: {
            persistence.scope(for: $0) == .private && $0.cachedForUserID == account.id
        })?.id {
            defaults.set(privateID.uuidString, forKey: host.activeFamilyKey(accountID: account.id))
            try host.reloadHousehold(preferredFamilySpaceID: privateID)
            return
        }

        let newID = try await repository.createFamilySpace(
            name: host.householdDisplayName(for: account),
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
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

    private func needsSharedCartConsolidation(for account: OneCartAccount) -> Bool {
        guard let host else { return false }
        let shared = host.familySpaces.filter { persistence.scope(for: $0) == .shared }
        guard !shared.isEmpty else { return false }
        if shared.count > 1 { return true }
        if let active = host.activeFamilySpace,
           persistence.scope(for: active) == .private
        {
            return true
        }
        return host.familySpaces.contains {
            persistence.scope(for: $0) == .private && $0.cachedForUserID == account.id
        }
    }

    private func adoptSharedFamilyCartIfNeeded(for account: OneCartAccount) async throws {
        guard let host else { return }
        try host.reloadHousehold(preferredFamilySpaceID: nil)

        guard let sharedFamily = host.familySpaces.first(where: {
            persistence.scope(for: $0) == .shared
        }), let sharedID = sharedFamily.id else {
            return
        }

        var privateCleanups: [(id: UUID, isEmpty: Bool)] = []
        var staleSharedIDs: [UUID] = []
        for space in host.familySpaces {
            guard let spaceID = space.id,
                  let scope = persistence.scope(for: space)
            else { continue }
            switch scope {
            case .private:
                guard space.cachedForUserID == account.id else { continue }
                privateCleanups.append(
                    (spaceID, FamilyCartMerge.summary(for: space).isEmpty)
                )
            case .shared:
                if spaceID != sharedID {
                    staleSharedIDs.append(spaceID)
                }
            }
        }

        defaults.set(
            sharedID.uuidString,
            forKey: host.activeFamilyKey(accountID: account.id)
        )
        try host.reloadHousehold(preferredFamilySpaceID: sharedID)

        for staleID in staleSharedIDs {
            do {
                try await repository.archiveFamilySpace(id: staleID)
                CartSyncLog.cart.info(
                    "adoptShared archived stale shared id=\(staleID.uuidString, privacy: .public)"
                )
            } catch {
                CartSyncLog.cart.error(
                    "adoptShared stale shared archive failed id=\(staleID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }

        for cleanup in privateCleanups {
            do {
                if cleanup.isEmpty {
                    continue
                }
                try await repository.mergeFamilyContent(
                    from: cleanup.id,
                    into: sharedID,
                    archiveSource: false
                )
            } catch {
                CartSyncLog.cart.error(
                    "adoptShared private cleanup failed id=\(cleanup.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                CartSyncLog.action.error(
                    "adoptShared privateCleanupFail error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }

        try host.reloadHousehold(preferredFamilySpaceID: sharedID)
        await host.refreshFamilyMetadata(showErrors: false)
    }
}
