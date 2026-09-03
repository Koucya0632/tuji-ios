// State machine for SRS review (§III.Q). Per item:
//   .answer — the user may flip the image over for the gloss (求救提示, see
//     `toggleHint`), then picks one of 4 MCQ choices, then one of three paths:
//     • fast correct  → the suggested rating is applied automatically and a
//       flash capsule confirms it — no reveal sheet, no extra tap. Manual
//       rating only remains where the user's judgment adds signal.
//     • slow correct  → reveal sheet with rating buttons (困難/穩定/熟練).
//     • wrong         → reveal sheet with 重來/困難 (困難 = "按錯了，其實記得";
//       anything higher would let a missed word skip its relearn).
//   A hinted item takes the wrong-answer rating table either way — see
//   `toggleHint` and docs/adr/0007-review-hint-costs-a-downgrade.md.
//
//   Retests (a word requeued after a wrong first answer) NEVER write SRS —
//   the first attempt's 重來 already rescheduled the word, and rating a
//   just-revealed answer again would stretch the relearn interval. Correct
//   retests flash-advance; wrong ones show the sheet as study material with
//   a single 下一題.
//
// Rating writes are optimistic: the UI advances immediately while persist()
// hands the answer to the DurableAnswerWriter in the background. The writer
// retries and, on exhaustion, parks the answer in the durable StudyAnswerOutbox
// (replayed on next launch/foreground) and reports `.parked`, which bumps
// `unsyncedCount` for CompleteView's notice.

import Observation
import SwiftUI

enum ReviewPhase: Hashable {
    case answer
    case review
}

/// What the reveal sheet is for (nil ⇒ no sheet, flash-advance path).
enum ReviewRevealMode: Hashable {
    /// Manual SRS rating buttons.
    case rate
    /// Retest wrong: study material + a single 下一題 (no write).
    case continueOnly
}

/// Feedback capsule shown while auto-advancing without the sheet.
enum ReviewFlash: Hashable {
    case autoRated(SRSRating)
    case retestPassed
}

@MainActor
@Observable
final class ReviewFlowCoordinator {
    /// Mutable so a wrong first answer can requeue the word once (appended to
    /// the tail for an in-session re-test, mirroring NewFlow).
    var queue: [StudyQueueItem]
    /// Distinct word count at start — the stable progress denominator so
    /// requeued re-tests don't inflate it.
    let originalCount: Int
    var index: Int = 0
    var phase: ReviewPhase = .answer
    var picked: String?
    /// The user flipped this presentation's image over for the gloss. Sticky
    /// within the presentation — flipping back does not un-see it — and reset
    /// in `advance()` along with the rest of the per-item state.
    private(set) var hinted: Bool = false
    /// Which face the card is showing right now. Distinct from `hinted`: this
    /// one goes back and forth, that one only ever turns on. It lives here
    /// rather than in the view because it has to reset per item, and the view
    /// is reused across items.
    private(set) var hintFaceUp: Bool = false
    var wasCorrect: Bool = false
    var suggested: SRSRating = .good
    var rated: SRSRating?
    var startedAt: Date = .now
    var finished: Bool = false
    private(set) var revealMode: ReviewRevealMode?
    private(set) var flash: ReviewFlash?
    /// Items the user actually answered (one per cleared item). Drives the
    /// "今天複習" tile row on CompleteView.
    var answered: [StudyQueueItem] = []
    /// Words already requeued once — enforces "one extra re-test per word".
    /// Also CompleteView's 答錯過 marker.
    var retriedIds: Set<String> = []
    /// Distinct words fully done (won't reappear). Drives the progress bar.
    var passedCount: Int = 0
    /// Times each word has been presented *and left* — folds into the MCQ
    /// option seed so a re-test reshuffles instead of letting "the answer was
    /// C" stand in for the word, and picks 聽句's sentence so a re-test hears
    /// the *other* one rather than the recording it just failed.
    private var presentedCounts: [String: Int] = [:]

    // MARK: - 聽句

    /// Which question this presentation is asking. Decided in
    /// `prepareQuestion`, when the card becomes current — not at session start,
    /// because the network can drop mid-session and take 聽句's eligibility
    /// with it (ADR-0014).
    private(set) var kind: ReviewQuestionKind = .pickWord
    /// The sentence being asked about, when `kind == .hearSentence`.
    private(set) var listeningExample: StudyExample?
    /// The two pictures, when `kind == .hearSentence`.
    private(set) var imageOptions: [ImageChoiceOption]?
    /// The eye was pressed and the sentence is legible. One-way within the
    /// presentation, like `hinted` — which it also sets, because reading the
    /// sentence is reading the answer.
    private(set) var sentenceRevealed: Bool = false
    /// Replays before answering. Deliberately does **not** reset the clock:
    /// with the download and the clip length already excluded, replay time
    /// points the right way — needing three listens *is* 困難.
    private(set) var replayCount: Int = 0
    /// The clip was missing/unreachable (so this was on-device synthesis), or
    /// nothing came out at all.
    private(set) var audioFailed: Bool = false
    /// Whether the sentence is currently being played, for the play button.
    private(set) var isPlayingSentence: Bool = false
    /// The clock has not started yet: 聽句 starts it when the audio *ends*.
    /// Until then an answer cannot be timed, and `pick` refuses.
    private(set) var awaitingAudio: Bool = false
    /// Whether `prepareQuestion` has decided what this card asks.
    ///
    /// The view must draw a skeleton until it has. `kind` defaults to
    /// `.pickWord`, and 選字's hero *is the answer's own picture* — so rendering
    /// the default for the one frame before the decision lands would show the
    /// answer to a question that turns out to be 聽句. It cannot be solved by
    /// defaulting the other way either: `.hearSentence` has no sentence to draw
    /// yet. The honest third state is "not decided".
    ///
    /// The skeleton also has to be a real view. A `body` that renders to
    /// nothing never runs its `.task`, so an `EmptyView` here would mean the
    /// decision is never made at all.
    private(set) var questionReady: Bool = false
    /// The kind the previous presentation used — "no two 聽句 in a row".
    private var previousKind: ReviewQuestionKind?
    /// Words already asked as 聽句 this session, so their re-test keeps the
    /// question instead of being demoted by the spacing rule.
    private var heardWordIds: Set<String> = []

    private let audio: ListeningAudio

    /// Everything that happens to an answer after it is handed to the writer:
    /// the drain, the mastery fold, the milestone, the parked count. Shared with
    /// 學新字 — see StudySessionWrites.
    let writes: StudySessionWrites

    private let queueProvider: StudyQueueProviding

    // How long the flow pauses before advancing past an answered item.
    //
    // Injected for the same reason 學新字 injects its own: the advance beats
    // are 300–800 ms of real `Task.sleep`, and CI runs every `@MainActor`
    // suite in parallel on one actor — a starved run turned a 300 ms beat into
    // a minute and failed every assertion after it. This coordinator was the
    // one that still had no seam at all, so its tests polled a wall clock and
    // carried a nine-line comment about the resulting flake instead of closing
    // it.

    /// The advances in flight — see `AnswerBeat`, which 學新字 holds too. 複習
    /// was the fourth copy of that machinery and the one with no cancellation
    /// at all: it spawned an untracked `Task`, so leaving mid-answer still ran
    /// `advance()` — and `drainPendingWrites`, and `finished = true` — on a
    /// coordinator whose screen was gone.
    private let beats: AnswerBeat

    init(
        queue: [StudyQueueItem],
        writer: DurableAnswerWriting = DurableAnswerWriter(),
        queueProvider: StudyQueueProviding = StudyQueueStore.shared,
        audio: ListeningAudio = LiveListeningAudio(),
        beat: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.queue = queue
        self.originalCount = queue.count
        self.writes = StudySessionWrites(writer: writer)
        self.queueProvider = queueProvider
        self.audio = audio
        self.beats = AnswerBeat(sleep: beat)
    }

    // MARK: - Choosing the question

    /// Decide what to ask about the current card, and start its audio if the
    /// answer is 聽句.
    ///
    /// The catalogue, the session language and connectivity arrive as arguments
    /// rather than injected stores because all three move: freezing them at
    /// `init` would decide the whole session's questions against the network as
    /// it was when the queue loaded.
    func prepareQuestion(
        pool: [CardWord],
        session: TargetLanguage,
        online: Bool,
        voice: SpeechService.Voice
    ) async {
        guard let item = current else { return }
        let presentation = self.choicesVariant(for: item)
        let example = ListeningQuestion.example(
            for: item,
            mastery: item.mastery,
            presentation: presentation
        )
        let clip = example?.audioUrls?[voice.rawValue]
        let alreadyHeard = self.heardWordIds.contains(item.word.id)
        var kind = ListeningQuestion.kind(
            wordId: item.word.id,
            canHear: example != nil && self.audio.canPlay(clip, online: online),
            previous: self.previousKind,
            alreadyHeard: alreadyHeard
        )

        // Two pictures or it is not this question. A pool that cannot produce a
        // fair distractor sends the card to 選字 — the same fallback every
        // other ineligible card takes.
        var options: [ImageChoiceOption]?
        if kind == .hearSentence {
            options = ImageChoicePair.options(
                for: item,
                pool: pool,
                session: session,
                mentionedWordIds: Set(example?.mentionedWordIds ?? []),
                queuedWordIds: self.upcomingWordIds,
                variant: presentation
            )
            if options == nil { kind = .pickWord }
        }

        self.kind = kind
        guard kind == .hearSentence, let example else {
            self.listeningExample = nil
            self.imageOptions = nil
            self.questionReady = true
            return
        }
        self.listeningExample = example
        self.imageOptions = options
        self.heardWordIds.insert(item.word.id)
        // Ready *before* the audio: the card is fully drawn and answerable
        // while the sentence plays. Only the clock waits for the audio.
        self.questionReady = true
        // The clock does not run yet. `startedAt` is set when the audio ends.
        self.awaitingAudio = true
        await self.playSentence(clip: clip, text: example.sentence, voice: voice, isReplay: false)
    }

    /// How much slower 慢讀 is than the recording. A time-stretch on the same
    /// clip rather than a second recording — it costs nothing, and if it turns
    /// out to sound wrong it can be swapped for a Chirp-generated slow take
    /// behind this same number.
    static let slowRate: Float = 0.8

    /// The play button, and the first automatic play. Replays are free by
    /// design: the suggestion no longer turns on a stopwatch the user can game,
    /// so hearing it again should never feel expensive.
    ///
    /// 慢讀 counts as a replay, because it is one: reaching for it says the
    /// sentence did not land at speed, which is the same thing pressing play
    /// again says. It carries no *rating* cost for the same reason replays
    /// don't — the clock does not restart (ADR-0014).
    func replaySentence(voice: SpeechService.Voice, slow: Bool = false) async {
        guard self.kind == .hearSentence, let example = listeningExample else { return }
        self.replayCount += 1
        await self.playSentence(
            clip: example.audioUrls?[voice.rawValue],
            text: example.sentence,
            voice: voice,
            isReplay: true,
            rate: slow ? Self.slowRate : 1
        )
    }

    private func playSentence(
        clip: String?,
        text: String,
        voice: SpeechService.Voice,
        isReplay: Bool,
        rate: Float = 1
    ) async {
        self.isPlayingSentence = true
        let outcome = await self.audio.play(clip, text: text, voice: voice, rate: rate)
        self.isPlayingSentence = false
        if outcome != .finished { self.audioFailed = true }
        // Only the first play opens the clock. A replay must not reset it —
        // that would turn the button into a way to buy time, and the time a
        // replay costs is exactly the signal that this word was hard.
        if !isReplay, self.awaitingAudio {
            self.awaitingAudio = false
            self.startedAt = .now
        }
    }

    /// Word ids still to be asked this session. An image distractor drawn from
    /// them would be a free look at a question the user has not reached.
    private var upcomingWordIds: Set<String> {
        guard self.index < self.queue.count else { return [] }
        return Set(self.queue[self.index...].map(\.word.id))
    }

    /// Lift the blur. Same cost as 求救提示's flip and for a stronger reason:
    /// the sentence spells the answer out, so from here this is a reading
    /// question, not a listening one (ADR-0014).
    func revealSentence() {
        guard self.phase == .answer, self.kind == .hearSentence else { return }
        self.sentenceRevealed = true
        self.hinted = true
    }

    /// Fetch the next round's due queue for 再來一輪; empty ⇒ nothing left. The
    /// view uses this to spin up a fresh coordinator (a clean full reset), so the
    /// fetch is injected and testable instead of the view reaching
    /// `StudyQueueStore.shared`.
    func fetchAnotherRound() async -> [StudyQueueItem] {
        await (try? self.queueProvider.fetch(mode: .review)) ?? []
    }

    var current: StudyQueueItem? {
        guard self.index < self.queue.count else { return nil }
        return self.queue[self.index]
    }

    var progress: Double {
        guard self.originalCount > 0 else { return 0 }
        // Based on distinct words completed (passedCount) so requeued re-tests
        // never push the bar backward. A half-step while revealing keeps it
        // feeling responsive.
        let boost = self.phase == .review ? 0.5 : 0
        return min(1, (Double(self.passedCount) + boost) / Double(self.originalCount))
    }

    /// MCQ option variant: bumps each time the word leaves the screen, so its
    /// re-test presents a fresh shuffle.
    func choicesVariant(for item: StudyQueueItem) -> Int {
        self.presentedCounts[item.word.id] ?? 0
    }

    /// True while the current presentation is a re-test of a word missed
    /// earlier this session.
    var isRetest: Bool {
        guard let curr = current else { return false }
        return self.retriedIds.contains(curr.word.id)
    }

    /// Flip the image over to read the gloss, and back. Only while the item is
    /// still unanswered: the reveal sheet rests at `.fraction(0.4)` with
    /// background interaction enabled, so the hero stays tappable underneath it
    /// and an answered item would otherwise still turn.
    ///
    /// Asking for the gloss is the user reporting that they could not retrieve
    /// the word, so it is remembered for the rating (`hinted`) even if they
    /// flip straight back.
    func toggleHint() {
        guard self.phase == .answer, self.kind == .pickWord else { return }
        self.hintFaceUp.toggle()
        if self.hintFaceUp { self.hinted = true }
    }

    /// Whether the 8-second "點一下圖片" nudge still has anything to teach on
    /// this item. The view owns the timer; this owns the decision.
    ///
    /// Never in 聽句. That delay exists to compensate for an affordance drawn
    /// nowhere — 選字's hint is a tap on a picture with nothing to say so — and
    /// 聽句's eye is on screen from the first frame. A line telling the user
    /// about a button they can already see is not a hint, it is noise.
    var canNudge: Bool {
        self.phase == .answer && !self.hinted && !self.isRetest && self.kind == .pickWord
    }

    /// Computed once per answer. Fast correct answers auto-apply this; the
    /// sheet highlights it as 建議 otherwise. Mastery caps the top end: a
    /// 2-second hit on a barely-known word is normal recall, not 熟練 — only
    /// well-established words (score ≥ 50) earn the long-interval jump.
    ///
    /// A hinted item is capped at 困難 regardless of speed. That cap is also
    /// what switches off the auto-rate path in `pick()`, which requires a
    /// suggestion other than 困難 — see ADR-0007.
    /// `elapsed` is nil when nothing was timed — 聽句 answered before its
    /// sentence finished. A correct-but-untimed answer suggests 穩定: 熟練 is
    /// the one rating that rests entirely on the speed signal, and claiming it
    /// without one would be inventing the evidence.
    func computeSuggestion(
        correct: Bool,
        elapsed: TimeInterval?,
        mastery: Int?,
        hinted: Bool = false
    )
        -> SRSRating
    {
        if !correct { return .again }
        if hinted { return .hard }
        guard let elapsed else { return .good }
        switch elapsed {
        case ..<3: return (mastery ?? 0) >= 50 ? .easy : .good
        case ..<7: return .good
        default: return .hard
        }
    }

    /// One of the two pictures in 聽句. Compared by id, not by label: two
    /// catalogue words can print the same string, they cannot share an id.
    func pickImage(_ option: ImageChoiceOption) {
        guard self.kind == .hearSentence, let curr = current else { return }
        self.resolve(picked: option.word, correct: option.id == curr.word.id, item: curr)
    }

    func pick(_ choice: String) {
        guard let curr = current else { return }
        self.resolve(picked: choice, correct: choice == curr.word.word, item: curr)
    }

    private func resolve(picked choice: String, correct ok: Bool, item curr: StudyQueueItem) {
        guard self.phase == .answer else { return }
        // Answering before the sentence finished leaves nothing timed — the
        // clock had not started. It may be genuine (the word was recognised
        // mid-sentence) or a rush, and the two are indistinguishable, so the
        // suggestion falls back to correctness rather than claiming a speed
        // that was never measured.
        let elapsed = self.awaitingAudio
            ? nil
            : Date.now.timeIntervalSince(self.startedAt)
        self.suggested = self.computeSuggestion(
            correct: ok,
            elapsed: elapsed,
            mastery: curr.mastery,
            hinted: self.hinted
        )
        self.picked = choice
        self.wasCorrect = ok
        UIImpactFeedbackGenerator(
            style: ok ? .light : .medium
        ).impactOccurred()
        self.phase = .review
        self.recordAnswered(curr)

        if self.retriedIds.contains(curr.word.id) {
            // Re-test: practice only, never a second SRS write (the first
            // attempt's 重來 already rescheduled this word).
            self.passedCount += 1
            if ok {
                self.flash = .retestPassed
                self.scheduleAdvance(after: .milliseconds(700))
            } else {
                self.revealMode = .continueOnly
            }
        } else if ok, self.suggested != .hard, self.kind == .pickWord {
            // Fast correct: the suggestion is unambiguous — apply it and keep
            // the session moving instead of raising a sheet to confirm it.
            //
            // 聽句 is excluded by that very precondition, not by an exception:
            // its answer is one of *two* pictures, so a fast correct answer is
            // one coin flip and "unambiguous" is not true of it. It takes the
            // branch below — the one whose comment already says the user's own
            // judgment carries signal (ADR-0014).
            self.passedCount += 1
            self.applyRating(self.suggested, for: curr)
            self.flash = .autoRated(self.suggested)
            self.scheduleAdvance(after: .milliseconds(700))
        } else {
            // Wrong, or correct-but-slow: the user's own judgment carries
            // signal, so surface the sheet with rating buttons.
            self.revealMode = .rate
        }
    }

    /// Rating buttons in the reveal sheet. Wrong answers offer only 重來/困難
    /// (困難 = misclick escape hatch) — anything higher would let a missed
    /// word skip its relearn. Correct-but-slow answers pick among the three
    /// positive ratings.
    ///
    /// A hinted answer takes the wrong-answer table even when it was right:
    /// the user told us they could not retrieve the word, so 穩定/熟練 are not
    /// theirs to claim. Only the *suggestion* still tracks correctness.
    var availableRatings: [SRSRating] {
        guard self.wasCorrect, !self.hinted else {
            return [.again, .hard]
        }
        return [.hard, .good, .easy]
    }

    /// Manual rating from the reveal sheet (revealMode == .rate only).
    func rate(_ r: SRSRating) {
        guard self.phase == .review, self.revealMode == .rate,
              self.rated == nil, let curr = current
        else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Wrong first attempt → requeue the word once for an in-session
        // re-test (appended to the tail). The re-test itself never requeues
        // again, and a correct first answer passes straight through.
        if !self.wasCorrect {
            self.retriedIds.insert(curr.word.id)
            self.queue.append(curr)
        } else {
            self.passedCount += 1
        }
        self.applyRating(r, for: curr)
        // Fixed, network-independent beat so the button fill registers.
        self.scheduleAdvance(after: .milliseconds(300))
    }

    /// 下一題 on the retest-wrong sheet (revealMode == .continueOnly).
    func continueFromReveal() {
        guard self.phase == .review, self.revealMode == .continueOnly else { return }
        self.scheduleAdvance(after: .zero)
    }

    // MARK: - Internals

    /// One row per word on CompleteView, even when re-tested twice.
    private func recordAnswered(_ item: StudyQueueItem) {
        if !self.answered.contains(where: { $0.word.id == item.word.id }) {
            self.answered.append(item)
        }
    }

    /// Record + persist one SRS rating (optimistically, in the background).
    private func applyRating(_ r: SRSRating, for item: StudyQueueItem) {
        self.rated = r
        let listening = self.kind == .hearSentence
        let payload = StudyAnswerPayload(
            cardId: item.card.id,
            rating: r,
            responseMs: Int(Date.now.timeIntervalSince(self.startedAt) * 1000),
            activity: self.kind.asActivity,
            hinted: self.hinted,
            // Only 聽句 has these, and sending them as nil elsewhere keeps a
            // 選字 row's metadata honestly empty rather than claiming zero
            // replays of audio that was never played.
            replayCount: listening ? self.replayCount : nil,
            audioFailed: listening ? self.audioFailed : nil
        )
        self.writes.submit(payload, wordId: item.word.id)
    }

    private func scheduleAdvance(after delay: Duration) {
        self.beats.schedule(after: delay) { self.advance() }
    }

    /// Drops everything this session still has in flight, and is what leaving
    /// calls. Without it the beat outlives the screen (see `pendingBeats`) —
    /// and, since 聽句 auto-plays, so does the sentence: walking out mid-clip
    /// used to narrate whichever screen the user went to instead.
    ///
    /// `awaitTerminal` is built on `withCheckedContinuation`, which is not
    /// cancellation-aware, so cancelling the view's `.task` does **not** reach
    /// the audio. It has to be told.
    func cancelPendingBeats() {
        self.beats.cancelAll()
        self.audio.stop()
    }

    private func advance() {
        if let leaving = current {
            self.presentedCounts[leaving.word.id, default: 0] += 1
        }
        // Remembered across the reset below: "no two 聽句 in a row" is the one
        // piece of per-item state whose whole job is to outlive its item.
        self.previousKind = self.kind
        if self.index + 1 >= self.queue.count {
            // Last item: give outstanding SRS writes a brief window to land so
            // CompleteView's mastery deltas are populated, but cap it so a slow
            // or dead network can't hang the summary.
            Task {
                await self.writes.drainPendingWrites(within: .milliseconds(800))
                self.finished = true
            }
        } else {
            self.index += 1
            self.phase = .answer
            self.picked = nil
            self.hinted = false
            self.hintFaceUp = false
            self.rated = nil
            self.revealMode = nil
            self.flash = nil
            self.startedAt = .now
            // 聽句 state. `kind` returns to the default rather than carrying
            // over: `prepareQuestion` decides it for the new card, and leaving
            // the old value up would let one frame render two pictures for a
            // word that has none.
            self.kind = .pickWord
            self.listeningExample = nil
            self.imageOptions = nil
            self.sentenceRevealed = false
            self.replayCount = 0
            self.audioFailed = false
            self.isPlayingSentence = false
            self.awaitingAudio = false
            self.questionReady = false
        }
    }
}
