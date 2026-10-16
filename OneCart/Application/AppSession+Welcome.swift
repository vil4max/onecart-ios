import AuthenticationServices
import Foundation

extension AppSession {
    /// Runs the app's startup once. `retryingFailure` lets a background request (Siri) run it
    /// again after a start that ended on the Welcome failure. That retry only loads the stores
    /// again: the store wipe stays with the Welcome Retry the user taps.
    func start(retryingFailure: Bool = false) async {
        if let startupTask {
            await startupTask.value
            return
        }
        guard !started || (retryingFailure && startFailed) else { return }
        started = true
        let task = Task { @MainActor in
            await bootstrapSession()
            await drainWidgetPendingToggles()
        }
        startupTask = task
        await task.value
        startupTask = nil
    }

    /// The last start ended on the Welcome failure rather than on sign-in or a ready session.
    var startFailed: Bool {
        guard startupTask == nil, account == nil, case .failed = welcomePhase else { return false }
        return true
    }

    func ensureHouseholdCartIfNeeded() async {
        if case let .failed(error) = await household.ensureHouseholdCartIfNeeded() {
            show(error)
        }
    }

    func retryHouseholdCartBootstrap() async {
        if case let .failed(error) = await household.retryHouseholdCartBootstrap() {
            show(error)
        }
    }

    func reportWelcomeFailure(_ message: String) {
        bootstrapper.disarmStoreWipe()
        showWelcome(.failed(message))
    }

    func dismissWelcomeSignInAttempt() {
        showWelcome(.signIn)
    }

    /// Welcome is on screen in `phase`, and the root stops showing the loading state.
    func showWelcome(_ phase: WelcomePhase) {
        needsWelcome = true
        welcomePhase = phase
        isReady = true
    }

    /// The session is signed in and ready; Welcome goes away.
    func finishWelcome() {
        needsWelcome = false
        welcomePhase = .signIn
        isReady = true
    }

    func completeAppleSignIn(credential: AppleSignInCredential) async {
        showWelcome(.connecting)
        do {
            // The busy operation ends before reconciliation: the coordinator skips
            // reconciling while the session reports busy.
            beginBusyOperation()
            defer { endBusyOperation() }
            appleSignIn.save(credential)
            if let providedName = credential.providedDisplayName {
                preferences.participantDisplayName = providedName
            } else if ParticipantDisplayName.isPlaceholder(preferences.participantDisplayName) {
                preferences.participantDisplayName = ""
            }
            await prepareSession(appleCredential: credential)
        }
        if let account {
            try? await household.reconcileProvisionalPersonalCartIfNeeded(for: account)
        }
    }

    func completeAppleSignIn(authorization: ASAuthorization) async {
        do {
            let credential = try appleSignIn.makeCredential(from: authorization)
            await completeAppleSignIn(credential: credential)
        } catch {
            bootstrapper.disarmStoreWipe()
            needsWelcome = true
            if let localized = error as? LocalizedError,
                let description = localized.errorDescription?.nilIfBlank
            {
                welcomePhase = .failed(description)
            } else {
                welcomePhase = .failed(String(localized: "welcome.sign_in_failed"))
            }
        }
    }

    func signOut() {
        do {
            try widgetStore.clear()
        } catch {
            show(error)
            return
        }
        widgetSync.cancelDrain()
        if let account {
            defaults.removeObject(forKey: activeFamilyKey(accountID: account.id))
        }
        activityNotifier.clearSnapshots()
        forgetCurrentUserRecordName()
        appleSignIn.clearCredential()
        clearAccountData()
        account = nil
        dismissAlert()
        showWelcome(.signIn)
        started = true
    }

    func scheduleInviteLinkPreparation(delayNanoseconds: UInt64) {
        invitePreparer.schedulePreparation(
            delayNanoseconds: delayNanoseconds,
            isOnline: { [weak self] in self?.online == true },
            family: { [weak self] in self?.activeFamilySpace },
            familyStillActive: { [weak self] familyID in
                self?.activeFamilySpace?.id == familyID
            },
            fetch: { [weak self] family in
                guard let self else { throw InviteLinkError.offline }
                return try await shareOrchestrator.existingInviteLink(for: family)
            }
        )
    }

    /// After a cart change the invite link of the active cart is prepared again, shortly after.
    func scheduleInviteLinkPreparation() {
        scheduleInviteLinkPreparation(delayNanoseconds: 1_500_000_000)
    }

    func clearPreparedInviteLink() {
        invitePreparer.clear()
    }

    func dismissSharedCartRemovedMessage() {
        household.dismissSharedCartRemovedMessage()
    }

    func finishFamilyCartSetup(for account: OneCartAccount) async throws {
        try await household.finishFamilyCartSetup(for: account)
    }

    func offerSharedCartJoinIfNeeded(for account: OneCartAccount) async throws {
        try await household.offerSharedCartJoinIfNeeded(for: account)
    }

    func installCloudObservers() {
        cloudSync.installCloudObservers()
    }

    func installConnectivityMonitor() {
        cloudSync.installConnectivityMonitor()
    }

    func activeFamilyKey(accountID: UUID) -> String {
        Self.activeFamilyKey(accountID: accountID)
    }

    nonisolated static func activeFamilyKey(accountID: UUID) -> String {
        "onecart.active-family-space-id.\(accountID.uuidString)"
    }

    func userFacingMessage(for error: Error) -> String {
        if error is OneCartCloudKitError {
            return CloudKitUserFacingError.message(for: error)
        }
        if CloudKitUserFacingError.isProductionSchemaFailure(error) {
            return CloudKitUserFacingError.productionSchemaMissing
        }
        if CloudKitUserFacingError.isNetworkError(error) {
            return String(localized: "sync.network_deferred")
        }
        if PersistenceController.isUserFacingCoreDataFailure(error) {
            return String(localized: "welcome.core_data_failed")
        }
        return CloudKitUserFacingError.message(for: error)
    }
}
