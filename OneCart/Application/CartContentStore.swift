import CoreData
import Foundation

@MainActor
final class CartContentStore: ObservableObject {
    static let historyPageSize = 30

    @Published private(set) var lists: [ShoppingListEntity] = []
    @Published private(set) var activeLists: [ShoppingListEntity] = []
    @Published private(set) var products: [ProductEntity] = []
    @Published private(set) var productsByListID: [UUID: [ProductEntity]] = [:]
    @Published private(set) var history: [PurchaseHistoryEntity] = []
    @Published private(set) var historyHasMore = false

    private let persistence: PersistenceController

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    func products(inListID listID: UUID) -> [ProductEntity] {
        productsByListID[listID] ?? []
    }

    func clearContent() {
        lists = []
        activeLists = []
        products = []
        productsByListID = [:]
        history = []
        historyHasMore = false
    }

    func reloadContent(familySpaceID: UUID?) throws {
        let context = persistence.container.viewContext
        context.processPendingChanges()
        guard let familySpaceID else {
            clearContent()
            return
        }
        lists = try fetchLists(familySpaceID: familySpaceID, in: context)
        products = try fetchProducts(familySpaceID: familySpaceID, in: context)
        try reloadHistoryPage(familySpaceID: familySpaceID, in: context)
        rebuildDerivedCollections()
    }

    func refreshProducts(familySpaceID: UUID) throws {
        let context = persistence.container.viewContext
        context.processPendingChanges()
        products = try fetchProducts(familySpaceID: familySpaceID, in: context)
        rebuildDerivedCollections()
    }

    func loadMoreHistory(familySpaceID: UUID) throws {
        guard historyHasMore else { return }
        let context = persistence.container.viewContext
        context.processPendingChanges()
        let page = try fetchHistory(
            familySpaceID: familySpaceID,
            in: context,
            limit: Self.historyPageSize + 1,
            offset: history.count
        )
        historyHasMore = page.count > Self.historyPageSize
        history.append(contentsOf: Array(page.prefix(Self.historyPageSize)))
    }

    func rebuildDerivedCollections() {
        activeLists = lists.filter { !$0.isDeletedValue && $0.statusValue == .active }

        var grouped: [UUID: [ProductEntity]] = [:]
        for product in products where !product.isDeletedValue {
            guard let listID = product.list?.id else { continue }
            grouped[listID, default: []].append(product)
        }
        productsByListID = grouped
    }

    private func reloadHistoryPage(
        familySpaceID: UUID,
        in context: NSManagedObjectContext
    ) throws {
        let page = try fetchHistory(
            familySpaceID: familySpaceID,
            in: context,
            limit: Self.historyPageSize + 1,
            offset: 0
        )
        historyHasMore = page.count > Self.historyPageSize
        history = Array(page.prefix(Self.historyPageSize))
    }

    private func fetchLists(
        familySpaceID: UUID,
        in context: NSManagedObjectContext
    ) throws -> [ShoppingListEntity] {
        let request = ShoppingListEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "familySpace.id == %@", familySpaceID as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ])
        request.sortDescriptors = [
            NSSortDescriptor(key: "status", ascending: true),
            NSSortDescriptor(key: "updatedAt", ascending: false),
        ]
        return try context.fetch(request)
    }

    private func fetchProducts(
        familySpaceID: UUID,
        in context: NSManagedObjectContext
    ) throws -> [ProductEntity] {
        let request = ProductEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "familySpace.id == %@", familySpaceID as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ])
        request.sortDescriptors = [
            NSSortDescriptor(key: "isPurchased", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
        ]
        return try context.fetch(request)
    }

    func fetchHistory(
        familySpaceID: UUID,
        in context: NSManagedObjectContext,
        limit: Int? = nil,
        offset: Int = 0
    ) throws -> [PurchaseHistoryEntity] {
        let request = PurchaseHistoryEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "familySpace.id == %@", familySpaceID as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        if let limit {
            request.fetchLimit = limit
        }
        if offset > 0 {
            request.fetchOffset = offset
        }
        request.fetchBatchSize = 20
        return try context.fetch(request)
    }
}
