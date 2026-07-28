import CoreData
import Foundation
import Network

@MainActor
protocol CloudSyncHost: AnyObject {
    var account: OneCartAccount? { get }
    var isOnline: Bool { get }
    var syncState: OneCartSyncState { get }

    func applySyncState(_ state: OneCartSyncState)
    func applyLastSyncError(_ message: String?)
    func presentSyncAlert(_ message: String)
    func presentProductionSchemaAlertIfNeeded(_ message: String)
    func refreshFamilyMetadata(showErrors: Bool) async
    func offerSharedCartJoinIfNeeded(for account: OneCartAccount) async throws
    func userFacingMessage(for error: Error) -> String
    func applyConnectivityOnline(_ isOnline: Bool)
}

@MainActor
final class CloudSyncCoordinator {
    private let persistence: PersistenceController
    private let cartSync: CartSyncService
    private let connectivity = ConnectivityMonitor()
    private weak var host: CloudSyncHost?

    private var remoteChangeObserver: NSObjectProtocol?
    private var cloudEventObserver: NSObjectProtocol?
    private var scheduledReloadTask: Task<Void, Never>?
    private var didPresentProductionSchemaAlert = false

    init(persistence: PersistenceController, cartSync: CartSyncService) {
        self.persistence = persistence
        self.cartSync = cartSync
    }

    func bind(host: CloudSyncHost) {
        self.host = host
    }

    func cancel() {
        scheduledReloadTask?.cancel()
        if let remoteChangeObserver {
            NotificationCenter.default.removeObserver(remoteChangeObserver)
            self.remoteChangeObserver = nil
        }
        if let cloudEventObserver {
            NotificationCenter.default.removeObserver(cloudEventObserver)
            self.cloudEventObserver = nil
        }
        connectivity.stop()
    }

    func syncCart(reason: CartSyncReason) async {
        guard let host else { return }
        let previousState = host.syncState
        let outcome = await cartSync.syncCart(reason: reason)
        switch outcome {
        case .succeeded:
            await host.refreshFamilyMetadata(showErrors: false)
            host.applySyncState(host.isOnline ? .synchronized : .offline)
            host.applyLastSyncError(nil)
        case .skippedDebounce:
            break
        case let .failed(message):
            host.applyLastSyncError(message)
            host.applySyncState(.failed)
            switch reason {
            case .pull:
                host.presentSyncAlert(message)
            case .foreground where previousState == .synchronized || previousState == .syncing:
                host.presentSyncAlert(message)
            case .foreground, .appear, .cloudImport, .afterToggle, .afterMutation:
                break
            }
        }
    }

    func installCloudObservers() {
        guard remoteChangeObserver == nil, cloudEventObserver == nil else { return }
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleCloudReload() }
        }

        cloudEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: persistence.container,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self,
                      let host = self.host,
                      let event = notification.userInfo?[
                          NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                      ] as? NSPersistentCloudKitContainer.Event else { return }
                if event.endDate == nil {
                    host.applySyncState(.syncing)
                } else if let error = event.error {
                    host.applySyncState(
                        CloudKitUserFacingError.isNetworkError(error) ? .offline : .failed
                    )
                    let message = host.userFacingMessage(for: error)
                    host.applyLastSyncError(message)
                    if CloudKitUserFacingError.isProductionSchemaFailure(error) {
                        self.presentProductionSchemaAlertIfNeeded(message)
                    }
                } else {
                    host.applySyncState(host.isOnline ? .synchronized : .offline)
                    host.applyLastSyncError(nil)
                    if CloudKitProductReloadPolicy.shouldReloadProductsAfterEvent(
                        type: event.type,
                        ended: true,
                        error: nil
                    ) {
                        CartSyncLog.cart.info("cloudKit import finished; scheduling cart sync")
                        self.scheduleCloudReload(delayNanoseconds: 150_000_000)
                    }
                }
            }
        }
    }

    func scheduleCloudReload(delayNanoseconds: UInt64 = 650_000_000) {
        guard let host, host.account != nil else { return }
        scheduledReloadTask?.cancel()
        scheduledReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled, let self, let host = self.host, let account = host.account else {
                return
            }
            do {
                try await host.offerSharedCartJoinIfNeeded(for: account)
                await self.syncCart(reason: .cloudImport)
            } catch {
                host.applySyncState(.failed)
                host.applyLastSyncError(host.userFacingMessage(for: error))
            }
        }
    }

    func installConnectivityMonitor() {
        connectivity.onChange = { [weak self] isOnline in
            Task { @MainActor in
                guard let self, let host = self.host else { return }
                let wasOnline = host.isOnline
                host.applyConnectivityOnline(isOnline)
                if !isOnline {
                    host.applySyncState(.offline)
                } else if !wasOnline, host.account != nil {
                    host.applySyncState(.syncing)
                    self.scheduleCloudReload(delayNanoseconds: 150_000_000)
                }
            }
        }
        connectivity.start()
    }

    func presentProductionSchemaAlertIfNeeded(_ message: String) {
        guard !didPresentProductionSchemaAlert else { return }
        didPresentProductionSchemaAlert = true
        host?.presentSyncAlert(message)
    }
}

final class ConnectivityMonitor {
    var onChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.vil55tim.onecart.connectivity")
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onChange?(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    func stop() {
        guard running else { return }
        running = false
        monitor.cancel()
    }
}
