// The one home for "what a finished study session refreshes, and when". Both
// completion screens — NewDoneView (學新字) and CompleteView (複習) — used to
// spell out the drain → invalidate → reload choreography inline, with divergent
// store subsets and only new-flow carrying the second-drain rule for the last
// word's write. SessionRefresh owns that sequence so the two flows can't drift.

import Foundation

/// A store the completion screens invalidate + reload after a session. The three
/// home stores (mastery, progress, study stats) already have this shape, so they
/// conform for free.
@MainActor
protocol RefreshableStore {
    func invalidate()
    func reload() async
}

extension MasteryStore: RefreshableStore {}
extension ProgressStore: RefreshableStore {}
extension StudyStatsStore: RefreshableStore {}

/// A study coordinator whose optimistic SRS writes can be awaited (bounded), so
/// the refresh doesn't race the writes.
@MainActor
protocol PendingWriteDraining {
    func drainPendingWrites(within timeout: Duration) async
    var hasPendingWrites: Bool { get }
}

extension NewFlowCoordinator: PendingWriteDraining {}
extension ReviewFlowCoordinator: PendingWriteDraining {}

/// A drainer with nothing to drain — for previews / callers with no coordinator.
struct NoPendingWrites: PendingWriteDraining {
    func drainPendingWrites(within _: Duration) async {}
    var hasPendingWrites: Bool {
        false
    }
}

@MainActor
struct SessionRefresh {
    /// The home stores to invalidate + reload (mastery, progress, study stats).
    let stores: [RefreshableStore]
    /// Drop the prefetched study queue — this session changed due/seen counts,
    /// so the next 復習 / 學新字 must re-fetch. A closure so the caller owns the
    /// StudyQueueStore reference and a test can spy the invalidation.
    let invalidateQueue: () -> Void

    /// Drain the optimistic writes, then invalidate + reload — and if the last
    /// word's write is still in flight after the short window, wait it out and
    /// refresh once more so no word is left 未學.
    func run(draining coordinator: PendingWriteDraining) async {
        await coordinator.drainPendingWrites(within: .seconds(2))
        await self.refresh()
        if coordinator.hasPendingWrites {
            await coordinator.drainPendingWrites(within: .seconds(15))
            await self.refresh()
        }
    }

    private func refresh() async {
        for store in self.stores {
            store.invalidate()
        }
        self.invalidateQueue()
        // Reload concurrently — the three are independent round-trips. Each Task
        // inherits the main actor (the stores are @MainActor), so they overlap on
        // their network awaits without leaving the actor.
        let reloads = self.stores.map { store in Task { await store.reload() } }
        for reload in reloads {
            await reload.value
        }
    }
}
