import Foundation

public struct WidgetItemSnapshot: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public var isPurchased: Bool
    public let categoryRaw: String
    public let subtitle: String?

    public init(
        id: UUID,
        name: String,
        isPurchased: Bool,
        categoryRaw: String,
        subtitle: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isPurchased = isPurchased
        self.categoryRaw = categoryRaw
        self.subtitle = subtitle
    }

    /// The stored raw value may come from a newer app than the widget; unknown values
    /// draw as `other` instead of hiding the line.
    var category: ProductCategory {
        ProductCategory(rawValue: categoryRaw) ?? .other
    }
}
