import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

protocol CategoryClassifying: Sendable {
    func classify(_ productName: String) async -> ProductCategory
}

enum ProductCategoryClassifier {
    static let shared: any CategoryClassifying = CompositeCategoryClassifier()
}

struct KeywordCategoryClassifier: CategoryClassifying {
    func classify(_ productName: String) async -> ProductCategory {
        ProductCategory.inferred(from: productName)
    }
}

struct CompositeCategoryClassifier: CategoryClassifying {
    private let keywords = KeywordCategoryClassifier()

    func classify(_ productName: String) async -> ProductCategory {
        let fallback = await keywords.classify(productName)
        #if canImport(FoundationModels)
            if let refined = await FoundationModelsCategoryClassifier().classifyIfAvailable(productName) {
                return refined
            }
        #endif
        return fallback
    }
}

#if canImport(FoundationModels)
    @Generable
    enum GroceryCategoryLabel: String, CaseIterable {
        case produce
        case dairy
        case meat
        case drinks
        case household
        case other

        var productCategory: ProductCategory {
            ProductCategory(rawValue: rawValue) ?? .other
        }
    }

    struct FoundationModelsCategoryClassifier: Sendable {
        private let timeoutNanoseconds: UInt64 = 3_000_000_000

        func classifyIfAvailable(_ productName: String) async -> ProductCategory? {
            let trimmed = productName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let model = SystemLanguageModel.default
            guard case .available = model.availability else { return nil }

            return await withTimeout(nanoseconds: timeoutNanoseconds) {
                let session = LanguageModelSession(
                    instructions: """
                    You classify grocery shopping-list item names into exactly one category.
                    Allowed categories: produce, dairy, meat, drinks, household, other.
                    Use other when unsure. Respond with the category only via structured output.
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

        private func withTimeout(
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
#endif
