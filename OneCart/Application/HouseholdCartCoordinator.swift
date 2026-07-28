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
        guard host.activeFamilySpace == nil else {
            host.applyHouseholdCartBootstrapFailed(false)
            return
        }
        guard !host.isEnsuringHouseholdCart else {
            CartSyncLog.action.info("ensureHousehold skip alreadyRunning")
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
            if host.activeFamilySpace != nil {
                CartSyncLog.action.info("ensureHousehold done afterAccept")
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
            } else {
                CartSyncLog.action.info("ensureHousehold offerSharedJoin count=\(host.familySpaces.count)")
                try await adoptSharedFamilyCartIfNeeded(for: account)
                guard !Task.isCancelled else { return }
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

    func handleInviteeSharedCartGoneIfNeeded() async {
        guard let host, let account = host.account else { return }
        let hasShared = host.familySpaces.contains { persistence.scope(for: $0) == .shared }
        guard !hasShared, host.lastActiveFamilyWasShared || host.access?.isParticipant == true else { return }

        let privateFamily = host.familySpaces.first {
            persistence.scope(for: $0) == .private && $0.cachedForUserID == account.id
        }
        if let privateID = privateFamily?.id {
            defaults.set(privateID.uuidString, forKey: host.activeFamilyKey(accountID: account.id))
            try? host.reloadHousehold(preferredFamilySpaceID: privateID)
        } else if host.activeFamilySpace == nil {
            do {
                let newID = try await repository.createFamilySpace(
                    name: host.householdDisplayName(for: account),
                    cachedForUserID: account.id,
                    isHouseholdDefault: true
                )
                defaults.set(newID.uuidString, forKey: host.activeFamilyKey(accountID: account.id))
                try host.reloadHousehold(preferredFamilySpaceID: newID)
            } catch {
                host.presentHouseholdError(error)
                return
            }
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

        let privateFamilies = host.familySpaces.filter {
            persistence.scope(for: $0) == .private
                && $0.cachedForUserID == account.id
        }

        for privateFamily in privateFamilies {
            guard let privateID = privateFamily.id,
                  let scope = persistence.scope(for: privateFamily) else { continue }
            if FamilyCartMerge.isDeletableStarter(privateFamily, scope: scope) {
                try await repository.archiveFamilySpace(id: privateID)
                continue
            }
            try await repository.mergeFamilyContent(from: privateID, into: sharedID)
        }

        defaults.set(
            sharedID.uuidString,
            forKey: host.activeFamilyKey(accountID: account.id)
        )
        try host.reloadHousehold(preferredFamilySpaceID: sharedID)
    }
}
