// Shared drain used by both study coordinators (review + new-learn) to give
// their optimistic, fire-and-forget SRS writes (POST /api/study/answer) a
// bounded window to land before the completion screen reloads mastery/stats.
// Without it the reload can outrun the write and the just-studied word shows
// stale on the 圖鑑/詳情 until the next session.

import Foundation

/// Await every task in `writes`, or `timeout`, whichever comes first. Writes
/// that miss the window keep running and still merge via @Observable state.
///
/// A task group can't express this: it awaits all its children at scope exit,
/// and `await Task<Void, Never>.value` isn't cancellation-aware, so the drain
/// loop would block past `timeout` until the slowest write settled — defeating
/// the cap. Instead race the writes against a sleep on a continuation and
/// resume on whichever lands first; the loser keeps running unstructured.
@MainActor
func drainPendingWrites(_ writes: [Task<Void, Never>], within timeout: Duration) async {
    guard !writes.isEmpty else { return }
    var resumed = false
    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
        /// Both closures inherit this @MainActor isolation, so `resumed` is
        /// touched serially — the guard makes resume exactly-once.
        func finishOnce() {
            guard !resumed else { return }
            resumed = true
            cont.resume()
        }
        Task {
            for w in writes {
                await w.value
            }
            finishOnce()
        }
        Task {
            try? await Task.sleep(for: timeout)
            finishOnce()
        }
    }
}
