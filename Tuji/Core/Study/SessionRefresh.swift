// The one home for "what a finished study session refreshes, and when". Both
// completion screens — NewDoneView (學新字) and CompleteView (複習) — used to
// spell out the drain → invalidate → reload choreography inline, with divergent
// store subsets and only new-flow carrying the second-drain rule for the last
// word's write. SessionRefresh owns that sequence so the two flows can't drift.

import Foundation
import SwiftUI

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

/// Something whose optimistic SRS writes can be awaited (bounded), so the
/// refresh doesn't race the writes. Both study flows satisfy it through the one
/// module that owns their writes — the two coordinators used to conform
/// separately, each with its own one-line delegation to the same free function.
@MainActor
protocol PendingWriteDraining {
    func drainPendingWrites(within timeout: Duration) async
    var hasPendingWrites: Bool { get }
}

extension StudySessionWrites: PendingWriteDraining {}

@MainActor
struct SessionRefresh {
    /// The home stores to invalidate + reload (mastery, progress, study stats).
    let stores: [RefreshableStore]
    /// Drop the prefetched study queue — this session changed due/seen counts,
    /// so the next 複習 / 學新字 must re-fetch. A closure so the caller owns the
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

/// Attach to the screen a finished session shows — **every** one of them.
///
/// The refresh belongs to *finishing the session*, not to the celebration that
/// happens to be on screen. It used to hang off `CompleteView` / `NewDoneView`,
/// so a session that crossed a streak milestone showed `MilestoneView` instead
/// and refreshed nothing at all: the streak it had just celebrated stayed
/// stale, mastery was never reloaded, and the study queue was never dropped.
///
/// The three home stores and the queue invalidation are read here rather than
/// assembled by each caller — that assembly was the duplication that survived
/// deduping the sequence itself.
extension View {
    func refreshesFinishedSession(
        draining: PendingWriteDraining,
        then: @escaping @MainActor () -> Void = {}
    )
        -> some View
    {
        self.modifier(FinishedSessionRefresh(draining: draining, then: then))
    }
}

private struct FinishedSessionRefresh: ViewModifier {
    let draining: PendingWriteDraining
    let then: @MainActor () -> Void

    @Environment(MasteryStore.self) private var mastery
    @Environment(ProgressStore.self) private var progress
    @Environment(StudyStatsStore.self) private var studyStats

    func body(content: Content) -> some View {
        content.task {
            await SessionRefresh(
                stores: [self.mastery, self.studyStats, self.progress],
                invalidateQueue: { StudyQueueStore.shared.invalidate() }
            ).run(draining: self.draining)
            self.then()
        }
    }
}
