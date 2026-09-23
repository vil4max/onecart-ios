import Foundation

@MainActor
protocol SessionBootstrapHost: AnyObject {
    var isOnline: Bool { get }
    var preferences: DevicePreferences { get }

    func notifyBootstrapObjectWillChange()
    func installConnectivityMonitor()
    func installCloudObservers()
    func acceptPendingCloudKitShares() async
    func finishFamilyCartSetup(for account: OneCartAccount) async throws
    func refreshFamilyMetadata(showErrors: Bool) async
    func scheduleInviteLinkPreparation(delayNanoseconds: UInt64)
    func reloadAfterBootstrap() throws
    func userFacingMessage(for error: Error) -> String
    func applyBootstrapAccount(_ account: OneCartAccount)
    func clearBootstrapAccount()
    func applyBootstrapSyncState(_ state: OneCartSyncState)
    func applyWelcomeSignIn()
    func applyWelcomeConnecting()
    func applyWelcomeFailed(_ message: String)
    func applyWelcomeReady(needsWelcome: Bool)
    func clearStoredAppleCredential()
    /// Launch ends without a signed-in account: a trip left running belongs to nobody.
    func endShoppingTripWithoutAccount()
}

@MainActor
final class SessionBootstrapper {
    private let persistence: PersistenceController
    private let repository: FamilySpaceRepository
    private let backend: CloudKitBackendService
    private let appleSignIn: AppleSignInAuthenticating
    private weak var host: SessionBootstrapHost?

    init(
        persistence: PersistenceController,
        repository: FamilySpaceRepository,
        backend: CloudKitBackendService,
        appleSignIn: AppleSignInAuthenticating
    ) {
        self.persistence = persistence
        self.repository = repository
        self.backend = backend
        self.appleSignIn = appleSignIn
    }

    func bind(host: SessionBootstrapHost) {
        self.host = host
    }

    /// Cause of the most recent welcome failure reported by this bootstrapper.
    private(set) var lastFailureCause: WelcomeFailureCause = .other

    nonisolated static func shouldHardResetStores(
        for previousPhase: WelcomePhase,
        cause: WelcomeFailureCause
    ) -> Bool {
        guard case .failed = previousPhase else { return false }
        return cause == .storeLoad
    }

    nonisolated static func failureCause(forLoadError error: Error) -> WelcomeFailureCause {
        PersistenceController.isUserFacingCoreDataFailure(error) ? .storeLoad : .other
    }

    func willHardResetStores(for previousPhase: WelcomePhase) -> Bool {
        Self.shouldHardResetStores(for: previousPhase, cause: lastFailureCause)
    }

    /// Failures reported outside `prepare` (for example Sign in with Apple) never arm the wipe.
    func disarmStoreWipe() {
        lastFailureCause = .other
    }

    func start() async {
        guard let host else { return }
        if let credential = appleSignIn.storedCredential() {
            let state = await appleSignIn.credentialState(for: credential.userID)
            switch state {
            case .authorized, .unknown:
                host.applyWelcomeConnecting()
                await prepare(appleCredential: credential)
                return
            case .revoked, .notFound:
                #if targetEnvironment(simulator)
                    host.applyWelcomeConnecting()
                    await prepare(appleCredential: credential)
                    return
                #else
                    host.clearStoredAppleCredential()
                #endif
            }
        }

        // No credential, or a revoked or unknown one: nobody is signed in (REQ-WIDGET-060).
        host.endShoppingTripWithoutAccount()
        host.applyWelcomeSignIn()
    }

    func retry(previousPhase: WelcomePhase) async {
        guard let host else { return }
        guard let credential = appleSignIn.storedCredential() else {
            host.applyWelcomeSignIn()
            return
        }
        host.applyWelcomeConnecting()

        // The armed cause is consumed here so one load failure authorizes at most one wipe.
        let shouldHardReset = willHardResetStores(for: previousPhase)
        lastFailureCause = .other
        if shouldHardReset {
            do {
                _ = try? persistence.copyStoreFilesForDiagnostics()
                try persistence.hardResetPersistentStores()
                host.notifyBootstrapObjectWillChange()
            } catch {
                host.applyWelcomeFailed(host.userFacingMessage(for: error))
                return
            }
        }

        await prepare(appleCredential: credential)
    }

    func prepare(appleCredential: AppleSignInCredential) async {
        guard let host else { return }
        lastFailureCause = .other
        do {
            try await persistence.load()
        } catch {
            // Only a failure of `load()` itself may arm the wipe; later steps can fail with
            // Cocoa save or merge errors while the stores still hold unexported edits.
            lastFailureCause = Self.failureCause(forLoadError: error)
            host.clearBootstrapAccount()
            host.applyWelcomeFailed(host.userFacingMessage(for: error))
            return
        }
        do {
            host.notifyBootstrapObjectWillChange()
            try await repository.deduplicateStableIDs()
            _ = try await repository.deduplicateProductsByName()
            host.preferences.reloadFromDefaults()

            if let appleName = appleCredential.providedDisplayName {
                host.preferences.participantDisplayName = appleName
            } else if ParticipantDisplayName.isPlaceholder(host.preferences.participantDisplayName) {
                host.preferences.participantDisplayName = ""
            }

            let preferredName = ParticipantDisplayName.resolved(
                preferences: host.preferences,
                account: nil
            )
            if !persistence.accountDeletionRecoveryRequired {
                host.installConnectivityMonitor()
                host.installCloudObservers()
            }

            let restoredAccount: OneCartAccount = if persistence.accountDeletionRecoveryRequired {
                OneCartAccount(
                    id: appleCredential.accountID,
                    displayName: preferredName ?? String(localized: "common.default_user")
                )
            } else {
                try await backend.restoredAccount(
                    appleUserID: appleCredential.userID,
                    displayName: preferredName
                )
            }
            let account = OneCartAccount(
                id: restoredAccount.id,
                displayName: ParticipantDisplayName.displayOrPlaceholder(
                    preferences: host.preferences,
                    account: restoredAccount
                ),
                avatarURL: restoredAccount.avatarURL,
                bannerURL: restoredAccount.bannerURL
            )
            host.applyBootstrapAccount(account)
            try await repository.claimUnassignedFamilySpaces(for: restoredAccount.id)
            try host.reloadAfterBootstrap()
            if persistence.accountDeletionRecoveryRequired {
                host.applyBootstrapSyncState(.failed)
                host.applyWelcomeReady(needsWelcome: false)
                return
            }
            await host.acceptPendingCloudKitShares()
            try await host.finishFamilyCartSetup(for: restoredAccount)
            host.applyBootstrapSyncState(host.isOnline ? .synchronized : .offline)
            await host.refreshFamilyMetadata(showErrors: false)
            host.applyWelcomeReady(needsWelcome: false)
            host.scheduleInviteLinkPreparation(delayNanoseconds: 2_000_000_000)
        } catch {
            host.clearBootstrapAccount()
            host.applyWelcomeFailed(host.userFacingMessage(for: error))
        }
    }
}
