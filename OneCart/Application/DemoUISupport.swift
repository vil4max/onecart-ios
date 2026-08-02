#if DEBUG
    import AuthenticationServices
    import CoreData
    import Foundation

    enum DemoUIMode {
        static let launchArgument = "-oneCartDemoUI"
        static let tabArgument = "-oneCartDemoTab"
        static let roleArgument = "-oneCartDemoRole"

        enum Role: String {
            case owner
            case member
        }

        static var isEnabled: Bool {
            ProcessInfo.processInfo.arguments.contains(launchArgument)
        }

        static var role: Role {
            guard isEnabled else { return .owner }
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: roleArgument),
                  let raw = arguments[safe: index + 1],
                  let parsed = Role(rawValue: raw.lowercased())
            else {
                return .owner
            }
            return parsed
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
        static func makeSession() -> AppSession {
            let suiteName = role == .member ? "onecart.demo-ui.member" : "onecart.demo-ui"
            return AppSession(
                persistence: PersistenceController(inMemory: true, cloudKitEnabled: false),
                defaults: UserDefaults(suiteName: suiteName) ?? .standard,
                appleSignIn: DemoAppleSignInService(role: role)
            )
        }

        @MainActor
        static func seed(_ model: AppSession) async {
            switch role {
            case .owner:
                await seedOwnerPersonalCart(model)
            case .member:
                await seedGuestSharedCart(model)
            }
        }

        @MainActor
        private static func seedOwnerPersonalCart(_ model: AppSession) async {
            guard let listID = model.activeLists.first?.id else { return }
            await seedLivingList(on: listID, model: model)
        }

        @MainActor
        private static func seedGuestSharedCart(_ model: AppSession) async {
            guard let account = model.account else { return }
            let persistence = model.persistence
            let sharedID = UUID()
            let listID = UUID()
            let sharedName = "Max's Cart"
            let now = Date()

            do {
                try await persistence.performBackgroundTask { context in
                    let space = FamilySpace(context: context)
                    try persistence.assign(space, to: .shared, in: context)
                    space.id = sharedID
                    space.name = sharedName
                    space.createdAt = now
                    space.updatedAt = now
                    space.isHouseholdDefault = NSNumber(value: true)

                    let list = ShoppingListEntity(context: context)
                    try persistence.assign(list, toSameStoreAs: space, in: context)
                    list.id = listID
                    list.title = String(localized: "common.default_list")
                    list.status = ShoppingListStatus.active.rawValue
                    list.createdAt = now
                    list.updatedAt = now
                    list.familySpace = space
                }
                persistence.container.viewContext.processPendingChanges()

                model.defaults.set(
                    sharedID.uuidString,
                    forKey: model.activeFamilyKey(accountID: account.id)
                )
                try model.reload(preferredFamilySpaceID: sharedID)

                await seedLivingList(on: listID, model: model)

                let ownerID = OneCartStableID.uuid(for: "onecart.demo-owner")
                model.familyMembers = [
                    FamilyMember(
                        id: ownerID,
                        displayName: "Max",
                        access: .owner,
                        joinedAt: now.addingTimeInterval(-86400),
                        isCurrentUser: false,
                        avatarURL: nil,
                        bannerURL: nil
                    ),
                    FamilyMember(
                        id: account.id,
                        displayName: account.displayName,
                        access: .member,
                        joinedAt: now,
                        isCurrentUser: true,
                        avatarURL: nil,
                        bannerURL: nil
                    ),
                ]
            } catch {
                CartSyncLog.action.error(
                    "demo member seed failed error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }

        @MainActor
        private static func seedLivingList(on listID: UUID, model: AppSession) async {
            for name in ["Milk", "Bread", "Apples", "Coffee"] {
                guard let list = model.activeLists.first(where: { $0.id == listID }) else { return }
                await model.addProduct(to: list, draft: draft(named: name))
            }
            for product in purchasable(listID: listID, from: model).prefix(3) {
                await model.togglePurchased(product)
            }
            if let list = model.activeLists.first(where: { $0.id == listID }) {
                await model.completePurchasedItems(list)
            }

            for name in ["Cheese", "Tomatoes", "Laundry detergent", "Orange juice"] {
                guard let list = model.activeLists.first(where: { $0.id == listID }) else { return }
                await model.addProduct(to: list, draft: draft(named: name))
            }
            for product in purchasable(listID: listID, from: model).prefix(2) {
                await model.togglePurchased(product)
            }
        }

        @MainActor
        private static func purchasable(
            listID: UUID,
            from model: AppSession
        ) -> [ProductEntity] {
            model.products(inListID: listID).filter { !$0.isPurchasedValue }
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
        private var credential: AppleSignInCredential

        init(role: DemoUIMode.Role) {
            switch role {
            case .owner:
                credential = AppleSignInCredential(
                    userID: "onecart-demo-owner",
                    email: nil,
                    givenName: "Max",
                    familyName: nil
                )
            case .member:
                credential = AppleSignInCredential(
                    userID: "onecart-demo-member",
                    email: nil,
                    givenName: "Tim",
                    familyName: nil
                )
            }
        }

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
