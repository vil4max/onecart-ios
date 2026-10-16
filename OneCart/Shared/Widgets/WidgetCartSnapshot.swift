import Foundation

public struct WidgetCartSnapshot: Codable, Sendable, Equatable {
    public let cartTitle: String
    public let totalCount: Int
    public let purchasedCount: Int
    public let isSyncing: Bool
    public let lastUpdated: Date
    public let familyMemberCount: Int
    public let activePartnerName: String?
    public let themeRaw: String?
    public private(set) var accentColorRaw: String?
    public let accountID: UUID?
    public let familyID: UUID?
    public let items: [WidgetItemSnapshot]

    public init(
        cartTitle: String,
        totalCount: Int,
        purchasedCount: Int,
        isSyncing: Bool,
        lastUpdated: Date,
        familyMemberCount: Int,
        activePartnerName: String? = nil,
        themeRaw: String? = nil,
        accentColorRaw: String? = nil,
        accountID: UUID? = nil,
        familyID: UUID? = nil,
        items: [WidgetItemSnapshot]
    ) {
        self.cartTitle = cartTitle
        self.totalCount = totalCount
        self.purchasedCount = purchasedCount
        self.isSyncing = isSyncing
        self.lastUpdated = lastUpdated
        self.familyMemberCount = familyMemberCount
        self.activePartnerName = activePartnerName
        self.themeRaw = themeRaw
        self.accentColorRaw = accentColorRaw
        self.accountID = accountID
        self.familyID = familyID
        self.items = items
    }

    /// Older builds stored a forced appearance; current builds write "system", so the widget
    /// follows the device. Each target maps this to its own UI type.
    public var forcedAppearance: WidgetAppearance? {
        switch themeRaw {
        case "dark":
            .dark
        case "light":
            .light
        default:
            nil
        }
    }

    public var accentColor: AppAccentColor {
        AppAccentColor(storedRawValue: accentColorRaw)
    }

    /// A snapshot without an accent (written by an older build, or the built-in placeholder
    /// and empty snapshots) takes the accent the app last stored, then falls back to emerald.
    /// The reader passes the stored value in, so the value never reads shared storage itself.
    public func fillingMissingAccent(with storedAccentRaw: String?) -> WidgetCartSnapshot {
        guard accentColorRaw == nil,
            let storedAccentRaw,
            AppAccentColor(rawValue: storedAccentRaw) != nil
        else {
            return self
        }
        var filled = self
        filled.accentColorRaw = storedAccentRaw
        return filled
    }

    public var remainingCount: Int {
        max(0, totalCount - purchasedCount)
    }

    public var progress: Double {
        totalCount > 0 ? Double(purchasedCount) / Double(totalCount) : 0.0
    }

    public var isEmpty: Bool {
        totalCount == 0
    }

    public var isAllPurchased: Bool {
        totalCount > 0 && purchasedCount >= totalCount
    }

    /// Stable IDs for the gallery sample, so previews and placeholders do not churn identity.
    private static func sampleItemID(_ index: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, index))
    }

    public static let placeholder = WidgetCartSnapshot(
        cartTitle: String(localized: "widget.sample.cart_title"),
        totalCount: 7,
        purchasedCount: 3,
        isSyncing: false,
        lastUpdated: Date(),
        familyMemberCount: 1,
        activePartnerName: nil,
        items: [
            WidgetItemSnapshot(
                id: sampleItemID(1),
                name: String(localized: "widget.sample.milk"),
                isPurchased: true,
                categoryRaw: ProductCategory.dairyEggs.rawValue,
                subtitle: nil
            ),
            WidgetItemSnapshot(
                id: sampleItemID(2),
                name: String(localized: "widget.sample.bread"),
                isPurchased: false,
                categoryRaw: ProductCategory.bakery.rawValue,
                subtitle: nil
            ),
            WidgetItemSnapshot(
                id: sampleItemID(3),
                name: String(localized: "widget.sample.eggs"),
                isPurchased: false,
                categoryRaw: ProductCategory.dairyEggs.rawValue,
                subtitle: nil
            ),
            WidgetItemSnapshot(
                id: sampleItemID(4),
                name: String(localized: "widget.sample.cheese"),
                isPurchased: false,
                categoryRaw: ProductCategory.dairyEggs.rawValue,
                subtitle: nil
            ),
        ]
    )

    public static let empty = WidgetCartSnapshot(
        cartTitle: String(localized: "common.app_name"),
        totalCount: 0,
        purchasedCount: 0,
        isSyncing: false,
        lastUpdated: Date(),
        familyMemberCount: 1,
        activePartnerName: nil,
        items: []
    )
}

public enum WidgetAppearance: Sendable, Equatable {
    case light
    case dark
}
