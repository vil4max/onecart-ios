import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

protocol CategoryClassifying: Sendable {
    func classify(_ productName: String) async -> ProductCategory
}

struct KeywordCategoryClassifier: CategoryClassifying {
    func classify(_ productName: String) async -> ProductCategory {
        ProductCategory.inferred(from: productName)
    }
}

/// The keyword category, refined by the on-device model when it is available. The model's
/// availability and its answer are injected, so tests drive the fallback without a model.
struct CompositeCategoryClassifier: CategoryClassifying {
    private let keywords = KeywordCategoryClassifier()
    private let isModelAvailable: @Sendable () -> Bool
    private let generate: @Sendable (String) async throws -> ProductCategory
    private let timeoutNanoseconds: UInt64

    init(
        isModelAvailable: @escaping @Sendable () -> Bool,
        generate: @escaping @Sendable (String) async throws -> ProductCategory,
        timeoutNanoseconds: UInt64 = 3_000_000_000
    ) {
        self.isModelAvailable = isModelAvailable
        self.generate = generate
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    /// The on-device language model where the SDK has it; elsewhere the keywords alone.
    static func live() -> CompositeCategoryClassifier {
        #if canImport(FoundationModels)
            CompositeCategoryClassifier(
                isModelAvailable: { FoundationModelsCategoryClassifier.isAvailable },
                generate: { try await FoundationModelsCategoryClassifier.generate(for: $0) }
            )
        #else
            CompositeCategoryClassifier(isModelAvailable: { false }, generate: { _ in .other })
        #endif
    }

    func classify(_ productName: String) async -> ProductCategory {
        let fallback = await keywords.classify(productName)
        let trimmed = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isModelAvailable() else { return fallback }
        let generate = generate
        let refined = await Self.withTimeout(nanoseconds: timeoutNanoseconds) {
            try await generate(trimmed)
        }
        return refined ?? fallback
    }

    /// A slow or failing model yields nil, so the caller keeps the keyword category.
    static func withTimeout(
        nanoseconds: UInt64,
        operation: @escaping @Sendable () async throws -> ProductCategory
    ) async -> ProductCategory? {
        await withTaskGroup(of: ProductCategory?.self) { group in
            group.addTask {
                do {
                    return try await operation()
                } catch {
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: nanoseconds)
                return nil
            }
            let first = await group.next()
            group.cancelAll()
            return first ?? nil
        }
    }
}

#if canImport(FoundationModels)
    @Generable
    enum GroceryCategoryLabel: String, CaseIterable {
        case meatPoultry
        case fishSeafood
        case dairyEggs
        case grocery
        case oilCanned
        case produce
        case frozen
        case bakery
        case saucesSpices
        case alcohol
        case coldDrinks
        case hotDrinks
        case sweetsSnacks
        case babyFood
        case household
        case other

        var productCategory: ProductCategory {
            ProductCategory.resolved(storedRawValue: rawValue)
        }
    }

    enum FoundationModelsCategoryClassifier {
        static var isAvailable: Bool {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
            return false
        }

        /// Asks the model for one category; `CompositeCategoryClassifier` bounds the wait.
        static func generate(for trimmed: String) async throws -> ProductCategory {
            let session = LanguageModelSession(
                instructions: """
                    You classify grocery shopping-list item names into exactly one Metro-style category.
                    Categories:
                    - meatPoultry: meat, poultry, sausages, ham
                    - fishSeafood: fish, seafood, shrimp, caviar
                    - dairyEggs: milk, cheese, yogurt, butter, eggs
                    - grocery: cereals, pasta, flour, sugar, salt, porridge
                    - oilCanned: cooking oil, vinegar, canned food
                    - produce: fruits, vegetables, greens, berries
                    - frozen: frozen food, ice cream, dumplings
                    - bakery: bread, lavash, bakery goods (not sweets)
                    - saucesSpices: sauces, ketchup, mayo, spices
                    - alcohol: beer, wine, spirits
                    - coldDrinks: water, juice, soda, soft drinks
                    - hotDrinks: tea, coffee, cocoa
                    - sweetsSnacks: candy, chocolate, cookies, chips, snacks
                    - babyFood: baby food, infant formula
                    - household: cleaning and non-food household goods
                    - other: anything else or unsure
                    Respond with the category only via structured output.
                    """
            )
            let response = try await session.respond(
                to: "Classify this grocery item name: \(trimmed)",
                generating: GroceryCategoryLabel.self,
                options: GenerationOptions(temperature: 0.2)
            )
            return response.content.productCategory
        }
    }
#endif
