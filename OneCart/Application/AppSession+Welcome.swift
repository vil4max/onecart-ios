import AuthenticationServices
import Foundation

extension AppSession {
    func start() async {
        guard !started else { return }
        started = true
        await bootstrapSession()
    }

    func retryStartup() async {
        await retryWelcome()
    }

    func ensureHouseholdCartIfNeeded() async {
        await household.ensureHouseholdCartIfNeeded()
    }

    func retryHouseholdCartBootstrap() async {
        await household.retryHouseholdCartBootstrap()
    }

    func retryWelcome() async {
        let previousPhase = welcomePhase
        await bootstrapper.retry(previousPhase: previousPhase)
    }

    func reportWelcomeFailure(_ message: String) {
        needsWelcome = true
        welcomePhase = .failed(message)
        isReady = true
    }

    func dismissWelcomeSignInAttempt() {
        needsWelcome = true
        welcomePhase = .signIn
        isReady = true
    }

    func completeAppleSignIn(authorization: ASAuthorization) async {
        needsWelcome = true
        welcomePhase = .connecting
        isReady = true
        isBusy = true
        defer { isBusy = false }
        do {
            let credential = try appleSignIn.makeCredential(from: authorization)
            appleSignIn.save(credential)
            if let providedName = credential.providedDisplayName {
                preferences.participantDisplayName = providedName
            } else if ParticipantDisplayName.isPlaceholder(preferences.participantDisplayName) {
                preferences.participantDisplayName = ""
            }
            await bootstrapper.prepare(appleCredential: credential)
        } catch {
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
        if let account {
            defaults.removeObject(forKey: activeFamilyKey(accountID: account.id))
        }
        appleSignIn.clearCredential()
        clearAccountData()
        account = nil
        alertMessage = nil
        needsWelcome = true
        welcomePhase = .signIn
        isReady = true
        started = true
    }

    private func bootstrapSession() async {
        await bootstrapper.start()
    }

    func createFamilyInviteLink() async throws -> FamilyInviteLink {
        guard let family = activeFamilySpace else {
            CartSyncLog.action.error("shareInvite denied noFamily")
            throw InviteLinkError.notOwner
        }
        return try await invitePreparer.createInviteLink(
            family: family,
            isOnline: online,
            fetch: { [shareOrchestrator] in
                try await shareOrchestrator.createInviteLink(for: family)
            }
        )
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
                return try await shareOrchestrator.createInviteLink(for: family)
            }
        )
    }

    func clearPreparedInviteLink() {
        invitePreparer.clear()
    }

    func presentAlert(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        alertMessage = trimmed
    }

    func dismissAlert() {
        alertMessage = nil
    }

    func bootstrapTestingSession(account: OneCartAccount) throws {
        self.account = account
        try reload()
    }

    func offerSharedCartJoinIfNeededForTesting() async throws {
        guard let account else { return }
        try await offerSharedCartJoinIfNeeded(for: account)
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
        "onecart.active-family-space-id.\(accountID.uuidString)"
    }

    func show(_ error: Error) {
        let message = userFacingMessage(for: error)
        if CloudKitUserFacingError.isProductionSchemaFailure(error) {
            presentProductionSchemaAlertIfNeeded(message)
            return
        }
        presentAlert(message)
    }

    func presentProductionSchemaAlertIfNeeded(_ message: String) {
        guard !didPresentProductionSchemaAlert else { return }
        didPresentProductionSchemaAlert = true
        presentAlert(message)
    }

    func userFacingMessage(for error: Error) -> String {
        if error is OneCartCloudKitError {
            return CloudKitUserFacingError.message(for: error)
        }
        if CloudKitUserFacingError.isNetworkError(error) {
            return String(localized: "sync.network_deferred")
        }
        if PersistenceController.isUserFacingCoreDataFailure(error) {
            return String(localized: "welcome.core_data_failed")
        }
        return CloudKitUserFacingError.message(for: error)
    }

    private func isNetworkError(_ error: Error) -> Bool {
        CloudKitUserFacingError.isNetworkError(error)
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
