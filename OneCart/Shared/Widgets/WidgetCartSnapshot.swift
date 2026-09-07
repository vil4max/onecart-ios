import Foundation
import SwiftUI

public enum OneCartAppGroup {
    public static let identifier = "group.com.vil555tim.onecart"
    public static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}

public struct WidgetCartSnapshot: Codable, Sendable, Equatable {
    public let cartTitle: String
    public let totalCount: Int
    public let purchasedCount: Int
    public let isSyncing: Bool
    public let lastUpdated: Date
    public let familyMemberCount: Int
    public let activePartnerName: String?
    public let themeRaw: String?
    public let accentColorRaw: String?
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
        self.items = items
    }

    public var preferredColorScheme: ColorScheme? {
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
        guard let accentColorRaw else {
            if let raw = OneCartAppGroup.defaults?.string(forKey: "onecart.accent-color"),
               let accent = AppAccentColor(rawValue: raw)
            {
                return accent
            }
            return .emerald
        }
        return AppAccentColor(rawValue: accentColorRaw) ?? .emerald
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

    public static let placeholder = WidgetCartSnapshot(
        cartTitle: "Наши покупки",
        totalCount: 7,
        purchasedCount: 3,
        isSyncing: false,
        lastUpdated: Date(),
        familyMemberCount: 1,
        activePartnerName: nil,
        items: [
            WidgetItemSnapshot(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Молоко 3.2%",
                isPurchased: true,
                categoryRaw: ProductCategory.dairyEggs.rawValue,
                subtitle: nil
            ),
            WidgetItemSnapshot(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "Хлеб бородинский",
                isPurchased: false,
                categoryRaw: ProductCategory.bakery.rawValue,
                subtitle: nil
            ),
            WidgetItemSnapshot(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                name: "Яйца С0",
                isPurchased: false,
                categoryRaw: ProductCategory.dairyEggs.rawValue,
                subtitle: nil
            ),
            WidgetItemSnapshot(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                name: "Сыр твердый",
                isPurchased: false,
                categoryRaw: ProductCategory.dairyEggs.rawValue,
                subtitle: nil
            ),
        ]
    )

    public static let empty = WidgetCartSnapshot(
        cartTitle: "OneCart Family",
        totalCount: 0,
        purchasedCount: 0,
        isSyncing: false,
        lastUpdated: Date(),
        familyMemberCount: 1,
        activePartnerName: nil,
        items: []
    )
}

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

    public var symbolName: String {
        ProductCategory(rawValue: categoryRaw)?.symbolName ?? "cart.fill"
    }
}
