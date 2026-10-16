import Foundation

/// The record names are optional in the stored JSON too, so snapshots saved before they existed
/// still decode.
struct CartItemSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let isPurchased: Bool
    let createdByName: String?
    let purchasedByName: String?
    let createdByRecordName: String?
    let purchasedByRecordName: String?

    init(
        id: UUID,
        name: String,
        isPurchased: Bool,
        createdByName: String? = nil,
        purchasedByName: String? = nil,
        createdByRecordName: String? = nil,
        purchasedByRecordName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isPurchased = isPurchased
        self.createdByName = createdByName
        self.purchasedByName = purchasedByName
        self.createdByRecordName = createdByRecordName
        self.purchasedByRecordName = purchasedByRecordName
    }
}
