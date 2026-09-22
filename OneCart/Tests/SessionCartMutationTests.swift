import CoreData
@testable import OneCart
import Testing

/// Cart mutations driven through the session (`AppSession+CartMutations`): the repository
/// paths are covered elsewhere; these assert the session's gates, the state it refreshes
/// and the alerts it raises.
@Suite("AppSession cart mutations")
@MainActor
struct SessionCartMutationTests {
    /// Seeds through the repository: `AppSession.addProduct` also starts a background category
    /// refinement that rewrites the row from a snapshot of its draft, which would race the
    /// mutation under test.
    private func addProduct(
        named name: String,
        to fixture: MembershipSessionFixture
    ) async throws -> ProductEntity {
        let listID = try #require(fixture.session.activeLists.first?.id)
        let id = try await fixture.repository.addProduct(to: listID, draft: draft(named: name))
        let context = fixture.persistence.container.viewContext
        await context.perform { context.processPendingChanges() }
        try fixture.session.reload()
        return try #require(fixture.session.products.first { $0.id == id })
    }

    private func draft(named name: String) -> ProductDraft {
        ProductDraft(name: name, quantity: 1, unit: .piece, category: .other, estimatedPrice: 0, note: "")
    }

    @Test("REQ-CART-040: checking an item records the shopper and unchecking clears it")
    func togglePurchasedRecordsAndClearsShopper() async throws {
        let fixture = try await MembershipSessionFixture.owner(displayName: "Alex")
        let product = try await addProduct(named: "Молоко", to: fixture)
        #expect(product.isPurchasedValue == false)

        await fixture.session.togglePurchased(product)
        let checked = try #require(fixture.session.products.first { $0.id == product.id })
        #expect(checked.isPurchasedValue)
        #expect(checked.purchasedByName == "Alex")

        await fixture.session.togglePurchased(checked)
        let unchecked = try #require(fixture.session.products.first { $0.id == product.id })
        #expect(unchecked.isPurchasedValue == false)
        #expect(unchecked.purchasedByName == nil)
        #expect(fixture.session.userAlert == nil)
    }

    @Test("REQ-CART-050: a Completed item survives delete; a to-buy item is removed")
    func deleteSkipsCompletedItems() async throws {
        let fixture = try await MembershipSessionFixture.owner()
        let bread = try await addProduct(named: "Хлеб", to: fixture)
        let milk = try await addProduct(named: "Молоко", to: fixture)
        await fixture.session.togglePurchased(milk)
        let completedMilk = try #require(fixture.session.products.first { $0.id == milk.id })

        await fixture.session.deleteProduct(completedMilk)
        #expect(fixture.session.products.map(\.id).contains(milk.id))

        await fixture.session.deleteProduct(bread)
        #expect(fixture.session.products.map(\.id).contains(bread.id) == false)
        #expect(fixture.session.products.count == 1)
        #expect(fixture.session.userAlert == nil)
    }

    @Test("REQ-CART-020: updating an item rewrites its name")
    func updateProductRewritesName() async throws {
        let fixture = try await MembershipSessionFixture.owner()
        let product = try await addProduct(named: "Хлеб", to: fixture)

        await fixture.session.updateProduct(product, draft: draft(named: "Батон"))

        let updated = try #require(fixture.session.products.first { $0.id == product.id })
        #expect(updated.displayName == "Батон")
        #expect(fixture.session.userAlert == nil)
    }

    @Test("A row that lost its identity in a hard refresh is dropped without an alert")
    func staleProductIsDropped() async throws {
        let fixture = try await MembershipSessionFixture.owner()
        let product = try await addProduct(named: "Хлеб", to: fixture)
        product.id = nil

        await fixture.session.togglePurchased(product)
        await fixture.session.updateProduct(product, draft: draft(named: "Батон"))
        await fixture.session.deleteProduct(product)

        #expect(fixture.session.products.count == 1)
        #expect(fixture.session.products.first?.isPurchasedValue == false)
        #expect(fixture.session.products.first?.displayName == "Хлеб")
        #expect(fixture.session.userAlert == nil)
    }

    @Test("REQ-SHELL-050: a mutation while editing is unavailable raises the permission alert")
    func mutationWhileEditingUnavailableRaisesPermissionAlert() async throws {
        let fixture = try await MembershipSessionFixture.owner()
        let product = try await addProduct(named: "Хлеб", to: fixture)
        let list = try #require(fixture.session.activeLists.first)
        fixture.session.isDeletingAccount = true
        #expect(fixture.session.canEdit == false)

        await fixture.session.togglePurchased(product)
        #expect(fixture.session.alertMessage == RepositoryError.permissionDenied.localizedDescription)
        #expect(fixture.session.products.first?.isPurchasedValue == false)

        fixture.session.dismissAlert()
        let added = await fixture.session.addProduct(to: list, draft: draft(named: "Молоко"))
        #expect(added == nil)
        #expect(fixture.session.alertMessage == RepositoryError.permissionDenied.localizedDescription)
        #expect(fixture.session.products.count == 1)
        #expect(fixture.session.isBusy == false)
    }

    @Test("Completing the checked items archives them into History and keeps the rest")
    func completePurchasedItemsArchivesCheckedRows() async throws {
        let fixture = try await MembershipSessionFixture.owner()
        let bread = try await addProduct(named: "Хлеб", to: fixture)
        let milk = try await addProduct(named: "Молоко", to: fixture)
        await fixture.session.togglePurchased(milk)
        let list = try #require(fixture.session.activeLists.first)

        await fixture.session.completePurchasedItems(list)

        #expect(fixture.session.products.map(\.id) == [bread.id])
        #expect(fixture.session.history.count == 1)
        #expect(fixture.session.userAlert == nil)
    }

    @Test("REQ-HIST-030: loading more history is a no-op without a cart or a next page")
    func loadMoreHistoryWithoutNextPageIsANoOp() async throws {
        let signedOut = try await MembershipSessionFixture.signedOut()
        signedOut.session.loadMoreHistory()
        #expect(signedOut.session.history.isEmpty)

        let owner = try await MembershipSessionFixture.owner()
        #expect(owner.session.historyHasMore == false)
        owner.session.loadMoreHistory()
        #expect(owner.session.history.isEmpty)
        #expect(owner.session.userAlert == nil)
    }

    @Test("REQ-CART-090: same-name rows delivered with different IDs merge into one line")
    func deduplicateMergesSameNameRows() async throws {
        let fixture = try await MembershipSessionFixture.owner()
        let familyID = try #require(fixture.personalID)
        let listID = try #require(fixture.session.activeLists.first?.id)
        let firstID = UUID()
        let persistence = fixture.persistence
        try await persistence.performBackgroundTask { context in
            let family = try FamilySpaceRepository.requireFamilySpace(id: familyID, in: context)
            guard let list = try FamilySpaceRepository.fetchList(id: listID, in: context) else {
                throw RepositoryError.listNotFound
            }
            for (stableID, name, offset) in [
                (firstID, "Молоко", 0.0), (UUID(), " молоко ", 60.0),
            ] as [(UUID, String, TimeInterval)] {
                let product = ProductEntity(context: context)
                try persistence.assign(product, toSameStoreAs: family, in: context)
                product.id = stableID
                product.name = name
                product.quantity = NSNumber(value: 1)
                product.unit = ProductUnit.piece.rawValue
                product.category = ProductCategory.other.rawValue
                product.estimatedPrice = NSNumber(value: 0)
                product.isPurchased = NSNumber(value: false)
                product.note = ""
                product.createdAt = Date().addingTimeInterval(offset)
                product.updatedAt = product.createdAt
                product.familySpace = family
                product.list = list
            }
        }
        let revisionBefore = fixture.session.contentRevision

        await fixture.session.deduplicateCartIfNeeded()

        #expect(fixture.session.products.map(\.id) == [firstID])
        #expect(fixture.session.contentRevision > revisionBefore)

        await fixture.session.deduplicateCartIfNeeded()
        #expect(fixture.session.products.map(\.id) == [firstID])
    }

    @Test("REQ-AUTH-040: the device-local name updates the account, the member row and the preference")
    func participantDisplayNameUpdatesAccountAndMemberRow() async throws {
        let fixture = try await MembershipSessionFixture.owner(displayName: "Alex")
        await fixture.session.refreshFamilyMetadata(showErrors: true)
        #expect(fixture.session.familyMembers.first?.displayName == "Alex")

        await fixture.session.updateParticipantDisplayName("  Мама ")

        #expect(fixture.session.preferences.participantDisplayName == "Мама")
        #expect(fixture.session.account?.displayName == "Мама")
        #expect(fixture.session.familyMembers.first?.displayName == "Мама")
        #expect(fixture.session.familyMembers.first?.isCurrentUser == true)

        await fixture.session.updateParticipantDisplayName("   ")

        #expect(fixture.session.preferences.participantDisplayName == "")
        #expect(fixture.session.account?.displayName == ParticipantDisplayName.placeholder)
        #expect(fixture.session.userAlert == nil)
    }
}

// MARK: - Category refinement vs. rename

/// Holds every classification until the test releases it, in call order.
private actor GatedClassifier: CategoryClassifying {
    private var pending: [CheckedContinuation<Void, Never>] = []
    private let categories: [String: ProductCategory]

    init(categories: [String: ProductCategory]) {
        self.categories = categories
    }

    var pendingCount: Int {
        pending.count
    }

    func classify(_ productName: String) async -> ProductCategory {
        await withCheckedContinuation { pending.append($0) }
        return categories[productName] ?? .other
    }

    /// Resumes the oldest held classification.
    func releaseNext() {
        guard !pending.isEmpty else { return }
        pending.removeFirst().resume()
    }

    func waitUntilHeld(_ count: Int) async {
        while pending.count < count {
            await Task.yield()
        }
    }
}

extension SessionCartMutationTests {
    private func draft(named name: String, category: ProductCategory) -> ProductDraft {
        ProductDraft(name: name, quantity: 1, unit: .piece, category: category, estimatedPrice: 0, note: "")
    }

    @Test("REQ-CART-020: a rename during category refinement keeps the new name and its category")
    func renameDuringRefinementIsNotOverwritten() async throws {
        let classifier = GatedClassifier(categories: ["Milk": .dairyEggs, "Oat milk": .coldDrinks])
        let fixture = try await MembershipSessionFixture.owner(displayName: "Alex", classifier: classifier)
        let list = try #require(fixture.session.activeLists.first)

        let id = try #require(await fixture.session.addProduct(to: list, draft: draft(named: "Milk", category: .other)))
        await classifier.waitUntilHeld(1)
        let firstRefinement = try #require(fixture.session.categoryRefinementTasks[id])

        let product = try #require(fixture.session.products.first { $0.id == id })
        await fixture.session.updateProduct(product, draft: draft(named: "Oat milk", category: .other))
        await classifier.waitUntilHeld(2)
        let secondRefinement = try #require(fixture.session.categoryRefinementTasks[id])

        // The refinement of the old name resumes first; it must not touch the renamed row.
        await classifier.releaseNext()
        await firstRefinement.value
        let afterStale = try #require(fixture.session.products.first { $0.id == id })
        #expect(afterStale.displayName == "Oat milk")
        #expect(afterStale.categoryValue == .other)

        // The refinement of the new name still lands.
        await classifier.releaseNext()
        await secondRefinement.value
        let afterFresh = try #require(fixture.session.products.first { $0.id == id })
        #expect(afterFresh.displayName == "Oat milk")
        #expect(afterFresh.categoryValue == .coldDrinks)
    }
}

