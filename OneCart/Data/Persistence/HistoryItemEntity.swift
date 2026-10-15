import CoreData
import Foundation

@objc(HistoryItemEntity)
final class HistoryItemEntity: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var quantity: NSNumber?
    @NSManaged var unit: String?
    @NSManaged var category: String?
    @NSManaged var estimatedPrice: NSNumber?
    @NSManaged var originalPrice: NSNumber?
    @NSManaged var imageURL: String?
    @NSManaged var sourceURL: String?
    @NSManaged var note: String?
    @NSManaged var purchasedAt: Date?
    @NSManaged var purchasedByName: String?
    @NSManaged var createdByName: String?
    @NSManaged var storeName: String?
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var deletedAt: Date?
    @NSManaged var familySpace: FamilySpace?
    @NSManaged var history: PurchaseHistoryEntity?

    @nonobjc static func fetchRequest() -> NSFetchRequest<HistoryItemEntity> {
        NSFetchRequest<HistoryItemEntity>(entityName: "HistoryItem")
    }

    var displayName: String {
        name?.nilIfBlank ?? String(localized: "common.default_product")
    }

    var quantityValue: Double {
        max(quantity?.doubleValue ?? 1, 0)
    }

    var unitValue: ProductUnit {
        ProductUnit(rawValue: unit ?? "") ?? .piece
    }

    var categoryValue: ProductCategory {
        ProductCategory.resolved(storedRawValue: category)
    }

    var purchaseMoment: Date {
        purchasedAt ?? createdAt ?? history?.purchaseDate ?? .distantPast
    }

    var estimatedPriceValue: Double {
        max(estimatedPrice?.doubleValue ?? 0, 0)
    }

    var imageURLValue: URL? {
        imageURL.flatMap(URL.init(string:))
    }

    var sourceURLValue: URL? {
        sourceURL.flatMap(URL.init(string:))
    }

    var createdDate: Date {
        createdAt ?? .distantPast
    }

    var updatedDate: Date {
        updatedAt ?? createdDate
    }

    var isDeletedValue: Bool {
        deletedAt != nil
    }
}

enum HistoryItems {
    private struct Identity: Hashable {
        let familyID: UUID
        let productID: UUID
    }

    /// Peers can archive the same product before receiving each other's tombstones.
    /// Keep transport records intact and count each family/product only once.
    static func unique(from entries: [PurchaseHistoryEntity]) -> [HistoryItemEntity] {
        var items: [HistoryItemEntity] = []
        var indices: [Identity: Int] = [:]

        for entry in entries where !entry.isDeletedValue {
            for item in entry.sortedItems {
                guard let familyID = item.familySpace?.id ?? entry.familySpace?.id,
                    let productID = item.id
                else {
                    items.append(item)
                    continue
                }
                let identity = Identity(familyID: familyID, productID: productID)
                if let index = indices[identity] {
                    if orderingKey(for: item).lexicographicallyPrecedes(orderingKey(for: items[index])) {
                        items[index] = item
                    }
                } else {
                    indices[identity] = items.count
                    items.append(item)
                }
            }
        }
        return items
    }

    private static func orderingKey(for item: HistoryItemEntity) -> [String] {
        [
            item.history?.id?.uuidString ?? "~",
            item.purchasedAt.map { String($0.timeIntervalSinceReferenceDate) } ?? "",
            item.name ?? "",
            item.quantity?.stringValue ?? "",
            item.unit ?? "",
            item.category ?? "",
            item.estimatedPrice?.stringValue ?? "",
            item.originalPrice?.stringValue ?? "",
            item.imageURL ?? "",
            item.sourceURL ?? "",
            item.note ?? "",
            item.purchasedByName ?? "",
            item.storeName ?? "",
            item.createdAt.map { String($0.timeIntervalSinceReferenceDate) } ?? "",
            item.updatedAt.map { String($0.timeIntervalSinceReferenceDate) } ?? "",
            item.createdByName ?? "",
        ]
    }
}
