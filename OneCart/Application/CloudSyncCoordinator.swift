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
    func drainWidgetPendingToggles() async
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
    /// Identifies the task that owns `scheduledReloadTask`; a cancelled or replaced task must not
    /// clear the slot of its successor when its cleanup finally runs.
    private var scheduledReloadGeneration = 0
    /// Shortest delay requested since the reload loop last went to sleep; nil means nothing pending.
    private var pendingReloadDelay: UInt64?
    /// Delay the reload loop is currently sleeping on; nil while it is syncing.
    private var sleepingReloadDelay: UInt64?
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
        // Free the slot now: the cancelled task runs its cleanup later, and a reload
        // requested in between would otherwise be dropped.
        scheduledReloadTask = nil
        scheduledReloadGeneration += 1
        pendingReloadDelay = nil
        sleepingReloadDelay = nil
        softRefreshTask?.cancel()
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
        guard let host, !persistence.accountDeletionRecoveryRequired else { return }
        let previousState = host.syncState
        let outcome = await cartSync.syncCart(reason: reason)
        guard !persistence.accountDeletionRecoveryRequired else { return }
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
            // Delivered on the main queue. Read synchronously: `changedValuesForCurrentEvent()`
            // only describes the change while this notification is being posted.
            guard Self.productPurchasedStateChanged(in: notification) else { return }
            MainActor.assumeIsolated {
                self?.scheduleSoftProductRefresh(delayNanoseconds: 50_000_000)
            }
        }

        cloudEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: persistence.container,
            queue: .main
        ) { [weak self] notification in
            // Delivered on the main queue. The event object is not Sendable, so only its
            // values cross into the main-actor closure.
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }
            let isFinished = event.endDate != nil
            let eventError = event.error
            let eventType = event.type
            MainActor.assumeIsolated {
                guard let self,
                      let host = self.host,
                      !self.persistence.accountDeletionRecoveryRequired else { return }
                if !isFinished {
                    host.applySyncState(.syncing)
                } else if let error = eventError {
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
                        type: eventType,
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
        guard host?.account != nil, !persistence.accountDeletionRecoveryRequired else { return }
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
        guard host?.account != nil, !persistence.accountDeletionRecoveryRequired else { return }
        pendingReloadDelay = min(pendingReloadDelay ?? .max, delayNanoseconds)
        if scheduledReloadTask != nil {
            // Only a sleeping loop is replaced, and only by a shorter request. A loop that is
            // already syncing picks the pending delay up on its next pass.
            guard let sleepingReloadDelay, delayNanoseconds < sleepingReloadDelay else { return }
            scheduledReloadTask?.cancel()
            self.sleepingReloadDelay = nil
        }
        scheduledReloadGeneration += 1
        let generation = scheduledReloadGeneration
        scheduledReloadTask = Task { [weak self] in
            defer {
                if let self, scheduledReloadGeneration == generation {
                    scheduledReloadTask = nil
                    sleepingReloadDelay = nil
                }
            }
            while let self, !Task.isCancelled {
                guard let delay = pendingReloadDelay else { return }
                pendingReloadDelay = nil
                sleepingReloadDelay = delay
                try? await Task.sleep(nanoseconds: delay)
                // A cancelled task no longer owns the shared state; leave it to its successor.
                guard !Task.isCancelled else { return }
                sleepingReloadDelay = nil
                guard !persistence.accountDeletionRecoveryRequired else { return }
                if pendingReloadDelay != nil {
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
                await host.drainWidgetPendingToggles()
                await syncCart(reason: .cloudImport)
            }
        }
    }

    private nonisolated static func productPurchasedStateChanged(in notification: Notification) -> Bool {
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
                guard !self.persistence.accountDeletionRecoveryRequired else { return }
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
