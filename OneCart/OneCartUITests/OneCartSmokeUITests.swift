import XCTest

/// End-to-end smoke of the core path on a real app process. Every launch uses DEBUG demo
/// mode (no Sign in with Apple, no CloudKit) with a freshly seeded owner cart: the seed holds
/// four cart lines, two of them completed, and one History day of three purchases.
///
/// The app under a UI test does not see `XCTestConfigurationFilePath`: XCTest sets it in the
/// runner process only, so the app's unit-test short-circuits (skipped bootstrap, in-memory
/// store) stay off and demo seeding runs as in `just demo`. The History test finds no day if
/// that ever changes.
@MainActor
final class OneCartSmokeUITests: XCTestCase {
    private static let timeout: TimeInterval = 15

    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-oneCartDemoUI",
            "-oneCartDemoRole", "owner",
            "-oneCartDemoReset",
            // English keeps the seeded names stable whatever the simulator language is.
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
    }

    override func tearDown() async throws {
        app?.terminate()
        app = nil
    }

    /// REQ-CART-030 adds a name-only line and REQ-CART-040 marks it bought; the progress
    /// header counts both steps.
    func test_REQ_CART_040_addedItemMarkedBoughtUpdatesProgress() throws {
        app.launch()
        let progress = app.descendants(matching: .any)["cart.progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: Self.timeout))
        let before = try progressCounts(progress)

        let itemName = "Smoke test item"
        app.buttons["cart.add"].tapWhenHittable(timeout: Self.timeout)
        let field = app.textFields["cart.add_field"]
        field.tapWhenHittable(timeout: Self.timeout)
        field.typeText(itemName)
        app.buttons["cart.add_submit"].tapWhenHittable(timeout: Self.timeout)
        app.buttons["cart.add_close"].tapWhenHittable(timeout: Self.timeout)

        let row = app.buttons.matching(
            NSPredicate(format: "identifier == 'cart.product_name' AND label BEGINSWITH %@", itemName)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout))
        waitForProgress(progress, toEqual: ProgressCounts(purchased: before.purchased, total: before.total + 1))

        toggle(inRowOf: row).tapWhenHittable(timeout: Self.timeout)
        waitForProgress(progress, toEqual: ProgressCounts(purchased: before.purchased + 1, total: before.total + 1))
    }

    /// REQ-SHELL-020: tapping a History day opens that day's products.
    func test_REQ_SHELL_020_historyDayOpensItsItems() {
        app.launch()
        tab(at: 1).tapWhenHittable(timeout: Self.timeout)

        app.buttons["history.day_row"].firstMatch.tapWhenHittable(timeout: Self.timeout)

        let item = app.descendants(matching: .any)["history.item_row"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: Self.timeout))
    }

    /// REQ-SHELL-030: the Settings tab carries the account group with Sign out.
    func test_REQ_SHELL_030_settingsTabShowsSignOut() {
        app.launch()
        tab(at: 2).tapWhenHittable(timeout: Self.timeout)

        XCTAssertTrue(app.scrollUntilExists(app.buttons["account.sign_out"]))
    }

    // MARK: - Helpers

    /// Tabs by position (Cart, History, Settings), so the test does not depend on titles.
    private func tab(at index: Int) -> XCUIElement {
        app.tabBars.buttons.element(boundBy: index)
    }

    /// A row's check control is its sibling, not its child: pick the toggle on the row's line.
    private func toggle(inRowOf row: XCUIElement) -> XCUIElement {
        let toggles = app.buttons.matching(identifier: "cart.product_toggle").allElementsBoundByIndex
        let rowMidY = row.frame.midY
        let nearest = toggles.min { lhs, rhs in
            abs(lhs.frame.midY - rowMidY) < abs(rhs.frame.midY - rowMidY)
        }
        return nearest ?? app.buttons["cart.product_toggle"]
    }

    /// Waits until the label's only two numbers are the expected counts, so the check holds
    /// in every language ("3 of 5 completed", "3 из 5 куплено").
    private func waitForProgress(
        _ progress: XCUIElement,
        toEqual expected: ProgressCounts,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let pattern = "^\\D*\(expected.purchased)\\D+\(expected.total)\\D*$"
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label MATCHES %@", pattern),
            object: progress
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: Self.timeout)
        XCTAssertEqual(
            result,
            .completed,
            "progress label '\(progress.label)' never showed \(expected)",
            file: file,
            line: line
        )
    }

    private func progressCounts(_ progress: XCUIElement) throws -> ProgressCounts {
        let numbers = progress.label
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
        guard numbers.count == 2 else {
            XCTFail("progress label has no 'N of M' counts: \(progress.label)")
            throw ProgressLabelError()
        }
        return ProgressCounts(purchased: numbers[0], total: numbers[1])
    }
}

private struct ProgressCounts: CustomStringConvertible {
    let purchased: Int
    let total: Int

    var description: String {
        "\(purchased) of \(total)"
    }
}

private struct ProgressLabelError: Error {}

private extension XCUIElement {
    func tapWhenHittable(timeout: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: self
        )
        let result = XCTWaiter.wait(for: [hittable], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(self) never became hittable", file: file, line: line)
        tap()
    }
}

private extension XCUIApplication {
    /// Lists are lazy: a row below the fold is not in the tree until the list scrolls to it.
    func scrollUntilExists(_ element: XCUIElement, maxSwipes: Int = 6) -> Bool {
        if element.waitForExistence(timeout: 3) {
            return true
        }
        for _ in 0 ..< maxSwipes {
            swipeUp()
            if element.waitForExistence(timeout: 2) {
                return true
            }
        }
        return false
    }
}
