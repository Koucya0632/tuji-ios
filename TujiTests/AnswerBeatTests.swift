// Pins the pause between an answer and its resolution — and the cancellation
// that was wrong three separate times before it became a module.
//
// The two coordinators still assert their own version of this through their own
// flows (`leavingDuringTheRecognizeBeatStopsItsWrite`,
// `leavingDuringTheAdvanceBeatDoesNotFinishTheSession`). Those are the tests
// that matter to a reader of 學新字 or 複習. These are the ones that matter to
// the next caller, who will not read either.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct AnswerBeatTests {
    /// A beat that resolves after its sleep, like every uncancelled answer.
    @Test
    func aScheduledBeatResolvesAfterItsDelay() async {
        let beats = AnswerBeat(sleep: { _ in })
        var resolved = false

        beats.schedule(after: .milliseconds(10)) { resolved = true }
        try? await Task.sleep(for: .milliseconds(50))

        #expect(resolved)
    }

    /// The whole reason the module exists. 學新字 leaked this for 認識, then for
    /// 選字 after the class doc said it was fixed, and 複習 never had it at all.
    @Test
    func cancellingDropsAPendingBeat() async {
        let beats = AnswerBeat(sleep: { _ in
            // Long enough that the cancellation lands first.
            try? await Task.sleep(for: .milliseconds(200))
        })
        var resolved = false

        beats.schedule(after: .milliseconds(200)) { resolved = true }
        beats.cancelAll()
        try? await Task.sleep(for: .milliseconds(300))

        #expect(!resolved)
    }

    /// 先離開 lands once and must reach every stage in flight, not the newest.
    @Test
    func cancellingDropsAllOfThem() async {
        let beats = AnswerBeat(sleep: { _ in try? await Task.sleep(for: .milliseconds(200)) })
        var resolved = 0

        for _ in 0..<3 {
            beats.schedule(after: .milliseconds(200)) { resolved += 1 }
        }
        beats.cancelAll()
        try? await Task.sleep(for: .milliseconds(300))

        #expect(resolved == 0)
    }

    /// A zero delay still goes through a task, so it is still cancellable —
    /// 複習's `.zero` advance. Making it the odd one out is how a fourth
    /// hand-written copy would start.
    @Test
    func aZeroDelayBeatIsStillCancellable() async {
        let beats = AnswerBeat(sleep: { _ in })
        var resolved = false

        beats.schedule(after: .zero) { resolved = true }
        beats.cancelAll()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(!resolved)
    }

    /// …and resolves when it is not cancelled. A `cancelAll` that swallowed
    /// everything, or a zero-delay path that never ran, would pass the test above.
    @Test
    func aZeroDelayBeatStillResolves() async {
        let beats = AnswerBeat(sleep: { _ in })
        var resolved = false

        beats.schedule(after: .zero) { resolved = true }
        try? await Task.sleep(for: .milliseconds(50))

        #expect(resolved)
    }

    /// Cancelling clears the roster: a beat scheduled afterwards belongs to the
    /// next answer, and must not be dropped by the cancel that preceded it.
    @Test
    func aBeatScheduledAfterACancelIsNotAffectedByIt() async {
        let beats = AnswerBeat(sleep: { _ in })
        var resolved = false

        beats.cancelAll()
        beats.schedule(after: .milliseconds(10)) { resolved = true }
        try? await Task.sleep(for: .milliseconds(50))

        #expect(resolved)
    }
}
