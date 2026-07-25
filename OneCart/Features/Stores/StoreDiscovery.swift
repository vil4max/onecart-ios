import CoreLocation
import MapKit
import SwiftUI

struct StoreCatalogRoute: Identifiable, Hashable {
    let title: String
    let systemImage: String
    let url: URL

    var id: String {
        "\(title)|\(url.absoluteString)"
    }

    var isDiscountRoute: Bool {
        systemImage == "tag.fill"
    }

    var containsOnlyDiscountedProducts: Bool {
        guard isDiscountRoute else { return false }
        let path = url.path.lowercased()
        return path.contains("/catalog/economy")
            || path.contains("/custom-categories/promotions")
    }
}

struct StoreBrand: Identifiable, Hashable {
    let id: String
    let name: String
    let shortMark: String
    let colorHex: String
    let searchQuery: String
    let aliases: [String]
    let officialURL: URL?

    static let popular: [StoreBrand] = [
        StoreBrand(
            id: "atb",
            name: "АТБ",
            shortMark: "АТБ",
            colorHex: "#E30613",
            searchQuery: "АТБ-Маркет",
            aliases: ["атб", "атб-маркет", "atb", "atb market"],
            officialURL: URL(string: "https://www.atbmarket.com")
        ),
        StoreBrand(
            id: "silpo",
            name: "Сільпо",
            shortMark: "С",
            colorHex: "#F58220",
            searchQuery: "Сільпо",
            aliases: ["сільпо", "сильпо", "silpo", "silpo food"],
            officialURL: URL(string: "https://silpo.ua")
        ),
        StoreBrand(
            id: "auchan",
            name: "Auchan",
            shortMark: "A",
            colorHex: "#E30613",
            searchQuery: "Auchan",
            aliases: ["auchan", "ашан", "ашан україна", "ашан украина"],
            officialURL: URL(string: "https://auchan.ua")
        ),
        StoreBrand(
            id: "novus",
            name: "NOVUS",
            shortMark: "N",
            colorHex: "#7CB342",
            searchQuery: "NOVUS",
            aliases: ["novus", "новус", "novus supermarket"],
            officialURL: URL(string: "https://novus.ua")
        ),
        StoreBrand(
            id: "varus",
            name: "VARUS",
            shortMark: "V",
            colorHex: "#79B829",
            searchQuery: "VARUS",
            aliases: ["varus", "варус", "varus market"],
            officialURL: URL(string: "https://varus.ua")
        ),
        StoreBrand(
            id: "fora",
            name: "Фора",
            shortMark: "Ф",
            colorHex: "#00B15E",
            searchQuery: "Фора",
            aliases: ["фора", "fora", "fora market"],
            officialURL: URL(string: "https://fora.ua")
        ),
        StoreBrand(
            id: "metro",
            name: "METRO",
            shortMark: "M",
            colorHex: "#003B7A",
            searchQuery: "METRO Cash & Carry",
            aliases: ["metro", "метро", "metro cash & carry", "metro cash and carry"],
            officialURL: URL(string: "https://www.metro.ua")
        ),
    ]

    static func matching(_ storeName: String) -> StoreBrand? {
        let normalizedName = normalize(storeName)
        return popular.first { brand in
            brand.aliases.contains { normalizedName.contains(normalize($0)) }
        }
    }

    var searchQueries: [String] {
        let values = id == "metro" ? [searchQuery] : [searchQuery, name]
        return values.reduce(into: []) { result, value in
            let normalized = Self.normalize(value)
            guard !result.contains(where: { Self.normalize($0) == normalized }) else { return }
            result.append(value)
        }
    }

    var catalogRoutes: [StoreCatalogRoute] {
        let values: [(String, String, String)] = switch id {
        case "atb":
            [
                ("Каталог", "square.grid.2x2", "https://www.atbmarket.com/"),
                ("Акции", "tag.fill", "https://www.atbmarket.com/catalog/economy"),
                (
                    "Для дома",
                    "sparkles",
                    "https://www.atbmarket.com/catalog/308-pobutova-khimiya-ta-neprodovol-chi-tovari"
                ),
            ]
        case "silpo":
            [
                ("Каталог", "square.grid.2x2", "https://silpo.ua/catalog"),
                // Silpo promo landing is behind bot walls; load full catalog and keep
                // only rows with a confirmed old price (see isShowingDiscounts).
                ("Акции", "tag.fill", "https://silpo.ua/catalog"),
                ("Для дома", "sparkles", "https://silpo.ua/category/pobutova-khimiia-4588"),
            ]
        case "auchan":
            [
                ("Каталог", "square.grid.2x2", "https://auchan.zakaz.ua/uk/"),
                ("Акции", "tag.fill", "https://auchan.zakaz.ua/uk/custom-categories/promotions/"),
                ("Для дома", "sparkles", "https://auchan.zakaz.ua/uk/categories/household-chemicals-auchan/"),
            ]
        case "novus":
            [
                ("Каталог", "square.grid.2x2", "https://novus.zakaz.ua/uk/"),
                ("Акции", "tag.fill", "https://novus.zakaz.ua/uk/custom-categories/promotions/"),
                ("Для дома", "sparkles", "https://novus.zakaz.ua/uk/categories/household-chemicals/"),
            ]
        case "varus":
            [
                ("Каталог", "square.grid.2x2", "https://varus.ua/"),
                ("Акции", "tag.fill", "https://varus.ua/price-of-the-week"),
                ("Для дома", "sparkles", "https://varus.ua/pobutova-himiya"),
            ]
        case "fora":
            [
                ("Каталог", "square.grid.2x2", "https://fora.ua/"),
                ("Для дома", "sparkles", "https://fora.ua/category/pobutova-khimiia-2984"),
            ]
        case "metro":
            [
                ("Каталог", "square.grid.2x2", "https://metro.zakaz.ua/uk/"),
                ("Акции", "tag.fill", "https://metro.zakaz.ua/uk/custom-categories/promotions/"),
                ("Для дома", "sparkles", "https://metro.zakaz.ua/uk/categories/chemicals-metro/"),
            ]
        default:
            []
        }

        let routes = values.compactMap { title, image, value -> StoreCatalogRoute? in
            guard let url = URL(string: value) else { return nil }
            return StoreCatalogRoute(title: title, systemImage: image, url: url)
        }
        if !routes.isEmpty { return routes }
        guard let officialURL else { return [] }
        return [StoreCatalogRoute(title: "Сайт", systemImage: "safari", url: officialURL)]
    }

    func catalogURLs(for category: ProductCategory) -> [URL] {
        if id == "atb" {
            let paths: [String] = switch category {
            case .produce:
                ["287-ovochi-ta-frukti"]
            case .dairy:
                ["molocni-produkti-ta-ajca", "siri"]
            case .meat:
                [
                    "maso", "353-riba-i-moreprodukti",
                    "360-kovbasa-i-m-yasni-delikatesi",
                ]
            case .drinks:
                ["294-napoi-bezalkogol-ni", "kava-caj", "292-alkogol-i-tyutyun"]
            case .household:
                // Keep household focused on home chemicals / home goods.
                // Hygiene, cosmetics and pet aisles used to leak unrelated catalog noise.
                [
                    "308-pobutova-khimiya-ta-neprodovol-chi-tovari",
                    "358-tovari-dlya-domu",
                ]
            case .other:
                [
                    "285-bakaliya", "299-konditers-ki-virobi",
                    "325-khlibobulochni-virobi", "322-zamorozheni-produkti",
                    "cipsi-sneki", "339-dityache-kharchuvannya",
                    "415-yapons-ka-kukhnya", "502-kulinariya",
                    "373-tovari-dlya-ditey", "389-kantselyars-ki-tovari",
                    "sertifikati-ta-platizni-kartki", "479-tyutyunovi-virobi",
                ]
            }
            return paths.compactMap { path in
                URL(string: "https://www.atbmarket.com/catalog/\(path)")
            }
        }

        // Silpo: load the official category shelves (not name-guessing on /catalog).
        if id == "silpo" {
            let paths: [String] = switch category {
            case .produce:
                [
                    "frukty-ovochi-4788",
                    "ovochi-4808",
                    "frukty-4791",
                    "sezonni-ovochi-frukty-4789",
                ]
            case .dairy:
                ["molochni-produkty-ta-iaitsia-234", "moloko-253"]
            case .meat:
                [
                    "m-iaso-4411",
                    "kovbasni-vyroby-i-m-iasni-delikatesy-4731",
                ]
            case .drinks:
                ["napoi-52", "alkogol-22"]
            case .household:
                ["pobutova-khimiia-4588"]
            case .other:
                []
            }
            return paths.compactMap { path in
                URL(string: "https://silpo.ua/category/\(path)")
            }
        }

        // Fora category IDs from public sitemap.
        if id == "fora" {
            let paths: [String] = switch category {
            case .produce:
                ["frukty-ovochi-ta-solinnia-2790", "ovochi-2794", "frukty-2797"]
            case .dairy:
                ["molochni-produkty-ta-iaitsia-2656"]
            case .meat:
                ["svizhe-m-iaso-5401", "kovbasy-ta-m-iasni-delikatesy-2738", "ryba-2699"]
            case .drinks:
                ["soky-ta-napoi-2479", "mineralna-i-pytna-voda-3642"]
            case .household:
                ["pobutova-khimiia-2984", "pobutova-khimiia-tovary-dlia-domu-2975"]
            case .other:
                []
            }
            return paths.compactMap { path in
                URL(string: "https://fora.ua/category/\(path)")
            }
        }

        // VARUS uses flat category slugs (verified live).
        if id == "varus" {
            let paths: [String] = switch category {
            case .produce:
                ["ovochi-svizhi", "frukti-svizhi", "frukti-ovochi-gorihi"]
            case .dairy:
                ["molochni-produkti"]
            case .meat:
                ["myasni-virobi-ta-yaycya"]
            case .drinks:
                ["napoi", "bezalkogolni-napoi"]
            case .household:
                ["pobutova-himiya", "own-clean"]
            case .other:
                []
            }
            return paths.compactMap { path in
                URL(string: "https://varus.ua/\(path)")
            }
        }

        let host: String
        let slugs: [String]
        switch (id, category) {
        case ("auchan", .produce):
            host = "auchan.zakaz.ua"
            slugs = ["fruits-and-vegetables-auchan"]
        case ("auchan", .dairy):
            host = "auchan.zakaz.ua"
            slugs = ["dairy-and-eggs-auchan"]
        case ("auchan", .meat):
            host = "auchan.zakaz.ua"
            slugs = ["meat-fish-poultry-auchan", "fish-and-seafood-auchan"]
        case ("auchan", .drinks):
            host = "auchan.zakaz.ua"
            slugs = ["drinks-auchan", "hot-drinks-auchan"]
        case ("auchan", .household):
            host = "auchan.zakaz.ua"
            slugs = [
                "household-chemicals-auchan",
                "interior-and-textiles-auchan",
            ]
        case ("auchan", .other):
            host = "auchan.zakaz.ua"
            slugs = [
                "bakery-auchan", "canned-food-auchan", "frozen-auchan",
                "grocery-and-sweets-auchan", "sauces-and-spices-auchan",
                "sweets-and-snacks-auchan", "crisps-and-snacks-auchan",
                "babies-auchan", "for-animals-auchan", "ready-meals-auchan",
                "kitchenware-auchan", "stationery-auchan", "hobby-auchan",
                "bioproducts-and-diabetic-goods-auchan", "gourmet-auchan",
                "home-appliances-auchan", "world-cuisine-auchan",
                "clothes-and-shoes-auchan",
            ]
        case ("metro", .produce):
            host = "metro.zakaz.ua"
            slugs = ["fruits-and-vegetables-metro"]
        case ("metro", .dairy):
            host = "metro.zakaz.ua"
            slugs = ["dairy-and-eggs-metro"]
        case ("metro", .meat):
            host = "metro.zakaz.ua"
            slugs = ["meat-fish-poultry-metro", "fish-and-seafood-metro"]
        case ("metro", .drinks):
            host = "metro.zakaz.ua"
            slugs = ["drinks-metro", "hot-drinks-metro"]
        case ("metro", .household):
            host = "metro.zakaz.ua"
            slugs = [
                "chemicals-metro",
                "household-goods-metro",
                "home-interior-and-textiles-metro",
            ]
        case ("metro", .other):
            host = "metro.zakaz.ua"
            slugs = [
                "bakery-metro", "canned-food-oil-vinegar-metro", "frozen-metro",
                "packets-cereals-metro", "sauces-and-spices-metro",
                "snacks-and-sweets-metro", "crisps-and-snacks-metro",
                "babies-metro", "for-animals-metro", "kitchenware-metro",
                "stationery-metro", "hobby-and-rest-metro",
                "health-and-lifestyle-metro",
            ]
        case ("novus", .produce):
            host = "novus.zakaz.ua"
            slugs = ["fruits-and-vegetables"]
        case ("novus", .dairy):
            host = "novus.zakaz.ua"
            slugs = ["dairy-and-eggs"]
        case ("novus", .meat):
            host = "novus.zakaz.ua"
            slugs = ["meat-fish-poultry", "fish-and-seafood-novus"]
        case ("novus", .drinks):
            host = "novus.zakaz.ua"
            slugs = ["drinks", "hot-drinks-novus"]
        case ("novus", .household):
            host = "novus.zakaz.ua"
            slugs = [
                "household-chemicals",
                "household-and-cleaning",
                "interior-and-textiles-novus",
            ]
        case ("novus", .other):
            host = "novus.zakaz.ua"
            slugs = [
                "bakery", "tins-jars-cooking", "frozen", "packets-cereals",
                "sauces-and-spices-novus", "snacks-and-sweets",
                "crisps-and-snacks", "babies", "for-animals", "ready-meals",
                "kitchenware", "stationery", "hobby",
                "health-and-lifestyle-novus", "clothes-and-shoes-novus",
            ]
        default:
            return []
        }
        return slugs.compactMap { slug in
            URL(string: "https://\(host)/uk/categories/\(slug)/")
        }
    }

    func catalogURL(for category: ProductCategory) -> URL? {
        catalogURLs(for: category).first
    }

    var completeCatalogURLs: [URL] {
        ProductCategory.allCases.flatMap(catalogURLs(for:))
    }

    /// Maps a loaded store page back to our product category (authoritative aisle tag).
    func productCategory(forCatalogURL url: URL?) -> ProductCategory? {
        guard let url else { return nil }
        let path = url.path.lowercased()
        // Prefer longest path match so nested produce sub-aisles win over generic catalog.
        var best: (ProductCategory, Int)?
        for category in ProductCategory.allCases {
            for candidate in catalogURLs(for: category) {
                let candidatePath = candidate.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard !candidatePath.isEmpty else { continue }
                let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if normalizedPath == candidatePath
                    || normalizedPath.hasPrefix(candidatePath + "/")
                    || normalizedPath.contains("/" + candidatePath)
                    || normalizedPath.hasSuffix(candidatePath)
                {
                    let score = candidatePath.count
                    if best == nil || score > best!.1 {
                        best = (category, score)
                    }
                }
            }
        }
        if let best { return best.0 }

        // Named routes that are not category-complete lists.
        if path.contains("economy")
            || path.contains("promotion")
            || path.contains("promotions")
            || path.contains("price-of-the-week")
            || path.contains("rasprodazha")
        {
            return nil
        }
        if path.contains("pobutova") || path.contains("household") || path.contains("own-clean")
            || path.contains("chemicals")
        {
            return .household
        }
        return nil
    }

    func acceptsCatalogURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let allowedHosts = Set(
            (catalogRoutes.map(\.url) + completeCatalogURLs).compactMap { $0.host?.lowercased() }
        )
        return allowedHosts.contains { allowed in
            host == allowed || host.hasSuffix(".\(allowed)")
        }
    }

    func matches(mapItemName: String?) -> Bool {
        guard let mapItemName else { return false }
        let normalizedName = Self.normalize(mapItemName)
        return aliases.contains { normalizedName.contains(Self.normalize($0)) }
    }

    func draft(for branch: StoreBranch) -> StoreDraft {
        StoreDraft(
            name: name,
            icon: shortMark,
            colorHex: colorHex,
            address: branch.address,
            latitude: branch.coordinate.latitude,
            longitude: branch.coordinate.longitude,
            externalAppURL: officialURL?.absoluteString,
            isPinned: false
        )
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

struct StoreBranch: Identifiable {
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance?

    var id: String {
        String(format: "%.5f:%.5f", coordinate.latitude, coordinate.longitude)
    }

    var formattedDistance: String? {
        guard let distance else { return nil }
        if distance < 1000 {
            return "\(Int(distance.rounded())) м"
        }
        return String(format: "%.1f км", distance / 1000)
    }

    static func deduplicated(_ values: [StoreBranch]) -> [StoreBranch] {
        var addresses = Set<String>()
        var coordinates = Set<String>()
        return values.filter { candidate in
            let addressKey = StoreBrand.normalize(candidate.address)
            let coordinateKey = String(
                format: "%.4f:%.4f",
                candidate.coordinate.latitude,
                candidate.coordinate.longitude
            )
            let hasAddress = candidate.address != "Адрес не указан"
            let isDuplicate = coordinates.contains(coordinateKey)
                || (hasAddress && addresses.contains(addressKey))
            guard !isDuplicate else { return false }
            coordinates.insert(coordinateKey)
            if hasAddress { addresses.insert(addressKey) }
            return true
        }
    }
}

private struct NovusLeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let o = rect.origin
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: o.x + w * 0.50, y: o.y))
        path.addQuadCurve(
            to: CGPoint(x: o.x + w, y: o.y + h * 0.55),
            control: CGPoint(x: o.x + w * 0.92, y: o.y + h * 0.08)
        )
        path.addQuadCurve(
            to: CGPoint(x: o.x + w * 0.50, y: o.y + h),
            control: CGPoint(x: o.x + w * 0.88, y: o.y + h * 0.92)
        )
        path.addQuadCurve(
            to: CGPoint(x: o.x, y: o.y + h * 0.55),
            control: CGPoint(x: o.x + w * 0.12, y: o.y + h * 0.92)
        )
        path.addQuadCurve(
            to: CGPoint(x: o.x + w * 0.50, y: o.y),
            control: CGPoint(x: o.x + w * 0.08, y: o.y + h * 0.08)
        )
        path.closeSubpath()
        return path
    }
}

struct StoreBrandMark: View {
    let storeName: String
    let fallbackIcon: String
    let fallbackColorHex: String
    var size: CGFloat = 44

    private var brand: StoreBrand? {
        StoreBrand.matching(storeName)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(backgroundColor)

            brandArtwork
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.29, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 5, y: 2)
        .accessibilityLabel(storeName)
    }

    private var backgroundColor: Color {
        switch brand?.id {
        case "atb": Color(hex: "#0F2F5C")
        case "silpo": Color(hex: "#4B286D")
        case "auchan": Color(hex: "#FFFDF8")
        case "novus": Color(hex: "#45B759")
        case "varus": Color(hex: "#C8E03A")
        case "fora": Color(hex: "#00B15E")
        case "metro": Color(hex: "#013E7F")
        default: Color(hex: brand?.colorHex ?? fallbackColorHex)
        }
    }

    @ViewBuilder
    private var brandArtwork: some View {
        switch brand?.id {
        case "atb":
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                    .fill(Color.white)
                    .padding(size * 0.07)
                Capsule()
                    .fill(Color(hex: "#FFD338"))
                    .frame(width: size * 0.64, height: max(2.5, size * 0.055))
                    .offset(y: -size * 0.22)
                Text("АТБ")
                    .font(.system(size: size * 0.30, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "#E30613"))
                    .tracking(-0.5)
                // Small yellow price-tag accent
                Circle()
                    .fill(Color(hex: "#FFD338"))
                    .frame(width: size * 0.11, height: size * 0.11)
                    .overlay(
                        Circle()
                            .fill(Color(hex: "#0F2F5C"))
                            .frame(width: size * 0.035, height: size * 0.035)
                    )
                    .offset(x: size * 0.30, y: -size * 0.28)
            }
        case "silpo":
            // Official orange «Сільпо» spiral wordmark on purple tile
            Image("StoreMarkSilpo")
                .resizable()
                .scaledToFit()
                .padding(size * 0.05)
        case "auchan":
            // Official A-bird; green eye ring is the OneCart twist
            Image("StoreMarkAuchan")
                .resizable()
                .scaledToFit()
                .padding(size * 0.10)
        case "novus":
            ZStack {
                Text("N")
                    .font(.system(size: size * 0.48, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .offset(x: -size * 0.04)
                NovusLeafShape()
                    .fill(Color(hex: "#F6D64A"))
                    .frame(width: size * 0.20, height: size * 0.24)
                    .rotationEffect(.degrees(18))
                    .offset(x: size * 0.26, y: -size * 0.22)
            }
        case "varus":
            // Official Varus flower on brand lime
            Image("StoreMarkVarus")
                .resizable()
                .scaledToFit()
                .padding(size * 0.12)
        case "fora":
            // Official basket only (transparent PNG); tile green comes from backgroundColor
            Image("StoreMarkFora")
                .resizable()
                .scaledToFit()
                .padding(size * 0.12)
        case "metro":
            ZStack {
                Capsule()
                    .fill(Color(hex: "#FFF100"))
                    .frame(width: size * 0.72, height: max(2, size * 0.045))
                    .offset(y: -size * 0.28)
                Text("METRO")
                    .font(.system(size: size * 0.195, weight: .black, design: .default))
                    .foregroundColor(Color(hex: "#FFF100"))
                    .tracking(-size * 0.012)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                    .padding(.horizontal, size * 0.08)
                Capsule()
                    .fill(Color(hex: "#FFF100"))
                    .frame(width: size * 0.72, height: max(2, size * 0.045))
                    .offset(y: size * 0.28)
            }
        default:
            Text(brand?.shortMark ?? fallbackIcon)
                .font(.system(size: size * 0.36, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .padding(.horizontal, size * 0.08)
        }
    }
}

struct StoreLocatorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let brand: StoreBrand
    let onAdded: () -> Void

    @StateObject private var locator: StoreLocatorModel
    @State private var selectedBranchID: String?

    init(brand: StoreBrand, onAdded: @escaping () -> Void = {}) {
        self.brand = brand
        self.onAdded = onAdded
        _locator = StateObject(wrappedValue: StoreLocatorModel(brand: brand))
    }

    private var selectedBranch: StoreBranch? {
        locator.branches.first { $0.id == selectedBranchID }
    }

    var body: some View {
        VStack(spacing: 0) {
            map

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if locator.isSearching {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(locator.statusText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                if locator.branches.isEmpty, !locator.isSearching {
                    EmptyCard(
                        image: "map",
                        title: "Выберите область",
                        message: "Передвиньте карту к нужному району и запустите поиск."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(locator.branches) { branch in
                                branchRow(branch)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(OneCartPalette.background.ignoresSafeArea())
        .navigationTitle(brand.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let selectedBranch {
                Button {
                    add(selectedBranch)
                } label: {
                    Label("Добавить эту точку", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .background(.ultraThinMaterial)
                .disabled(model.isBusy)
            }
        }
        .onAppear {
            locator.start()
        }
    }

    private var map: some View {
        Map(
            coordinateRegion: $locator.region,
            interactionModes: .all,
            showsUserLocation: locator.showsUserLocation,
            annotationItems: locator.branches
        ) { branch in
            MapAnnotation(coordinate: branch.coordinate) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedBranchID = branch.id
                    }
                } label: {
                    StoreBrandMark(
                        storeName: brand.name,
                        fallbackIcon: brand.shortMark,
                        fallbackColorHex: brand.colorHex,
                        size: selectedBranchID == branch.id ? 42 : 34
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 270)
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 8) {
                Button {
                    locator.requestCurrentLocation()
                } label: {
                    Image(systemName: "location.fill")
                        .frame(width: 38, height: 38)
                }

                Button {
                    locator.searchVisibleRegion()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 38, height: 38)
                }
            }
            .buttonStyle(.bordered)
            .padding(12)
        }
    }

    private func branchRow(_ branch: StoreBranch) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedBranchID = branch.id
                locator.region.center = branch.coordinate
            }
        } label: {
            HStack(spacing: 11) {
                StoreBrandMark(
                    storeName: brand.name,
                    fallbackIcon: brand.shortMark,
                    fallbackColorHex: brand.colorHex,
                    size: 42
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(branch.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(branch.address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)

                if let distance = branch.formattedDistance {
                    Text(distance)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }

                Image(systemName: selectedBranchID == branch.id ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedBranchID == branch.id ? OneCartPalette.primary : .secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(OneCartPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        selectedBranchID == branch.id
                            ? OneCartPalette.primary.opacity(0.55)
                            : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func add(_ branch: StoreBranch) {
        Task {
            await model.addStore(brand.draft(for: branch))
            onAdded()
            dismiss()
        }
    }
}

struct StoreCatalogSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List(StoreBrand.popular) { brand in
                NavigationLink {
                    StoreLocatorView(brand: brand) {
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 12) {
                        StoreBrandMark(
                            storeName: brand.name,
                            fallbackIcon: brand.shortMark,
                            fallbackColorHex: brand.colorHex,
                            size: 44
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(brand.name)
                                .font(.body.weight(.semibold))
                            Text("Найти ближайшую точку")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Добавить магазин")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
    }
}
