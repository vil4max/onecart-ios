import ActivityKit
import Foundation

/// The shopping trip shown on the Lock Screen and in the Dynamic Island (REQ-WIDGET-040).
/// The identity pins the trip to one account and cart; everything that can change during
/// the trip lives in `ContentState` so a rename or a theme switch updates it in place.
public struct ShoppingTripAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var cartTitle: String
        public var purchasedCount: Int
        public var totalCount: Int
        /// The first to-buy lines in cart order; the activity checks them off in place.
        public var nextItems: [ShoppingTripItem]
        public var accentColorRaw: String?

        public init(
            cartTitle: String,
            purchasedCount: Int,
            totalCount: Int,
            nextItems: [ShoppingTripItem],
            accentColorRaw: String? = nil
        ) {
            self.cartTitle = cartTitle
            self.purchasedCount = purchasedCount
            self.totalCount = totalCount
            self.nextItems = nextItems
            self.accentColorRaw = accentColorRaw
        }

        public var remainingCount: Int {
            max(0, totalCount - purchasedCount)
        }

        public var progress: Double {
            totalCount > 0 ? Double(purchasedCount) / Double(totalCount) : 0
        }

        public var isAllPurchased: Bool {
            totalCount > 0 && purchasedCount >= totalCount
        }

        public var accentColor: AppAccentColor {
            accentColorRaw.flatMap(AppAccentColor.init(rawValue:)) ?? .emerald
        }
    }

    public let accountID: UUID
    public let familyID: UUID

    public init(accountID: UUID, familyID: UUID) {
        self.accountID = accountID
        self.familyID = familyID
    }
}

public struct ShoppingTripItem: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let categoryRaw: String

    public init(id: UUID, name: String, categoryRaw: String) {
        self.id = id
        self.name = name
        self.categoryRaw = categoryRaw
    }

    /// Unknown raw values from a newer app draw as `other` instead of hiding the line.
    var category: ProductCategory {
        ProductCategory(rawValue: categoryRaw) ?? .other
    }
}

public extension ShoppingTripAttributes.ContentState {
    /// ActivityKit caps the payload at 4 KB; three names keep it far below that.
    static let maxNextItems = 3

    /// The trip reads the same snapshot as the widgets, so both surfaces always agree.
    init(snapshot: WidgetCartSnapshot) {
        self.init(
            cartTitle: snapshot.cartTitle,
            purchasedCount: snapshot.purchasedCount,
            totalCount: snapshot.totalCount,
            nextItems: snapshot.items
                .filter { !$0.isPurchased }
                .prefix(Self.maxNextItems)
                .map { ShoppingTripItem(id: $0.id, name: $0.name, categoryRaw: $0.categoryRaw) },
            accentColorRaw: snapshot.accentColorRaw
        )
    }
}
