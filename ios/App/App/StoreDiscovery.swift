import CoreLocation
import MapKit
import SwiftUI

struct StoreCatalogRoute: Identifiable, Hashable {
    let title: String
    let systemImage: String
    let url: URL

    var id: String { "\(title)|\(url.absoluteString)" }

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
            colorHex: "#F5A623",
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
        )
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
        let values: [(String, String, String)]
        switch id {
        case "atb":
            values = [
                ("Каталог", "square.grid.2x2", "https://www.atbmarket.com/"),
                ("Акции", "tag.fill", "https://www.atbmarket.com/catalog/economy"),
                ("Для дома", "sparkles", "https://www.atbmarket.com/catalog/308-pobutova-khimiya-ta-neprodovol-chi-tovari"),
            ]
        case "silpo":
            values = [
                ("Каталог", "square.grid.2x2", "https://silpo.ua/catalog"),
                ("Акции", "tag.fill", "https://silpo.ua/catalog"),
                ("Для дома", "sparkles", "https://silpo.ua/category/pobutova-khimiia-4588"),
            ]
        case "auchan":
            values = [
                ("Каталог", "square.grid.2x2", "https://auchan.zakaz.ua/uk/"),
                ("Акции", "tag.fill", "https://auchan.zakaz.ua/uk/custom-categories/promotions/"),
                ("Для дома", "sparkles", "https://auchan.zakaz.ua/uk/categories/household-chemicals-auchan/"),
            ]
        case "novus":
            values = [
                ("Каталог", "square.grid.2x2", "https://novus.zakaz.ua/uk/"),
                ("Акции", "tag.fill", "https://novus.zakaz.ua/uk/custom-categories/promotions/"),
                ("Для дома", "sparkles", "https://novus.zakaz.ua/uk/categories/household-chemicals/"),
            ]
        case "varus":
            values = [
                ("Каталог", "square.grid.2x2", "https://varus.ua/"),
                ("Для дома", "sparkles", "https://varus.ua/own-clean"),
            ]
        case "fora":
            values = [
                ("Каталог", "square.grid.2x2", "https://fora.ua/"),
            ]
        case "metro":
            values = [
                ("Каталог", "square.grid.2x2", "https://metro.zakaz.ua/uk/"),
                ("Акции", "tag.fill", "https://metro.zakaz.ua/uk/custom-categories/promotions/"),
                ("Для дома", "sparkles", "https://metro.zakaz.ua/uk/categories/chemicals-metro/"),
            ]
        default:
            values = []
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
            let paths: [String]
            switch category {
            case .produce:
                paths = ["287-ovochi-ta-frukti"]
            case .dairy:
                paths = ["molocni-produkti-ta-ajca", "siri"]
            case .meat:
                paths = [
                    "maso", "353-riba-i-moreprodukti",
                    "360-kovbasa-i-m-yasni-delikatesi",
                ]
            case .drinks:
                paths = ["294-napoi-bezalkogol-ni", "kava-caj", "292-alkogol-i-tyutyun"]
            case .household:
                paths = [
                    "308-pobutova-khimiya-ta-neprodovol-chi-tovari",
                    "290-gigiena-i-kosmetika", "358-tovari-dlya-domu",
                    "436-tovari-dlya-tvarin",
                ]
            case .other:
                paths = [
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
                "household-and-pets-care-auchan",
                "personal-hygiene-auchan",
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
                "chemicals-metro", "household-goods-metro",
                "personal-hygiene-metro", "home-interior-and-textiles-metro",
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
                "household-chemicals", "household-and-cleaning",
                "personal-hygiene", "interior-and-textiles-novus",
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

    func acceptsCatalogURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return catalogRoutes.contains { route in
            guard let allowedHost = route.url.host?.lowercased() else { return false }
            return host == allowedHost || host.hasSuffix(".\(allowedHost)")
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
        if distance < 1_000 {
            return "\(Int(distance.rounded())) м"
        }
        return String(format: "%.1f км", distance / 1_000)
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

final class StoreLocatorModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 50.4501, longitude: 30.5234),
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
    )
    @Published private(set) var branches: [StoreBranch] = []
    @Published private(set) var isSearching = false
    @Published private(set) var statusText = "Определяем ваше местоположение…"
    @Published private(set) var showsUserLocation = false

    private let brand: StoreBrand
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var localSearch: MKLocalSearch?
    private var pendingSearchRequests: [MKLocalSearch.Request] = []
    private var accumulatedMapItems: [MKMapItem] = []
    private var firstSearchError: Error?
    private var searchDistanceOrigin: CLLocation?
    private var searchSession = UUID()
    private var hasStarted = false
    private var lastHandledAuthorizationStatus: CLAuthorizationStatus?

    init(brand: StoreBrand) {
        self.brand = brand
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    deinit {
        localSearch?.cancel()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        handleAuthorizationChange()
    }

    private func handleAuthorizationChange() {
        let authorizationStatus = locationManager.authorizationStatus
        guard authorizationStatus != lastHandledAuthorizationStatus else { return }
        lastHandledAuthorizationStatus = authorizationStatus

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            showsUserLocation = true
            statusText = "Ищем ближайшие точки \(brand.name)…"
            locationManager.requestLocation()
        case .notDetermined:
            statusText = "Разрешите геолокацию, чтобы найти ближайший магазин."
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            showsUserLocation = false
            statusText = "Геолокация выключена. Переместите карту и нажмите «Искать здесь»."
        @unknown default:
            statusText = "Не удалось определить доступ к геолокации."
        }
    }

    func requestCurrentLocation() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            statusText = "Обновляем местоположение…"
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            statusText = "Разрешите геолокацию для OneCart в настройках iPhone."
        @unknown default:
            break
        }
    }

    func searchVisibleRegion() {
        search(near: region.center, origin: currentLocation)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.hasStarted else { return }
            self.handleAuthorizationChange()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            currentLocation = location
            showsUserLocation = true
            region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.10)
            )
            search(near: location.coordinate, origin: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.statusText = "Не удалось получить геопозицию. Можно выбрать область на карте вручную."
        }
    }

    private func search(near coordinate: CLLocationCoordinate2D, origin: CLLocation?) {
        localSearch?.cancel()
        localSearch = nil
        let session = UUID()
        searchSession = session
        isSearching = true
        branches = []
        statusText = "Ищем \(brand.name) в этой области…"

        let regions = Self.searchRegions(around: coordinate, visibleSpan: region.span)
        var requests = regions.map { region -> MKLocalSearch.Request in
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = brand.searchQuery
            request.region = region
            return request
        }
        requests.append(contentsOf: brand.searchQueries.dropFirst().prefix(2).map { query in
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = regions[0]
            return request
        })

        pendingSearchRequests = requests
        accumulatedMapItems = []
        firstSearchError = nil
        searchDistanceOrigin = origin
            ?? CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        runNextSearch(in: session)
    }

    private func runNextSearch(in session: UUID) {
        guard searchSession == session else { return }
        guard !pendingSearchRequests.isEmpty else {
            finishSearch(in: session)
            return
        }

        let request = pendingSearchRequests.removeFirst()
        let search = MKLocalSearch(request: request)
        localSearch = search
        search.start { [weak self] response, error in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.searchSession == session else { return }
                self.accumulatedMapItems.append(contentsOf: response?.mapItems ?? [])
                if self.firstSearchError == nil {
                    self.firstSearchError = error
                }
                self.publishAccumulatedBranches()

                if self.pendingSearchRequests.isEmpty {
                    self.finishSearch(in: session)
                } else {
                    self.statusText = self.branches.isEmpty
                        ? "Проверяем соседние районы…"
                        : "Найдено точек: \(self.branches.count) · уточняем район…"
                    self.runNextSearch(in: session)
                }
            }
        }
    }

    private func publishAccumulatedBranches() {
        guard let searchDistanceOrigin else { return }
        branches = StoreBranch.deduplicated(
            accumulatedMapItems.map { item in
                let itemLocation = CLLocation(
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
                return StoreBranch(
                    name: brand.name,
                    address: Self.address(for: item.placemark),
                    coordinate: item.placemark.coordinate,
                    distance: searchDistanceOrigin.distance(from: itemLocation)
                )
            }
        )
        .sorted {
            ($0.distance ?? .greatestFiniteMagnitude) <
                ($1.distance ?? .greatestFiniteMagnitude)
        }
    }

    private func finishSearch(in session: UUID) {
        guard searchSession == session else { return }
        localSearch = nil
        pendingSearchRequests = []
        isSearching = false

        if branches.isEmpty, let firstSearchError {
            statusText = "Поиск не выполнен: \(firstSearchError.localizedDescription)"
        } else {
            statusText = branches.isEmpty
                ? "Точек \(brand.name) в этой области не найдено."
                : "Найдено точек: \(branches.count)"
        }
    }

    private static func searchRegions(
        around center: CLLocationCoordinate2D,
        visibleSpan: MKCoordinateSpan
    ) -> [MKCoordinateRegion] {
        let latitudeDelta = min(max(visibleSpan.latitudeDelta, 0.12), 0.34)
        let longitudeDelta = min(max(visibleSpan.longitudeDelta, 0.12), 0.34)
        let tileSpan = MKCoordinateSpan(
            latitudeDelta: latitudeDelta * 0.64,
            longitudeDelta: longitudeDelta * 0.64
        )
        let latitudeOffset = latitudeDelta * 0.28
        let longitudeOffset = longitudeDelta * 0.28
        let centers = [
            center,
            CLLocationCoordinate2D(latitude: center.latitude + latitudeOffset, longitude: center.longitude),
            CLLocationCoordinate2D(latitude: center.latitude - latitudeOffset, longitude: center.longitude),
            CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude + longitudeOffset),
            CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude - longitudeOffset),
        ]
        return centers.map { MKCoordinateRegion(center: $0, span: tileSpan) }
    }

    private static func address(for placemark: MKPlacemark) -> String {
        let street = [placemark.thoroughfare, placemark.subThoroughfare]
            .compactMap { $0 }
            .joined(separator: ", ")
        var parts: [String] = []
        if let locality = placemark.locality, !locality.isEmpty {
            parts.append(locality)
        }
        if let subLocality = placemark.subLocality,
           !subLocality.isEmpty,
           !parts.contains(subLocality) {
            parts.append(subLocality)
        }
        if !street.isEmpty {
            parts.append(street)
        }
        return parts.isEmpty ? "Адрес не указан" : parts.joined(separator: " · ")
    }
}

/// Official Fora basket: trapezoid body + peaked handle (red circle lockup).
private struct ForaBasketBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let o = rect.origin
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: o.x + w * 0.12, y: o.y + h * 0.40))
        path.addLine(to: CGPoint(x: o.x + w * 0.22, y: o.y + h * 0.90))
        path.addLine(to: CGPoint(x: o.x + w * 0.78, y: o.y + h * 0.90))
        path.addLine(to: CGPoint(x: o.x + w * 0.88, y: o.y + h * 0.40))
        path.closeSubpath()
        return path
    }
}

private struct ForaBasketHandleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let o = rect.origin
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: o.x + w * 0.28, y: o.y + h * 0.40))
        path.addLine(to: CGPoint(x: o.x + w * 0.50, y: o.y + h * 0.10))
        path.addLine(to: CGPoint(x: o.x + w * 0.72, y: o.y + h * 0.40))
        return path
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
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 5, y: 2)
        .accessibilityLabel(storeName)
    }

    private var backgroundColor: Color {
        switch brand?.id {
        case "atb": return Color(hex: "#0F2F5C")
        case "silpo": return Color(hex: "#4B286D")
        case "auchan": return Color(hex: "#FFFDF8")
        case "novus": return Color(hex: "#45B759")
        case "varus": return Color(hex: "#C8E03A")
        case "fora": return Color(hex: "#1FAF46")
        case "metro": return Color(hex: "#013E7F")
        default: return Color(hex: brand?.colorHex ?? fallbackColorHex)
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
            // Official lockup condensed for a square tile: wordmark + basket badge
            VStack(spacing: size * 0.04) {
                Text("фора")
                    .font(.system(size: size * 0.168, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(-size * 0.004)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                ZStack {
                    Circle()
                        .fill(Color(hex: "#EE4036"))
                    ForaBasketBodyShape()
                        .fill(Color.white)
                        .padding(size * 0.055)
                    ForaBasketHandleShape()
                        .stroke(
                            Color.white,
                            style: StrokeStyle(
                                lineWidth: max(1.6, size * 0.045),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .padding(size * 0.055)
                    HStack(spacing: size * 0.03) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule()
                                .fill(Color(hex: "#EE4036"))
                                .frame(width: max(1.4, size * 0.022), height: size * 0.09)
                        }
                    }
                    .offset(y: size * 0.055)
                }
                .frame(width: size * 0.42, height: size * 0.42)
            }
            .padding(.vertical, size * 0.06)
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

                if locator.branches.isEmpty && !locator.isSearching {
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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
