// The pause between an answer and what it resolves to — and, more to the point,
// how that pause is stopped when the screen goes away.
//
// Four copies of this existed, and the cancellation half was wrong in three of
// them at one time or another:
//
//   • 認識 hardcoded its sleep and never joined `pendingBeats`, so 先離開 could
//     not reach it — rating a single-unit word 已認識 and leaving immediately
//     still ran the resolution, and its SRS write, on a dead coordinator.
//   • The class doc above `NewFlowCoordinator` had already declared that defect
//     fixed while 認識 still leaked; the comment on `recognizeAnswer` records it.
//   • 複習 had no array at all: `scheduleAdvance` spawned an untracked `Task`,
//     so leaving mid-answer ran `advance()` — draining writes and flipping
//     `finished` — behind a dismissed view.
//
// Three times is a shape, not an accident. The callers say *how long* and *what
// happens next*; how to wait, how to stop, and how to notice you were stopped
// are not theirs to restate.

import Foundation

/// The answer beats a study flow has in flight.
///
/// One per coordinator. Cancelling drops every pending resolution: the beat is
/// unstructured work that outlives its view on purpose (it must survive a
/// re-render), which is exactly why leaving has to be able to end it.
@MainActor
final class AnswerBeat {
    private var pending: [Task<Void, Never>] = []

    /// Injected because the real beats are 300–800 ms of `Task.sleep`, and CI
    /// runs every `@MainActor` suite in parallel on one actor — a starved run
    /// turned a 300 ms beat into a minute and failed every assertion after it.
    private let sleep: @Sendable (Duration) async -> Void

    init(sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    /// Waits, then resolves — unless `cancelAll()` lands first.
    ///
    /// A zero delay still goes through a task, so it stays cancellable and
    /// still resolves after the caller returns. That is 複習's `.zero` advance,
    /// and making it the odd one out is how a fourth copy would start.
    func schedule(after delay: Duration, then resolve: @escaping @MainActor () -> Void) {
        self.pending.append(Task { [sleep] in
            if delay > .zero { await sleep(delay) }
            guard !Task.isCancelled else { return }
            resolve()
        })
    }

    /// Drops every beat still waiting. 先離開 calls this before dismissing.
    func cancelAll() {
        for task in self.pending {
            task.cancel()
        }
        self.pending.removeAll()
    }
}
