import Foundation
import Network
import Synchronization

/// Online/offline transitions for `CloudSyncCoordinator`; the composition root injects the live
/// monitor and tests a fake, so no test depends on the simulator's network path.
protocol ConnectivityMonitoring: AnyObject, Sendable {
    /// Called on the monitor's queue with whether the network is reachable.
    var onChange: (@Sendable (Bool) -> Void)? { get set }
    func start()
    func stop()
}

final class ConnectivityMonitor: ConnectivityMonitoring {
    private struct State {
        var onChange: (@Sendable (Bool) -> Void)?
        var monitor: NWPathMonitor?
    }

    private let state = Mutex(State())
    private let queue = DispatchQueue(label: "com.vil555tim.onecart.connectivity")

    /// Called on the monitor queue.
    var onChange: (@Sendable (Bool) -> Void)? {
        get { state.withLock { $0.onChange } }
        set { state.withLock { $0.onChange = newValue } }
    }

    func start() {
        // Every start gets a fresh monitor: sign-out and account deletion stop monitoring,
        // and a cancelled NWPathMonitor is not documented to resume updates.
        let monitor = NWPathMonitor()
        let isAlreadyRunning = state.withLock { state in
            guard state.monitor == nil else { return true }
            state.monitor = monitor
            return false
        }
        guard !isAlreadyRunning else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onChange?(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    func stop() {
        let monitor = state.withLock { state in
            defer { state.monitor = nil }
            return state.monitor
        }
        monitor?.cancel()
    }
}
