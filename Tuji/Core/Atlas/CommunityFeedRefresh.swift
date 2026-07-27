// App-level signal that a just-published item/collection went live, so the
// community feed (公開圖鑑) bypasses its URLCache on its next appearance and shows
// it immediately — without it the feed (served under `.useProtocolCachePolicy`)
// can return a list captured before the publish.
//
// Producers (the publish flows in 我的合集 / 自製圖鑑管理) call `markNeedsReload()`;
// the feed consumes it once on load. Injected via the SwiftUI environment at the
// app root — replaces the former `AtlasFeedRefreshCenter` global singleton, so the
// coupling is an explicit, visible dependency instead of a hidden global.

import Observation

@MainActor
@Observable
final class CommunityFeedRefresh {
    private var pending = false

    /// Mark the feed as needing a cache-bypassing reload on its next appearance.
    func markNeedsReload() {
        self.pending = true
    }

    /// Whether a reload is pending; reading it clears the flag.
    func consume() -> Bool {
        defer { self.pending = false }
        return self.pending
    }
}
