// Device-wide reachability via NWPathMonitor. Complements APIClient's
// reactive error handling (which only learns about connectivity loss when a
// request actually fails) with a proactive signal the UI can show ahead of
// time, and a hook to flush offline-queued work the moment the network
// comes back rather than waiting for the next launch/foreground.

import Network
import Observation
import OSLog

@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// False until the first path update arrives, so the offline banner
    /// doesn't flash on cold launch before NWPathMonitor reports a status.
    private(set) var hasStatus = false
    private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.tuji.ios.network-monitor")
    private let log = Logger(subsystem: "app.tuji.ios", category: "network")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                self?.apply(connected: connected)
            }
        }
        monitor.start(queue: queue)
    }

    private func apply(connected: Bool) {
        let wasConnected = isConnected
        hasStatus = true
        isConnected = connected
        guard connected, !wasConnected else { return }
        log.info("network restored, flushing offline outbox")
        Task { await StudyAnswerOutbox.shared.replay() }
    }
}
