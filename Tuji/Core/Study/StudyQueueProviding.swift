import Foundation

/// Narrow seam over `StudyQueueStore` for getting a study queue.
///
/// It carried only `fetch` for a while, because the only injected caller was
/// 再來一輪 — a *follow-up* round. The path every 復習 / 學新字 tap and every
/// `tuji://study` link takes is `StudyLauncherView.loadQueue`, which reached the
/// singleton directly and had no tests at all: not the warm-cache `take`, not
/// the empty-queue case, not the throw. `take` joins the seam so that path can
/// be driven too.
///
/// `StudyQueueStore` already implements both, so it conforms for free.
@MainActor
protocol StudyQueueProviding {
    func fetch(mode: StudyMode) async throws -> [StudyQueueItem]
    /// A queue TodayView pre-fetched, if one is still warm. nil = go and fetch.
    func take(mode: StudyMode) -> [StudyQueueItem]?
}

extension StudyQueueStore: StudyQueueProviding {}
