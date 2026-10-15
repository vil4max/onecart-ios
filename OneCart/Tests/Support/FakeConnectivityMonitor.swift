import Foundation
@testable import OneCart
import Synchronization

/// Stays silent until a test reports a transition, so the session keeps its initial online state
/// instead of following the simulator's network path.
final class FakeConnectivityMonitor: ConnectivityMonitoring {
    private struct State {
        var onChange: (@Sendable (Bool) -> Void)?
        var isRunning = false
    }

    private let state = Mutex(State())

    var onChange: (@Sendable (Bool) -> Void)? {
        get { state.withLock { $0.onChange } }
        set { state.withLock { $0.onChange = newValue } }
    }

    var isRunning: Bool {
        state.withLock { $0.isRunning }
    }

    func start() {
        state.withLock { $0.isRunning = true }
    }

    func stop() {
        state.withLock { $0.isRunning = false }
    }

    func report(isOnline: Bool) {
        onChange?(isOnline)
    }
}
