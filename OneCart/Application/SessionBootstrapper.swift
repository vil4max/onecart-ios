import Foundation

@MainActor
protocol SessionBootstrapHost: AnyObject {
    var isOnline: Bool { get }
    var preferences: DevicePreferences { get }

    func notifyBootstrapObjectWillChange()
    func installConnectivityMonitor()
    func installCloudObservers()
    func reloadProfileMedia(for accountID: UUID)
    func acceptPendingCloudKitShares() async
    func finishFamilyCartSetup(for account: OneCartAccount) async throws
    func refreshFamilyMetadata(showErrors: Bool) async
    func scheduleInviteLinkPreparation(delayNanoseconds: UInt64)
    func reloadAfterBootstrap() throws
    func userFacingMessage(for error: Error) -> String
    func applyBootstrapAccount(_ account: OneCartAccount)
    func applyBootstrapSyncState(_ state: OneCartSyncState)
    func applyWelcomeSignIn()
    func applyWelcomeConnecting()
    func applyWelcomeFailed(_ message: String)
    func applyWelcomeReady(needsWelcome: Bool)
    func clearStoredAppleCredential()
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

    nonisolated static func shouldHardResetStores(for previousPhase: WelcomePhase) -> Bool {
        if case let .failed(message) = previousPhase,
           message == String(localized: "welcome.core_data_failed")
        {
            return true
        }
        return false
    }

    func start() async {
        guard let host else { return }
        if let credential = appleSignIn.storedCredential() {
            let state = await appleSignIn.credentialState(for: credential.userID)
            switch state {
            case .authorized, .unknown:
                host.applyWelcomeReady(needsWelcome: false)
                host.applyWelcomeConnecting()
                await prepare(appleCredential: credential)
                return
            case .revoked, .notFound:
                host.clearStoredAppleCredential()
            }
        }

        host.applyWelcomeSignIn()
    }

    func retry(previousPhase: WelcomePhase) async {
        guard let host else { return }
        guard let credential = appleSignIn.storedCredential() else {
            host.applyWelcomeSignIn()
            return
        }
        host.applyWelcomeConnecting()

        if Self.shouldHardResetStores(for: previousPhase) {
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
        do {
            try await persistence.load()
            host.notifyBootstrapObjectWillChange()
            try await repository.deduplicateStableIDs()
            host.preferences.reloadFromDefaults()

            let preferredName = appleCredential.providedDisplayName
                ?? host.preferences.participantDisplayName.nilIfBlank
                ?? appleCredential.displayName
            host.installConnectivityMonitor()
            host.installCloudObservers()

            let restoredAccount = try await backend.restoredAccount(
                appleUserID: appleCredential.userID,
                displayName: preferredName
            )
            host.applyBootstrapAccount(restoredAccount)
            if let appleName = appleCredential.providedDisplayName {
                host.preferences.participantDisplayName = appleName
            } else if host.preferences.participantDisplayName.nilIfBlank == nil {
                host.preferences.participantDisplayName = restoredAccount.displayName
            }
            host.reloadProfileMedia(for: restoredAccount.id)
            try await repository.claimUnassignedFamilySpaces(for: restoredAccount.id)
            try host.reloadAfterBootstrap()
            await host.acceptPendingCloudKitShares()
            try await host.finishFamilyCartSetup(for: restoredAccount)
            host.applyBootstrapSyncState(host.isOnline ? .synchronized : .offline)
            await host.refreshFamilyMetadata(showErrors: false)
            host.applyWelcomeReady(needsWelcome: false)
            host.scheduleInviteLinkPreparation(delayNanoseconds: 2_000_000_000)
        } catch {
            host.applyWelcomeFailed(host.userFacingMessage(for: error))
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
