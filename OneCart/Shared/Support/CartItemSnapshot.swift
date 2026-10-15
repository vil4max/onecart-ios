import Foundation

struct CartItemSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let isPurchased: Bool
    let createdByName: String?
    let purchasedByName: String?

    init(
        id: UUID,
        name: String,
        isPurchased: Bool,
        createdByName: String? = nil,
        purchasedByName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isPurchased = isPurchased
        self.createdByName = createdByName
        self.purchasedByName = purchasedByName
    }
}
