import Combine
import CoreLocation
import MapKit

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

    func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self, hasStarted else { return }
            handleAuthorizationChange()
        }
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
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

    func locationManager(_: CLLocationManager, didFailWithError _: Error) {
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
                guard let self, searchSession == session else { return }
                accumulatedMapItems.append(contentsOf: response?.mapItems ?? [])
                if firstSearchError == nil {
                    firstSearchError = error
                }
                publishAccumulatedBranches()

                if pendingSearchRequests.isEmpty {
                    finishSearch(in: session)
                } else {
                    statusText = branches.isEmpty
                        ? "Проверяем соседние районы…"
                        : "Найдено точек: \(branches.count) · уточняем район…"
                    runNextSearch(in: session)
                }
            }
        }
    }

    private func publishAccumulatedBranches() {
        guard let searchDistanceOrigin else { return }
        branches = StoreBranch.deduplicated(
            accumulatedMapItems
                .filter { brand.matches(mapItemName: $0.name) }
                .map { item in
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
           !parts.contains(subLocality)
        {
            parts.append(subLocality)
        }
        if !street.isEmpty {
            parts.append(street)
        }
        return parts.isEmpty ? "Адрес не указан" : parts.joined(separator: " · ")
    }
}
