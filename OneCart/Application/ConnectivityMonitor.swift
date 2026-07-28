import Foundation
import Network

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
