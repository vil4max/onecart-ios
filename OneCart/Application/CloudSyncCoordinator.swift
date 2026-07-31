import CoreData
import Foundation

@MainActor
protocol CloudSyncHost: AnyObject {
    var account: OneCartAccount? { get }
    var isOnline: Bool { get }
    var syncState: OneCartSyncState { get }

    func applySyncState(_ state: OneCartSyncState)
    func applyLastSyncError(_ message: String?)
    func presentSyncAlert(_ message: String)
    func presentProductionSchemaAlertIfNeeded(_ message: String)
    func softRefreshCartProducts()
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
    private var objectsDidChangeObserver: NSObjectProtocol?
    private var scheduledReloadTask: Task<Void, Never>?
    private var softRefreshTask: Task<Void, Never>?
    private var cloudReloadPending = false
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
        softRefreshTask?.cancel()
        cloudReloadPending = false
        if let remoteChangeObserver {
            NotificationCenter.default.removeObserver(remoteChangeObserver)
            self.remoteChangeObserver = nil
        }
        if let cloudEventObserver {
            NotificationCenter.default.removeObserver(cloudEventObserver)
            self.cloudEventObserver = nil
        }
        if let objectsDidChangeObserver {
            NotificationCenter.default.removeObserver(objectsDidChangeObserver)
            self.objectsDidChangeObserver = nil
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
            Task { @MainActor in
                self?.scheduleSoftProductRefresh()
                self?.scheduleCloudReload()
            }
        }

        objectsDidChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: persistence.container.viewContext,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self, Self.productPurchasedStateChanged(in: notification) else { return }
                self.scheduleSoftProductRefresh(delayNanoseconds: 50_000_000)
            }
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
                        self.scheduleSoftProductRefresh()
                        self.scheduleCloudReload(delayNanoseconds: 150_000_000)
                    }
                }
            }
        }
    }

    func scheduleSoftProductRefresh(delayNanoseconds: UInt64 = 80_000_000) {
        guard host?.account != nil else { return }
        softRefreshTask?.cancel()
        softRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled, let self, let host, host.account != nil else {
                return
            }
            host.softRefreshCartProducts()
        }
    }

    func scheduleCloudReload(delayNanoseconds: UInt64 = 650_000_000) {
        guard host?.account != nil else { return }
        cloudReloadPending = true
        guard scheduledReloadTask == nil else { return }
        scheduledReloadTask = Task { [weak self] in
            defer {
                self?.scheduledReloadTask = nil
            }
            while let self, !Task.isCancelled {
                guard cloudReloadPending else { return }
                cloudReloadPending = false
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                guard !Task.isCancelled else { return }
                if cloudReloadPending {
                    continue
                }
                guard let host, let account = host.account else { return }
                host.softRefreshCartProducts()
                do {
                    try await host.offerSharedCartJoinIfNeeded(for: account)
                } catch {
                    // Keep importing CloudKit changes even if adopt/merge races.
                    host.applySyncState(.failed)
                    host.applyLastSyncError(host.userFacingMessage(for: error))
                }
                await syncCart(reason: .cloudImport)
            }
        }
    }

    private static func productPurchasedStateChanged(in notification: Notification) -> Bool {
        let keys: [String] = [
            NSUpdatedObjectsKey,
            NSRefreshedObjectsKey,
            NSInsertedObjectsKey,
        ]
        for key in keys {
            guard let objects = notification.userInfo?[key] as? Set<NSManagedObject> else {
                continue
            }
            for object in objects {
                guard object is ProductEntity else { continue }
                if key == NSInsertedObjectsKey || key == NSRefreshedObjectsKey {
                    return true
                }
                let changed = object.changedValuesForCurrentEvent()
                if changed["isPurchased"] != nil
                    || changed["purchasedAt"] != nil
                    || changed["purchasedByName"] != nil
                    || changed["createdByName"] != nil
                {
                    return true
                }
            }
        }
        return false
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
