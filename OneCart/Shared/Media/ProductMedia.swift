import SwiftUI

struct OfficialProductMedia: Equatable {
    let imageURL: URL
    let sourceURL: URL
    let sourceName: String

    static func resolve(product: ProductEntity) -> OfficialProductMedia? {
        if let imageURL = product.imageURLValue {
            return OfficialProductMedia(
                imageURL: imageURL,
                sourceURL: product.sourceURLValue ?? imageURL,
                sourceName: product.store?.displayName ?? "официального каталога"
            )
        }
        return resolve(
            productName: product.displayName,
            storeName: product.store?.displayName
        )
    }

    static func resolve(historyItem: HistoryItemEntity) -> OfficialProductMedia? {
        if let imageURL = historyItem.imageURLValue {
            return OfficialProductMedia(
                imageURL: imageURL,
                sourceURL: historyItem.sourceURLValue ?? imageURL,
                sourceName: historyItem.storeName
                    ?? historyItem.history?.store?.displayName
                    ?? "каталога"
            )
        }
        return resolve(
            productName: historyItem.displayName,
            storeName: historyItem.storeName ?? historyItem.history?.store?.displayName
        )
    }

    static func resolve(productName: String, storeName: String?) -> OfficialProductMedia? {
        let normalizedProduct = normalize(productName)
        let normalizedStore = normalize(storeName ?? "")

        return rules.first { rule in
            let productMatches = rule.keywords.contains {
                normalizedProduct.contains(normalize($0))
            }
            guard productMatches else { return false }

            if normalizedStore.isEmpty {
                return true
            }

            return rule.storeAliases.contains {
                normalizedStore.contains(normalize($0))
            }
        }?.media
    }

    private struct Rule {
        let keywords: [String]
        let storeAliases: [String]
        let media: OfficialProductMedia
    }

    private static let rules: [Rule] = [
        Rule(
            keywords: ["банан", "banana"],
            storeAliases: ["атб", "atb"],
            media: OfficialProductMedia(
                imageURL: URL(
                    string: "https://src.zakaz.atbmarket.com/cache/photos/18797/catalog_product_gal_mob_18797.jpg"
                )!,
                sourceURL: URL(string: "https://www.atbmarket.com/product/banan-1-gat")!,
                sourceName: "АТБ"
            )
        ),
        Rule(
            keywords: ["яйц", "яєч", "egg"],
            storeAliases: ["атб", "atb"],
            media: OfficialProductMedia(
                imageURL: URL(
                    string: "https://src.zakaz.atbmarket.com/cache/photos/31637/catalog_product_gal_mob_31637.jpg"
                )!,
                sourceURL: URL(string: "https://www.atbmarket.com/product/ajce-kurace-10-st-asensvit-1-kategorii-fas")!,
                sourceName: "АТБ"
            )
        ),
        Rule(
            keywords: ["молок", "milk"],
            storeAliases: ["сільпо", "сильпо", "silpo"],
            media: OfficialProductMedia(
                imageURL: URL(
                    string: "https://images.silpo.ua/v2/products/744x744/webp/f823d548-8855-41ec-973c-ec846b395477.png"
                )!,
                sourceURL: URL(
                    string: "https://silpo.ua/product/moloko-ultrapasteryzovane-na-zdorov-ia-bezlaktozne-2-5-857563"
                )!,
                sourceName: "Сільпо"
            )
        ),
        Rule(
            keywords: ["хлеб", "хліб", "bread"],
            storeAliases: ["сільпо", "сильпо", "silpo"],
            media: OfficialProductMedia(
                imageURL: URL(
                    string: "https://images.silpo.ua/v2/products/744x744/webp/f48ceed7-015a-415b-a340-d1101d998261.png"
                )!,
                sourceURL: URL(string: "https://silpo.ua/product/khlib-dobryi-tsilnozernovyi-829906")!,
                sourceName: "Сільпо"
            )
        ),
        Rule(
            keywords: ["сыр", "сир", "cheese"],
            storeAliases: ["сільпо", "сильпо", "silpo"],
            media: OfficialProductMedia(
                imageURL: URL(
                    string: "https://images.silpo.ua/v2/products/744x744/webp/b750bc2a-fde6-4d89-b703-939588c84c94.png"
                )!,
                sourceURL: URL(
                    string: "https://silpo.ua/product/syr-gouda-napivtverdyi-z-korov-iachogo-moloka-narizanyi-skybkamy-48-1009450"
                )!,
                sourceName: "Сільпо"
            )
        ),
        Rule(
            keywords: ["вода", "water"],
            storeAliases: ["auchan", "ашан"],
            media: OfficialProductMedia(
                imageURL: URL(
                    string: "https://img3.zakaz.ua/89b4d9093f374877b5099687d2bf590f/1756745262-s350x350.jpg"
                )!,
                sourceURL: URL(string: "https://auchan.zakaz.ua/uk/products/voda-kozhen-den-6000ml--04823090107840/")!,
                sourceName: "Auchan"
            )
        ),
    ]

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

struct OfficialProductThumbnail: View {
    let media: OfficialProductMedia?
    let category: ProductCategory
    var isPurchased = false
    var size: CGFloat = 42

    private var displayURL: URL? {
        guard let media else { return nil }
        return OfficialCatalogProductQuality.upgradedImageURL(media.imageURL) ?? media.imageURL
    }

    var body: some View {
        Group {
            if let displayURL {
                AsyncImage(url: displayURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            // Fit keeps packaging edges; fill was cropping and stacking white frames.
                            .scaledToFit()
                            .padding(size * 0.06)
                    case .failure:
                        fallback
                    case .empty:
                        ZStack {
                            fallback
                            ProgressView()
                                .controlSize(.mini)
                        }
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        // Unified studio card: white plate for every store photo (packshots already on white).
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .stroke(Color(.separator).opacity(0.35), lineWidth: 0.5)
        )
        .saturation(isPurchased ? 0.2 : 1)
        .opacity(isPurchased ? 0.68 : 1)
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [
                    OneCartPalette.primary.opacity(0.13),
                    OneCartPalette.primary.opacity(0.04),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: category.systemImage)
                .font(.system(size: size * 0.37, weight: .semibold))
                .foregroundColor(OneCartPalette.primary.opacity(0.78))
        }
    }
}

extension ProductCategory {
    var systemImage: String {
        switch self {
        case .produce:
            "leaf.fill"
        case .dairy:
            "drop.fill"
        case .meat:
            "fork.knife"
        case .drinks:
            "waterbottle.fill"
        case .household:
            "sparkles"
        case .other:
            "shippingbox.fill"
        }
    }
}
