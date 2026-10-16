import CoreData
import Foundation

/// What the CloudKit observers and the scheduled reload read from the session and what they ask
/// it to do. The session conforms; the coordinator holds it weakly, since the session owns it.
@MainActor
protocol CloudSyncContext: AnyObject {
    var account: OneCartAccount? { get }
    var isOnline: Bool { get }
    var syncState: OneCartSyncState { get }
    /// Reflects a CloudKit event or a connectivity change in the session's sync status.
    func applyCloudSyncEvent(_ event: CloudSyncEvent)
    func softRefreshCartProducts()
    /// One reload pass after CloudKit changes: refresh, adopt a joined cart, replay widget
    /// purchases, then a `.cloudImport` sync.
    func runCloudImportPass(for account: OneCartAccount) async
}

/// What the coordinator observed; the session decides what it means for its sync status.
enum CloudSyncEvent {
    case importStarted
    case importFailed(Error)
    case importFinished
    case connectivityChanged(isOnline: Bool)
    case wentOffline
    case reconnected
}

/// How a cart sync ended, for the session to apply; nil from `syncCart` means nothing changed.
enum CloudSyncResult: Equatable {
    /// The session refreshes the members, then shows synchronized or offline.
    case synced
    case failed(message: String, presentsAlert: Bool)
}

@MainActor
final class CloudSyncCoordinator {
    private let persistence: PersistenceController
    private let cartSync: CartSyncService
    private let connectivity: any ConnectivityMonitoring
    private weak var context: (any CloudSyncContext)?

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
    private let clock: AppClock

    init(
        persistence: PersistenceController,
        cartSync: CartSyncService,
        connectivity: any ConnectivityMonitoring,
        clock: AppClock = .live,
        context: any CloudSyncContext
    ) {
        self.persistence = persistence
        self.cartSync = cartSync
        self.connectivity = connectivity
        self.clock = clock
        self.context = context
    }

    private var recoveryRequired: Bool {
        persistence.accountDeletionRecoveryRequired
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
        for observer in [remoteChangeObserver, cloudEventObserver, objectsDidChangeObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        remoteChangeObserver = nil
        cloudEventObserver = nil
        objectsDidChangeObserver = nil
        connectivity.stop()
    }

    /// Runs a cart sync and reports how it ended. A pull always alerts on failure; a foreground
    /// sync alerts only when the cart looked healthy before.
    func syncCart(reason: CartSyncReason) async -> CloudSyncResult? {
        guard let context, !recoveryRequired else { return nil }
        let previousState = context.syncState
        let outcome = await cartSync.syncCart(reason: reason)
        guard !recoveryRequired else { return nil }
        switch outcome {
        case .succeeded:
            return .synced
        case .skippedDebounce, .cancelled:
            return nil
        case let .failed(message):
            let presentsAlert: Bool =
                switch reason {
                case .pull:
                    true
                case .foreground:
                    previousState == .synchronized || previousState == .syncing
                case .appear, .cloudImport:
                    false
                }
            return .failed(message: message, presentsAlert: presentsAlert)
        }
    }
}

// MARK: - Observers

extension CloudSyncCoordinator {
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

        installCloudEventObserver()
    }

    private func installCloudEventObserver() {
        cloudEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: persistence.container,
            queue: .main
        ) { [weak self] notification in
            // Delivered on the main queue. The event object is not Sendable, so only its
            // values cross into the main-actor closure.
            guard
                let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event
            else { return }
            let isFinished = event.endDate != nil
            let eventError = event.error
            let eventType = event.type
            MainActor.assumeIsolated {
                self?.handleCloudEvent(type: eventType, isFinished: isFinished, error: eventError)
            }
        }
    }

    private func handleCloudEvent(
        type: NSPersistentCloudKitContainer.EventType,
        isFinished: Bool,
        error: Error?
    ) {
        guard let context, !recoveryRequired else { return }
        guard isFinished else {
            context.applyCloudSyncEvent(.importStarted)
            return
        }
        if let error {
            context.applyCloudSyncEvent(.importFailed(error))
            return
        }
        context.applyCloudSyncEvent(.importFinished)
        if CloudKitProductReloadPolicy.shouldReloadProductsAfterEvent(type: type, ended: true, error: nil) {
            CartSyncLog.cart.info("cloudKit import finished; scheduling cart sync")
            scheduleSoftProductRefresh()
            scheduleCloudReload(delayNanoseconds: 150_000_000)
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
            for object in objects where object is ProductEntity {
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
                self?.handleConnectivityChange(isOnline: isOnline)
            }
        }
        connectivity.start()
    }

    private func handleConnectivityChange(isOnline: Bool) {
        guard let context else { return }
        let wasOnline = context.isOnline
        context.applyCloudSyncEvent(.connectivityChanged(isOnline: isOnline))
        guard !recoveryRequired else { return }
        if !isOnline {
            context.applyCloudSyncEvent(.wentOffline)
        } else if !wasOnline, context.account != nil {
            context.applyCloudSyncEvent(.reconnected)
            scheduleCloudReload(delayNanoseconds: 150_000_000)
        }
    }
}

// MARK: - Scheduled refresh and reload

extension CloudSyncCoordinator {
    func scheduleSoftProductRefresh(delayNanoseconds: UInt64 = 80_000_000) {
        guard context?.account != nil, !recoveryRequired else { return }
        softRefreshTask?.cancel()
        let clock = clock
        softRefreshTask = Task { [weak self] in
            try? await clock.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled, let context = self?.context, context.account != nil else {
                return
            }
            context.softRefreshCartProducts()
        }
    }

    func scheduleCloudReload(delayNanoseconds: UInt64 = 650_000_000) {
        guard context?.account != nil, !recoveryRequired else { return }
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
                try? await clock.sleep(nanoseconds: delay)
                // A cancelled task no longer owns the shared state; leave it to its successor.
                guard !Task.isCancelled else { return }
                sleepingReloadDelay = nil
                guard !recoveryRequired else { return }
                if pendingReloadDelay != nil {
                    continue
                }
                guard let context, let account = context.account else { return }
                await context.runCloudImportPass(for: account)
            }
        }
    }
}
