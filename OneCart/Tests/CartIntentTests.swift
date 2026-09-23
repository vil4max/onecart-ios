import AuthenticationServices
import Foundation
@testable import OneCart
import XCTest

/// Siri and Shortcuts: what the intents do to the cart and what Siri says back.
@MainActor
final class CartIntentTests: XCTestCase {
    private struct Fixture {
        let session: AppSession
        let backend: FakeShoppingTripBackend
        let listID: UUID
    }

    private func makeFixture() async throws -> Fixture {
        let (persistence, repository) = try await makeInMemoryRepository()
        let account = OneCartAccount(id: OneCartStableID.uuid(for: "onecart.in-memory-user"), displayName: "Alex")
        let familyID = try await repository.createFamilySpace(
            name: "Personal", cachedForUserID: account.id, isHouseholdDefault: true
        )
        let listID = try XCTUnwrap(repository.fetchFamilySpace(id: familyID)?.activeLists.first?.id)
        _ = try await repository.addProduct(to: listID, draft: productDraft(name: "Хлеб"))
        let backend = FakeShoppingTripBackend()
        let session = try makeTestSession(persistence: persistence, shoppingTripBackend: backend)
        try session.bootstrapTestingSession(account: account)
        session.started = true
        session.needsWelcome = false
        return Fixture(session: session, backend: backend, listID: listID)
    }

    // MARK: - REQ-SIRI-010 add

    func test_REQ_SIRI_010_splitsSeveralNamesAndDropsBlanksAndRepeats() {
        XCTAssertEqual(CartIntentNames.split("Milk, bread;\n  milk ,, Eggs "), ["Milk", "bread", "Eggs"])
        XCTAssertEqual(CartIntentNames.split(" ,\n "), [])
    }

    func test_REQ_SIRI_010_addsNameOnlyLinesAndKeepsExistingOnes() async throws {
        let fixture = try await makeFixture()

        let result = try await fixture.session.addItemsFromIntent("Молоко, хлеб")

        XCTAssertEqual(result.added, ["Молоко"])
        XCTAssertEqual(result.alreadyOnCart, ["хлеб"])
        let lines = fixture.session.products(inListID: fixture.listID)
        XCTAssertEqual(lines.count, 2)
        let milk = try XCTUnwrap(lines.first { $0.displayName == "Молоко" })
        XCTAssertEqual(milk.estimatedPriceValue, 0)
        XCTAssertFalse(milk.isPurchasedValue)
    }

    func test_REQ_SIRI_010_refusesAnEmptyRequestOrASignedOutSession() async throws {
        let fixture = try await makeFixture()
        do {
            _ = try await fixture.session.addItemsFromIntent(" , ")
            XCTFail("A blank request must not reach the cart")
        } catch {
            XCTAssertEqual(error as? CartIntentError, .emptyName)
        }

        fixture.session.signOut()
        do {
            _ = try await fixture.session.addItemsFromIntent("Milk")
            XCTFail("Siri must not add to a signed-out session")
        } catch {
            XCTAssertEqual(error as? CartIntentError, .signedOut)
        }
    }

    func test_REQ_SIRI_010_waitsForAHouseholdCartStillBeingSetUp() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let session = try makeTestSession(persistence: persistence)
        try session.bootstrapTestingSession(account: OneCartAccount(id: UUID(), displayName: "Alex"))
        session.started = true
        session.needsWelcome = false
        XCTAssertNil(session.activeFamilySpace)

        // The cart screen started the setup; Siri arrives while it is still running.
        let screenSetup = Task { await session.ensureHouseholdCartIfNeeded() }
        for _ in 0 ..< 100 where !session.isEnsuringHouseholdCart {
            await Task.yield()
        }
        XCTAssertTrue(session.isEnsuringHouseholdCart, "Precondition: the setup is running")

        let result = try await session.addItemsFromIntent("Milk")

        XCTAssertEqual(result.added, ["Milk"])
        await screenSetup.value
    }

    func test_REQ_SIRI_010_aLocalFailureIsNotBlamedOnICloud() {
        XCTAssertNotEqual(CartIntentError.failed.errorDescription, String(localized: "sync.generic_failure"))
        XCTAssertEqual(CartIntentError.failed.errorDescription, String(localized: "intent.error.failed"))
    }

    func test_REQ_SIRI_010_speaksWhatWasAddedAndWhatWasAlreadyThere() {
        let spoken = CartIntentSpeech.addResult(CartIntentAddResult(added: ["Milk"], alreadyOnCart: ["Bread"]))
        XCTAssertEqual(
            spoken,
            String(localized: "intent.add_item.added \("Milk")") + " "
                + String(localized: "intent.add_item.already \("Bread")")
        )
    }

    // MARK: - REQ-SIRI-020 remaining

    func test_REQ_SIRI_020_readsTheLinesStillToBuy() async throws {
        let fixture = try await makeFixture()
        _ = try await fixture.session.addItemsFromIntent("Молоко")

        let remaining = try await fixture.session.remainingItemsForIntent()

        XCTAssertEqual(remaining.totalCount, 2)
        XCTAssertEqual(Set(remaining.names), ["Молоко", "Хлеб"])
        XCTAssertEqual(fixture.session.products(inListID: fixture.listID).count, 2)
    }

    func test_REQ_SIRI_020_speaksAShortListOrTheCartState() {
        XCTAssertEqual(
            CartIntentSpeech.remaining(CartIntentRemaining(totalCount: 0, names: [])),
            String(localized: "widget.empty")
        )
        XCTAssertEqual(
            CartIntentSpeech.remaining(CartIntentRemaining(totalCount: 2, names: [])),
            String(localized: "widget.all_purchased")
        )
        let names = ["A", "B", "C", "D", "E", "F", "G"]
        let spoken = CartIntentSpeech.remaining(CartIntentRemaining(totalCount: 9, names: names))
        let listed = ["A", "B", "C", "D", "E"].formatted(.list(type: .and))
        XCTAssertEqual(
            spoken,
            String(localized: "intent.remaining.list \(7) \(listed)") + " " + String(localized: "trip.more \(2)")
        )
    }

    // MARK: - REQ-SIRI-030 shopping trip

    func test_REQ_SIRI_030_startsTheShoppingTrip() async throws {
        let fixture = try await makeFixture()

        try await fixture.session.startShoppingTripFromIntent()

        XCTAssertTrue(fixture.session.isShoppingTripActive)
        XCTAssertEqual(fixture.backend.requested.count, 1)
        XCTAssertEqual(fixture.backend.requested.first?.state.nextItems.map(\.name), ["Хлеб"])
    }

    // MARK: - REQ-SIRI-040 background startup

    /// A session that runs the real startup path against a store directory the test controls.
    private func makeStartingSession(
        credential: AppleSignInCredential?,
        appleSignIn: AppleSignInAuthenticating? = nil,
        backend: FakeShoppingTripBackend = FakeShoppingTripBackend()
    ) throws -> (AppSession, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OneCartSiriStart-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let persistence = PersistenceController(inMemory: false, storeDirectoryURL: directory, cloudKitEnabled: false)
        let session = try makeTestSession(
            persistence: persistence,
            appleSignIn: appleSignIn ?? InMemoryAppleSignIn(credential: credential),
            shoppingTripBackend: backend
        )
        return (session, directory)
    }

    private let siriUser = AppleSignInCredential(userID: "siri-user", email: nil, givenName: "Alex", familyName: nil)

    func test_REQ_SIRI_040_aFailedStartIsReportedAndRetriedOnTheNextRequest() async throws {
        let (session, directory) = try makeStartingSession(credential: siriUser)
        // A directory occupying the sqlite path makes the store load fail, as in FragileStoreLoadTests.
        let privateURL = directory.appendingPathComponent("OneCart-private.sqlite")
        try FileManager.default.createDirectory(at: privateURL, withIntermediateDirectories: true)

        do {
            _ = try await session.addItemsFromIntent("Milk")
            XCTFail("A failed start must not reach the cart")
        } catch {
            XCTAssertEqual(error as? CartIntentError, .unavailable)
        }
        XCTAssertNotEqual(
            CartIntentError.unavailable.errorDescription,
            CartIntentError.signedOut.errorDescription,
            "A signed-in user must not be told to sign in"
        )
        // Siri never performs the store wipe; only the Welcome Retry may.
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: privateURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)

        try FileManager.default.removeItem(at: privateURL)
        let result = try await session.addItemsFromIntent("Milk")

        XCTAssertEqual(result.added, ["Milk"])
        XCTAssertNotNil(session.account)
    }

    func test_REQ_SIRI_040_aStartWithoutAnAccountIsReportedAsSignedOut() async throws {
        let (session, _) = try makeStartingSession(credential: nil)

        do {
            _ = try await session.remainingItemsForIntent()
            XCTFail("Siri must not read a signed-out session")
        } catch {
            XCTAssertEqual(error as? CartIntentError, .signedOut)
        }
    }

    func test_REQ_SIRI_040_stopsWaitingForAStartupThatTakesTooLong() async throws {
        let signIn = GatedAppleSignIn(credential: siriUser)
        let (session, _) = try makeStartingSession(credential: nil, appleSignIn: signIn)
        let clock = IntentTestClock()
        let reported = expectation(description: "Siri reports the app unavailable")

        let request = Task { @MainActor in
            do {
                _ = try await session.addItemsFromIntent("Milk", deadline: clock.deadline())
                XCTFail("A request must not wait past the limit")
            } catch {
                XCTAssertEqual(error as? CartIntentError, .unavailable)
            }
            reported.fulfill()
        }
        await signIn.waitUntilAsked()
        clock.advance(by: CartIntentDeadline.startupLimit)
        await fulfillment(of: [reported], timeout: 5)

        // Startup was left running and finishes once the slow step answers.
        signIn.release()
        await request.value
        await session.start()
        XCTAssertNotNil(session.account)
        XCTAssertFalse(session.products.contains { $0.displayName == "Milk" }, "Nothing is added after Siri gave up")
    }

    func test_REQ_SIRI_040_aTripThatWouldStartAfterTheLimitDoesNotStart() async throws {
        let signIn = GatedAppleSignIn(credential: siriUser)
        let backend = FakeShoppingTripBackend()
        let (session, _) = try makeStartingSession(credential: nil, appleSignIn: signIn, backend: backend)
        let clock = IntentTestClock()

        let request = Task { @MainActor in
            try await session.startShoppingTripFromIntent(deadline: clock.deadline())
        }
        await signIn.waitUntilAsked()
        // Time passes while the timer has not fired yet: startup then finishes first.
        clock.moveNowWithoutFiring(by: .seconds(11))
        signIn.release()
        do {
            try await request.value
            XCTFail("A trip must not start after the limit")
        } catch {
            XCTAssertEqual(error as? CartIntentError, .unavailable)
        }
        XCTAssertTrue(backend.requested.isEmpty)

        _ = try await session.addItemsFromIntent("Milk", deadline: IntentTestClock().deadline())
        try await session.startShoppingTripFromIntent(deadline: IntentTestClock().deadline())
        XCTAssertEqual(backend.requested.count, 1, "Within the limit the same request starts the trip")
    }

    // MARK: - REQ-SIRI-040 phrases

    func test_REQ_SIRI_040_everyPhraseIsTranslatedAndNamesTheApp() throws {
        XCTAssertEqual(OneCartShortcuts.appShortcuts.count, 3)
        let phrases = [
            "Add to ${applicationName}",
            "Add an item to ${applicationName}",
            "Add to my ${applicationName} cart",
            "What's left in ${applicationName}",
            "What to buy in ${applicationName}",
            "Start shopping in ${applicationName}",
            "I'm shopping with ${applicationName}",
        ]
        for language in ["ru", "uk"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for phrase in phrases {
                let translated = bundle.localizedString(forKey: phrase, value: "MISSING", table: "AppShortcuts")
                XCTAssertNotEqual(translated, "MISSING", "\(language): \(phrase)")
                XCTAssertNotEqual(translated, phrase, "\(language): \(phrase)")
                XCTAssertTrue(translated.contains("${applicationName}"), "\(language): \(phrase)")
            }
        }
    }
}

/// Holds startup at the credential check until the test releases it.
private final class GatedAppleSignIn: AppleSignInAuthenticating, @unchecked Sendable {
    private let credential: AppleSignInCredential
    private let asked = AsyncStream<Void>.makeStream()
    private let gate = AsyncStream<Void>.makeStream()

    init(credential: AppleSignInCredential) {
        self.credential = credential
    }

    func storedCredential() -> AppleSignInCredential? {
        credential
    }

    func save(_: AppleSignInCredential) {}

    func clearCredential() {}

    func credentialState(for _: String) async -> AppleSignInCredentialState {
        asked.continuation.yield()
        for await _ in gate.stream {}
        return .authorized
    }

    func signIn() async throws -> AppleSignInCredential {
        throw AppleSignInError.failed
    }

    func makeCredential(from _: ASAuthorization) throws -> AppleSignInCredential {
        throw AppleSignInError.failed
    }

    func waitUntilAsked() async {
        var iterator = asked.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func release() {
        gate.continuation.finish()
    }
}

/// A manual clock for `CartIntentDeadline`: time moves only when the test says so.
@MainActor
private final class IntentTestClock {
    private let start = ContinuousClock.now
    private var elapsed: Duration = .zero
    private var sleepers: [(id: UUID, until: Duration, continuation: CheckedContinuation<Void, Never>)] = []

    func deadline(limit: Duration = CartIntentDeadline.startupLimit) -> CartIntentDeadline {
        CartIntentDeadline(
            end: start + limit,
            now: { self.start + self.elapsed },
            sleep: { duration in try await self.sleep(for: duration) }
        )
    }

    /// Moves time and fires every timer that is due.
    func advance(by duration: Duration) {
        elapsed += duration
        let due = sleepers.filter { $0.until <= elapsed }
        sleepers.removeAll { $0.until <= elapsed }
        due.forEach { $0.continuation.resume() }
    }

    /// Moves time without firing timers, as when work and the timer end in the same instant.
    func moveNowWithoutFiring(by duration: Duration) {
        elapsed += duration
    }

    /// Like `Task.sleep`, a cancelled sleep ends at once and throws.
    private func sleep(for duration: Duration) async throws {
        let id = UUID()
        let until = elapsed + duration
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                sleepers.append((id, until, continuation))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.wake(id) }
        }
        try Task.checkCancellation()
    }

    private func wake(_ id: UUID) {
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return }
        sleepers.remove(at: index).continuation.resume()
    }
}
