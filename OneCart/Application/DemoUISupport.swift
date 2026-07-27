#if DEBUG
    import AuthenticationServices
    import Foundation

    enum DemoUIMode {
        static let launchArgument = "-oneCartDemoUI"
        static let tabArgument = "-oneCartDemoTab"

        static var isEnabled: Bool {
            ProcessInfo.processInfo.arguments.contains(launchArgument)
        }

        static var initialTab: MainTab? {
            guard isEnabled else { return nil }
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: tabArgument),
                  let raw = arguments[safe: index + 1]
            else {
                return nil
            }
            return MainTab(rawValue: raw)
        }

        @MainActor
        static func makeSession() -> AppModel {
            AppSession(
                persistence: PersistenceController(inMemory: true, cloudKitEnabled: false),
                defaults: UserDefaults(suiteName: "onecart.demo-ui") ?? .standard,
                appleSignIn: DemoAppleSignInService()
            )
        }

        @MainActor
        static func seed(_ model: AppModel) async {
            guard let list = model.activeLists.first else { return }

            for name in ["Молоко", "Хлеб", "Яблоки", "Кофе"] {
                await model.addProduct(to: list, draft: draft(named: name))
            }
            for product in purchasable(in: list, from: model).prefix(3) {
                await model.togglePurchased(product)
            }
            await model.completePurchasedItems(list)

            for name in ["Сыр", "Помидоры", "Стиральный порошок", "Апельсиновый сок"] {
                await model.addProduct(to: list, draft: draft(named: name))
            }
            for product in purchasable(in: list, from: model).prefix(2) {
                await model.togglePurchased(product)
            }
        }

        @MainActor
        private static func purchasable(
            in list: ShoppingListEntity,
            from model: AppModel
        ) -> [ProductEntity] {
            guard let id = list.id else { return [] }
            return model.products(inListID: id).filter { !$0.isPurchasedValue }
        }

        private static func draft(named name: String) -> ProductDraft {
            ProductDraft(
                name: name,
                quantity: 1,
                unit: .piece,
                category: ProductCategory.inferred(from: name),
                estimatedPrice: 0,
                note: "",
                imageURL: nil,
                sourceURL: nil,
                originalPrice: nil,
                loyaltyPrice: nil,
                catalogFetchedAt: nil,
                promotionEndsAt: nil
            )
        }
    }

    private extension Array {
        subscript(safe index: Int) -> Element? {
            indices.contains(index) ? self[index] : nil
        }
    }

    final class DemoAppleSignInService: AppleSignInAuthenticating {
        private var credential = AppleSignInCredential(
            userID: "onecart-demo-user",
            email: nil,
            givenName: "Максим",
            familyName: nil
        )

        func storedCredential() -> AppleSignInCredential? {
            credential
        }

        func save(_ credential: AppleSignInCredential) {
            self.credential = credential
        }

        func clearCredential() {}

        func credentialState(for _: String) async -> AppleSignInCredentialState {
            .authorized
        }

        func signIn() async throws -> AppleSignInCredential {
            credential
        }

        func makeCredential(from _: ASAuthorization) throws -> AppleSignInCredential {
            credential
        }
    }
#endif
