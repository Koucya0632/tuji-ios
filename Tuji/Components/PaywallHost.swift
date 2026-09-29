// 付費頁, opened from wherever a lock is.
//
// Ten screens each kept their own `@State showPaywall` and their own
// `.sheet { PaywallView() }`, and two of them — a lock inside a sheet — had to
// dismiss that sheet, sleep 400 ms and hope, because SwiftUI will not present a
// second sheet from a screen that is already covered.
//
// Now a lock asks the environment: `@Environment(\.presentPaywall)` and call it.
// The nearest host answers. The app root is one host, and every sheet shell
// (`TujiSheetShell`, `TujiFormSheet`) is another, so a lock inside a sheet opens
// the paywall *on top of* that sheet — nothing to dismiss, nothing to wait for,
// and the sheet is still there when the paywall closes.

import OSLog
import SwiftUI

struct PresentPaywallAction {
    fileprivate let run: @MainActor () -> Void

    @MainActor
    func callAsFunction() {
        self.run()
    }
}

extension EnvironmentValues {
    /// No host above: a screen shown outside the app root (a preview). Logged,
    /// not silent, so a missing host is findable.
    @Entry var presentPaywall = PresentPaywallAction {
        Logger(subsystem: "app.tuji.ios", category: "paywall")
            .error("presentPaywall called with no paywall host above it")
    }
}

private struct PaywallHost: ViewModifier {
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .environment(\.presentPaywall, PresentPaywallAction { self.showing = true })
            .sheet(isPresented: self.$showing) { PaywallView() }
    }
}

extension View {
    /// Makes this subtree's locks open the paywall from here. Applied at the app
    /// root and by the sheet shells; a screen should not need it.
    func paywallHost() -> some View {
        self.modifier(PaywallHost())
    }
}
