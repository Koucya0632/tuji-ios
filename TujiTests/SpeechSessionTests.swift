// 語音輸入 and 跟讀's timing and state, with the mic and recogniser faked and a
// clock moved by hand: what reaches the caller, when a try ends by itself, and
// what a late word from an earlier try can no longer touch.

import Foundation
import Testing
@testable import Tuji

@MainActor
private final class FakeSpeechInput: SpeechListening {
    var authorized = true
    var outcome: SpeechOpenOutcome = .listening
    var recording: URL?
    private(set) var opened: [SpeechListenRequest] = []
    private(set) var events: [SpeechListenEvents] = []
    private(set) var endedAudio = 0
    private(set) var cancelled = 0

    var latest: SpeechListenEvents {
        self.events[self.events.count - 1]
    }

    /// When set, `authorize` waits for `answer(_:)`, as the system prompt does.
    var asks = false
    private var question: CheckedContinuation<Bool, Never>?

    func authorize() async -> Bool {
        guard self.asks else { return self.authorized }
        return await withCheckedContinuation { self.question = $0 }
    }

    func answer(_ granted: Bool) {
        self.question?.resume(returning: granted)
        self.question = nil
    }

    func open(_ request: SpeechListenRequest, events: SpeechListenEvents) -> SpeechOpenOutcome {
        self.opened.append(request)
        self.events.append(events)
        return self.outcome
    }

    func endAudio() {
        self.endedAudio += 1
    }

    func cancel() {
        self.cancelled += 1
    }

    func finishRecording() -> URL? {
        self.recording
    }

    /// A partial transcript.
    func say(_ text: String, on events: SpeechListenEvents? = nil) {
        (events ?? self.latest).result(text, false, false)
    }

    /// The recogniser's last word.
    func final(_ text: String?, on events: SpeechListenEvents? = nil) {
        (events ?? self.latest).result(text, true, false)
    }

    func fail() {
        self.latest.result(nil, false, true)
    }
}

/// Time that only moves when a test says so.
@MainActor
private final class SpeechClock {
    private var now: Duration = .zero
    private var sleepers: [(until: Duration, wake: CheckedContinuation<Void, Never>)] = []

    var sleep: SpeechSleep {
        // Held strongly: a timer still asleep when the test ends keeps its clock.
        { delay in
            await withCheckedContinuation { self.sleepers.append((self.now + delay, $0)) }
        }
    }

    func advance(_ delay: Duration) async {
        await Self.settle()
        self.now += delay
        let due = self.sleepers.filter { $0.until <= self.now }
        self.sleepers.removeAll { $0.until <= self.now }
        due.forEach { $0.wake.resume() }
        await Self.settle()
    }

    /// Lets the timer tasks run up to their next sleep.
    static func settle() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }
}

@MainActor
struct DictationTests {
    private let input = FakeSpeechInput()
    private let clock = SpeechClock()

    private func make() -> Dictation {
        Dictation(input: self.input, sleep: self.clock.sleep)
    }

    private func start(_ dictation: Dictation, into box: Box) async {
        await dictation.start(locale: Locale(identifier: "ja-JP")) { box.heard.append($0) }
    }

    final class Box {
        var heard: [String] = []
    }

    @Test
    func eachPartialReachesTheCallerAndTheFinalEndsIt() async {
        let dictation = self.make(), box = Box()
        await self.start(dictation, into: box)
        #expect(dictation.phase == .listening)
        #expect(self.input.opened.first?.punctuate == true)
        self.input.say("公園")
        self.input.say("公園に行きたい")
        self.input.final("公園に行きたい。")
        #expect(box.heard == ["公園", "公園に行きたい", "公園に行きたい。"])
        #expect(dictation.phase == .idle)
    }

    @Test
    func anEmptyFinalLeavesWhatWasHeard() async {
        let dictation = self.make(), box = Box()
        await self.start(dictation, into: box)
        self.input.say("公園")
        self.input.final("")
        #expect(box.heard == ["公園"])
        #expect(dictation.phase == .idle)
    }

    @Test
    func stoppingStillLetsTheLastWordIn() async {
        let dictation = self.make(), box = Box()
        await self.start(dictation, into: box)
        self.input.say("公園")
        dictation.stop()
        #expect(dictation.phase == .idle)
        #expect(self.input.endedAudio == 1)
        self.input.final("公園です")
        #expect(box.heard.last == "公園です")
    }

    @Test
    func cancellingDropsEverythingAfterIt() async {
        let dictation = self.make(), box = Box()
        await self.start(dictation, into: box)
        self.input.say("公園")
        dictation.cancel()
        self.input.final("公園です")
        #expect(box.heard == ["公園"])
    }

    @Test
    func aWordFromAnEarlierTryIsIgnored() async {
        let dictation = self.make(), first = Box(), second = Box()
        await self.start(dictation, into: first)
        let earlier = self.input.latest
        await self.start(dictation, into: second)
        self.input.say("遅い", on: earlier)
        self.input.say("新しい")
        #expect(first.heard.isEmpty)
        #expect(second.heard == ["新しい"])
        #expect(dictation.phase == .listening)
    }

    @Test
    func nothingHeardStopsAfterTheSilence() async {
        let dictation = self.make(), box = Box()
        await self.start(dictation, into: box)
        await self.clock.advance(Dictation.silence - .milliseconds(1))
        #expect(dictation.phase == .listening)
        await self.clock.advance(.milliseconds(1))
        #expect(dictation.phase == .idle)
        #expect(self.input.endedAudio == 1)
    }

    @Test
    func aPauseAfterAWordStopsIt() async {
        let dictation = self.make(), box = Box()
        await self.start(dictation, into: box)
        await SpeechClock.settle()
        self.input.say("公園")
        await self.clock.advance(Dictation.pause - .milliseconds(1))
        #expect(dictation.phase == .listening)
        await self.clock.advance(.milliseconds(1))
        #expect(dictation.phase == .idle)
    }

    @Test
    func anEarlierTrysCeilingDoesNotStopTheNextOne() async {
        let dictation = self.make(), box = Box()
        await self.start(dictation, into: box)
        await self.clock.advance(.seconds(5))
        await self.start(dictation, into: box)
        // Talk past where the first try's ceiling was (60 s) but not the new one's (65 s).
        for _ in 0..<28 {
            self.input.say("まだ")
            await self.clock.advance(.seconds(2))
        }
        #expect(dictation.phase == .listening)
    }

    @Test
    func theSystemTakingTheMicStopsItLikeThePersonDid() async {
        let dictation = self.make(), box = Box()
        await self.start(dictation, into: box)
        self.input.say("公園")
        self.input.latest.interrupted()
        #expect(dictation.phase == .idle)
        #expect(self.input.endedAudio == 1)
        self.input.final("公園です")
        #expect(box.heard.last == "公園です")
    }

    @Test
    func anInterruptionFromAnEarlierTryIsIgnored() async {
        let dictation = self.make(), box = Box()
        await self.start(dictation, into: box)
        let earlier = self.input.latest
        await self.start(dictation, into: box)
        earlier.interrupted()
        #expect(dictation.phase == .listening)
    }

    @Test
    func itIsNotListeningWhileTheSystemAsksForTheMic() async {
        let dictation = self.make(), box = Box()
        self.input.asks = true
        let starting = Task { await self.start(dictation, into: box) }
        await SpeechClock.settle()
        #expect(dictation.phase == .idle)
        #expect(self.input.opened.isEmpty)
        self.input.answer(true)
        await starting.value
        #expect(dictation.phase == .listening)
    }

    @Test
    func refusingTheMicGoesStraightToDenied() async {
        let dictation = self.make(), box = Box()
        self.input.asks = true
        let starting = Task { await self.start(dictation, into: box) }
        await SpeechClock.settle()
        self.input.answer(false)
        await starting.value
        #expect(dictation.phase == .denied)
        #expect(self.input.opened.isEmpty)
    }

    @Test
    func cancellingWhileTheSystemAsksOpensNothing() async {
        let dictation = self.make(), box = Box()
        self.input.asks = true
        let starting = Task { await self.start(dictation, into: box) }
        await SpeechClock.settle()
        dictation.cancel()
        self.input.answer(true)
        await starting.value
        #expect(dictation.phase == .idle)
        #expect(self.input.opened.isEmpty)
    }

    @Test
    func problemsAreToldApart() async {
        let dictation = self.make(), box = Box()
        self.input.authorized = false
        await self.start(dictation, into: box)
        #expect(dictation.phase == .denied)
        self.input.authorized = true
        for (outcome, phase) in [
            (SpeechOpenOutcome.unsupported, Dictation.Phase.unavailable),
            (.offline, .offline),
            (.failed, .failed)
        ] {
            self.input.outcome = outcome
            await self.start(dictation, into: box)
            #expect(dictation.phase == phase)
        }
    }
}

@MainActor
struct ShadowingRecorderTests {
    private let input = FakeSpeechInput()
    private let clock = SpeechClock()

    private func make() -> ShadowingRecorder {
        ShadowingRecorder(input: self.input, sleep: self.clock.sleep)
    }

    private func start(_ recorder: ShadowingRecorder, line: Int = 0) async {
        await recorder.start(line: line, target: "コーヒーをください", language: .ja)
    }

    private func ratio(_ recorder: ShadowingRecorder) -> Double? {
        if case let .scored(score, _) = recorder.phase { return score.ratio }
        return nil
    }

    @Test
    func theTryIsRecordedAndScoredOnTheFinal() async {
        let recorder = self.make()
        self.input.recording = URL(fileURLWithPath: "/tmp/try.caf")
        await self.start(recorder)
        #expect(self.input.opened.first?.recordTo != nil)
        #expect(self.input.opened.first?.punctuate == false)
        self.input.say("コーヒー")
        #expect(recorder.phase == .listening(heard: "コーヒー"))
        self.input.final("コーヒーをください")
        #expect(self.ratio(recorder) == 1)
        #expect(recorder.recording == self.input.recording)
    }

    @Test
    func stoppingWaitsForTheLastWordThenScoresWhatWasHeard() async {
        let recorder = self.make()
        await self.start(recorder)
        self.input.say("コーヒー")
        recorder.stop()
        #expect(recorder.phase == .finishing)
        #expect(recorder.isActive(line: 0))
        await self.clock.advance(ShadowingRecorder.lastWord)
        #expect(self.ratio(recorder).map { $0 > 0 && $0 < 1 } == true)
    }

    @Test
    func anEmptyFinalAfterAPartialScoresThePartial() async {
        let recorder = self.make()
        await self.start(recorder)
        self.input.say("コーヒーをください")
        self.input.final("")
        #expect(self.ratio(recorder) == 1)
    }

    @Test
    func theSystemTakingTheMicScoresWhatWasHeard() async {
        let recorder = self.make()
        await self.start(recorder)
        self.input.say("コーヒーをください")
        self.input.latest.interrupted()
        #expect(recorder.phase == .finishing)
        self.input.final(nil)
        #expect(self.ratio(recorder) == 1)
    }

    @Test
    func whatACancelledTryHeardDoesNotScoreTheNext() async {
        let recorder = self.make()
        await self.start(recorder, line: 0)
        self.input.say("コーヒーをください")
        recorder.cancel()
        await self.start(recorder, line: 1)
        recorder.stop()
        await self.clock.advance(ShadowingRecorder.lastWord)
        guard case let .scored(_, heard) = recorder.phase else {
            Issue.record("not scored: \(recorder.phase)")
            return
        }
        #expect(heard.isEmpty)
        #expect(recorder.lineID == 1)
    }

    @Test
    func anEarlierTrysCeilingDoesNotStopTheNextOne() async {
        let recorder = self.make()
        await self.start(recorder, line: 0)
        await self.clock.advance(.seconds(5))
        await self.start(recorder, line: 1)
        // Past the first try's ceiling (20 s), short of the new one's (25 s).
        for _ in 0..<8 {
            self.input.say("コーヒー")
            await self.clock.advance(.seconds(2))
        }
        #expect(recorder.isListening)
    }

    @Test
    func aLineIsNotListeningWhileTheSystemAsksForTheMic() async {
        let recorder = self.make()
        self.input.asks = true
        let starting = Task { await self.start(recorder, line: 3) }
        await SpeechClock.settle()
        #expect(recorder.phase == .idle)
        #expect(!recorder.isActive(line: 3))
        self.input.answer(true)
        await starting.value
        #expect(recorder.phase == .listening(heard: ""))
        #expect(recorder.isActive(line: 3))
    }

    @Test
    func nothingHeardScoresAsNothingHeard() async {
        let recorder = self.make()
        await self.start(recorder)
        await self.clock.advance(ShadowingRecorder.silence)
        await self.clock.advance(ShadowingRecorder.lastWord)
        guard case let .scored(_, heard) = recorder.phase else {
            Issue.record("not scored: \(recorder.phase)")
            return
        }
        #expect(heard.isEmpty)
    }
}
