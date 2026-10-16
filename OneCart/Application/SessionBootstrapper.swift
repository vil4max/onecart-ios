import Foundation

struct SessionBootstrapDependencies {
    let persistence: PersistenceController
    let deduplicator: any CartDeduplicator
    let cloudSharing: any FamilyCloudSharing
    let appleSignIn: any AppleSignInAuthenticating
    let preferences: DevicePreferences
    let cartSync: CartSyncService
}

/// How loading the stores for a sign-in ended.
enum StoreLoadOutcome {
    /// The name the device or the Apple ID gives this user, if any.
    case loaded(preferredName: String?)
    case failed(Error)
}

/// The startup steps that touch the stores and the stored sign-in: which credential to restore,
/// the explicit store wipe a load failure arms, loading and deduplicating the stores, and the
/// account iCloud restores. Each step returns its outcome; the session runs them in order
/// (`AppSession+Bootstrap.swift`) and applies the result to its state.
@MainActor
final class SessionBootstrapper {
    private let dependencies: SessionBootstrapDependencies

    init(dependencies: SessionBootstrapDependencies) {
        self.dependencies = dependencies
    }

    private var persistence: PersistenceController {
        dependencies.persistence
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

    /// Failures reported outside `loadStores` (for example Sign in with Apple) never arm the wipe.
    func disarmStoreWipe() {
        lastFailureCause = .other
    }

    /// The stored sign-in to restore at launch; nil when nobody is signed in.
    func restorableCredential() async -> AppleSignInCredential? {
        let appleSignIn = dependencies.appleSignIn
        guard let credential = appleSignIn.storedCredential() else { return nil }
        switch await appleSignIn.credentialState(for: credential.userID) {
        case .authorized, .unknown:
            return credential
        case .revoked, .notFound:
            // Simulator builds keep the stored sign-in across launches (demo and UI checks)
            // even when the credential check reports it gone; a device signs out.
            #if targetEnvironment(simulator)
                return credential
            #else
                appleSignIn.clearCredential()
                return nil
            #endif
        }
    }

    /// Wipes the stores, after a diagnostics copy, when the failure Welcome shows came from a
    /// store load. The armed cause is consumed here so one load failure authorizes at most one
    /// wipe. Throws when the wipe failed.
    func resetStoresIfArmed(previousPhase: WelcomePhase) throws {
        let shouldHardReset = willHardResetStores(for: previousPhase)
        lastFailureCause = .other
        guard shouldHardReset else { return }
        _ = try? persistence.copyStoreFilesForDiagnostics()
        try persistence.hardResetPersistentStores()
        dependencies.cartSync.bumpRevisionAfterLocalChange()
    }

    /// Loads the stores, merges duplicates and settles the user's name from the Apple sign-in.
    func loadStores(appleCredential: AppleSignInCredential) async -> StoreLoadOutcome {
        lastFailureCause = .other
        do {
            try await persistence.load()
        } catch {
            // Only a failure of `load()` itself may arm the wipe; later steps can fail with
            // Cocoa save or merge errors while the stores still hold unexported edits.
            lastFailureCause = Self.failureCause(forLoadError: error)
            return .failed(error)
        }
        do {
            // The load reset the stores under the live fetch results; the revision is the
            // observable signal dependents (`ShoppingListView`) react to.
            dependencies.cartSync.bumpRevisionAfterLocalChange()
            try await dependencies.deduplicator.deduplicateStableIDs()
            _ = try await dependencies.deduplicator.deduplicateProductsByName()
        } catch {
            return .failed(error)
        }
        let preferences = dependencies.preferences
        preferences.reloadFromDefaults()
        if let appleName = appleCredential.providedDisplayName {
            preferences.participantDisplayName = appleName
        } else if ParticipantDisplayName.isPlaceholder(preferences.participantDisplayName) {
            preferences.participantDisplayName = ""
        }
        return .loaded(preferredName: ParticipantDisplayName.resolved(preferences: preferences, account: nil))
    }

    /// The account iCloud restores, or a local stand-in while an interrupted account deletion
    /// is recovered with CloudKit off.
    func restoreAccount(appleCredential: AppleSignInCredential, preferredName: String?) async throws -> OneCartAccount {
        if persistence.accountDeletionRecoveryRequired {
            return OneCartAccount(
                id: appleCredential.accountID,
                displayName: preferredName ?? String(localized: "common.default_user")
            )
        }
        return try await dependencies.cloudSharing.restoredAccount(
            appleUserID: appleCredential.userID,
            displayName: preferredName
        )
    }
}
