import CoreData
import Foundation

/// Mirrored CloudKit rows are tombstoned with `deletedAt` instead of being deleted, so the
/// deletion reaches the other devices.
protocol SoftDeletable: AnyObject {
    var deletedAt: Date? { get set }
}

protocol Timestamped: AnyObject {
    var updatedAt: Date? { get set }
}

extension FamilySpace: SoftDeletable, Timestamped {}
extension StoreEntity: SoftDeletable, Timestamped {}
extension ShoppingListEntity: SoftDeletable, Timestamped {}
extension ProductEntity: SoftDeletable, Timestamped {}
extension PurchaseHistoryEntity: SoftDeletable, Timestamped {}
