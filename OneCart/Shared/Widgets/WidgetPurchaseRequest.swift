import Foundation

public struct WidgetPurchaseRequest: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let accountID: UUID
    public let familyID: UUID
    public let productID: UUID
    public let isPurchased: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        accountID: UUID,
        familyID: UUID,
        productID: UUID,
        isPurchased: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.accountID = accountID
        self.familyID = familyID
        self.productID = productID
        self.isPurchased = isPurchased
        self.createdAt = createdAt
    }
}
