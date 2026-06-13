// Holds the most-recent pending `TujiDeepLink` so MainTabsView can pick
// it up via `.onChange`, switch tabs, and append the route to the
// matching NavigationStack path.
//
// Why @Observable instead of an EnvironmentKey'd value: deep links
// arriving during app launch fire before the tab shell mounts, so we
// need a place to park the pending intent until the consumer is ready.

import Observation
import OSLog
import SwiftUI

@MainActor
@Observable
final class DeepLinkCoordinator {
    static let shared = DeepLinkCoordinator()

    /// Set by `TujiApp.handleIncoming(_:)`; cleared after consume().
    var pending: TujiDeepLink?

    private let log = Logger(subsystem: "app.tuji.ios", category: "deeplink")

    private init() {}

    func receive(_ link: TujiDeepLink) {
        self.log.info("queued \(String(describing: link), privacy: .public)")
        self.pending = link
    }

    func consume() -> TujiDeepLink? {
        defer { self.pending = nil }
        return self.pending
    }
}
