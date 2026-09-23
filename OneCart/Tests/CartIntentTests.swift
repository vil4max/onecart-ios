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

    func test_REQ_SIRI_010_splitsOnStandaloneAndWordsInThreeLanguages() {
        XCTAssertEqual(CartIntentNames.split("молоко и хлеб"), ["молоко", "хлеб"])
        XCTAssertEqual(CartIntentNames.split("молоко І хліб, сир"), ["молоко", "хліб", "сир"])
        XCTAssertEqual(CartIntentNames.split("Milk AND bread and eggs"), ["Milk", "bread", "eggs"])
        XCTAssertEqual(CartIntentNames.split("Сливки и"), ["Сливки"])
        // The letters inside a word never split it.
        XCTAssertEqual(CartIntentNames.split("Иван-чай, икра"), ["Иван-чай", "икра"])
        XCTAssertEqual(CartIntentNames.split("Band-aid; Brandy"), ["Band-aid", "Brandy"])
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

    func test_REQ_SIRI_010_aFailedNameIsReportedAndTheRestStillGoIn() async throws {
        let result = try await CartIntentAddResult.adding(["Milk", "Bread", "Eggs", "Salt"]) { name in
            switch name {
            case "Bread": .failed
            case "Salt": .alreadyOnCart
            default: .added
            }
        }

        XCTAssertEqual(result.added, ["Milk", "Eggs"])
        XCTAssertEqual(result.alreadyOnCart, ["Salt"])
        XCTAssertEqual(result.failed, ["Bread"])
        XCTAssertEqual(
            spoken(CartIntentSpeech.addResult(result)),
            "Added to the cart: Milk and Eggs. Already on the cart: Salt. Couldn't add: Bread."
        )
    }

    func test_REQ_SIRI_010_aFailedAddQueuesNoAlertInTheApp() async throws {
        let fixture = try await makeFixture()
        // The list goes away underneath the session, so the save itself fails.
        let context = fixture.session.persistence.container.newBackgroundContext()
        let listID = fixture.listID
        try await context.perform {
            let list = try XCTUnwrap(FamilySpaceRepository.fetchList(id: listID, in: context))
            list.deletedAt = Date()
            try context.save()
        }

        do {
            _ = try await fixture.session.addItemsFromIntent("Milk")
            XCTFail("A save that did not land must be reported")
        } catch {
            XCTAssertEqual(error as? CartIntentError, .failed)
        }
        XCTAssertNil(fixture.session.userAlert, "Siri's failure must not surface later as an app alert")
    }

    func test_REQ_SIRI_010_speaksWhatWasAddedAndWhatWasAlreadyThere() {
        XCTAssertEqual(
            spoken(CartIntentSpeech.addResult(CartIntentAddResult(added: ["Milk"], alreadyOnCart: ["Bread"]))),
            "Added to the cart: Milk. Already on the cart: Bread."
        )
    }

    // MARK: - REQ-SIRI-020 remaining

    func test_REQ_SIRI_020_readsTheLinesStillToBuy() async throws {
        let fixture = try await makeFixture()
        _ = try await fixture.session.addItemsFromIntent("Молоко")

        let remaining = try await fixture.session.remainingItemsForIntent()

        XCTAssertEqual(remaining.totalCount, 2)
        XCTAssertEqual(remaining.names, ["Молоко", "Хлеб"])
        XCTAssertEqual(fixture.session.products(inListID: fixture.listID).count, 2)
    }

    func test_REQ_SIRI_020_readsInTheOrderTheCartScreenShows() async throws {
        let fixture = try await makeFixture()
        let repository = FamilySpaceRepository(
            persistence: fixture.session.persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        // Added in this order, so the newest-first fetch reads "Tea, Cheese, Хлеб".
        for (name, category) in [("Cheese", ProductCategory.dairyEggs), ("Tea", .hotDrinks)] {
            _ = try await repository.addProduct(
                to: fixture.listID,
                draft: ProductDraft(
                    name: name, quantity: 1, unit: .piece, category: category, estimatedPrice: 0, note: ""
                )
            )
        }
        try fixture.session.reload()

        let remaining = try await fixture.session.remainingItemsForIntent()

        // The cart screen groups to-buy lines by category: dairy, hot drinks, then other.
        XCTAssertEqual(remaining.names, ["Cheese", "Tea", "Хлеб"])
    }

    func test_REQ_SIRI_020_speaksAShortListOrTheCartState() {
        XCTAssertEqual(
            spoken(CartIntentSpeech.remaining(CartIntentRemaining(totalCount: 0, names: []))),
            "Cart is empty"
        )
        XCTAssertEqual(
            spoken(CartIntentSpeech.remaining(CartIntentRemaining(totalCount: 2, names: []))),
            "All purchased!"
        )
        XCTAssertEqual(spoken(remainingSpeech(count: 1)), "1 item left to buy: A.")
        XCTAssertEqual(spoken(remainingSpeech(count: 7)), "7 items left to buy: A, B, C, D, and E. And 2 more.")
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
