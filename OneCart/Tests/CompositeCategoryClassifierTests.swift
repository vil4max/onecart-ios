import Foundation
@testable import OneCart
import Synchronization
import Testing

/// The keyword category stays whenever the on-device model cannot answer in time (REQ-SHELL-010).
/// Availability and the model's answer are injected, so no test waits on a real model.
@Suite("Category classifier fallback")
struct CompositeCategoryClassifierTests {
    private struct ModelFailure: Error {}

    /// Counts the model calls, so a test can tell an unasked model from one that failed.
    private final class Calls: Sendable {
        private let names = Mutex<[String]>([])
        var value: Int { names.withLock { $0.count } }
        var asked: [String] { names.withLock { $0 } }
        func record(_ name: String = "") { names.withLock { $0.append(name) } }
    }

    @Test("REQ-SHELL-010: an unavailable model is never asked and the keyword category stays")
    func unavailableModelKeepsTheKeywordCategory() async {
        let calls = Calls()
        let classifier = CompositeCategoryClassifier(
            isModelAvailable: { false },
            generate: { _ in
                calls.record()
                return .household
            }
        )

        #expect(await classifier.classify("Хлеб") == .bakery)
        #expect(calls.value == 0)
    }

    @Test("REQ-SHELL-010: a model that throws leaves the keyword category")
    func failingModelKeepsTheKeywordCategory() async {
        let classifier = CompositeCategoryClassifier(
            isModelAvailable: { true },
            generate: { _ in throw ModelFailure() }
        )

        #expect(await classifier.classify("Хлеб") == .bakery)
    }

    @Test("REQ-SHELL-010: a model slower than the timeout leaves the keyword category")
    func slowModelKeepsTheKeywordCategory() async {
        let classifier = CompositeCategoryClassifier(
            isModelAvailable: { true },
            generate: { _ in
                try await Task.sleep(for: .seconds(60))
                return .household
            },
            timeoutNanoseconds: 1_000_000
        )

        #expect(await classifier.classify("Хлеб") == .bakery)
    }

    @Test("REQ-SHELL-010: an available model refines the category with the trimmed name; a blank name skips it")
    func availableModelRefinesTheCategory() async {
        let calls = Calls()
        let classifier = CompositeCategoryClassifier(
            isModelAvailable: { true },
            generate: { name in
                calls.record(name)
                return .household
            }
        )

        #expect(await classifier.classify("  Хлеб  ") == .household)
        #expect(calls.asked == ["Хлеб"])
        _ = await classifier.classify("   ")
        #expect(calls.value == 1)
    }
}
