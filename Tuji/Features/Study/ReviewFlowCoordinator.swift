// The 複習 session (§III.Q): a cursor over the due queue, the beats between
// cards, and what a finished answer is worth.
//
// **One card's own state is not here.** What it asks, what the user has done to
// it and what that adds up to live in `ReviewQuestion`, which this rebuilds on
// every advance — see that file for why the per-item reset is a construction.
// This keeps only what outlives a card: the queue and where we are in it, the
// requeue set, the session's 聽句 opt-out, the primed haptics, `AnswerBeat`,
// and the writer.
//
// Per card:
//   .answer — the user may flip the image over for the gloss (求救提示, see
//     `toggleHint`), then picks among the 4 MCQ choices. In 看圖選字 a wrong
//     option is only *ruled out* — marked, taken out of play, question still
//     open — so the item resolves on the pick that lands, down one of three
//     paths (聽句 has two pictures, so its first tap resolves either way):
//     • fast correct  → the suggested rating is applied automatically and a
//       flash capsule confirms it — no reveal sheet, no extra tap. Manual
//       rating only remains where the user's judgment adds signal.
//     • slow correct  → reveal sheet with rating buttons (困難/穩定/熟練).
//     • wrong         → reveal sheet with 重來/困難 (困難 = "按錯了，其實記得";
//       anything higher would let a missed word skip its relearn). "Wrong"
//       means anything was ruled out first, not that the final tap missed.
//   Either sheet arrives a beat (`revealDelay`) after the options resolve, so
//   the result is readable before a modal covers it.
//
//   A hinted item takes the wrong-answer rating table either way — see
//   `ReviewQuestion.toggleHint` and docs/adr/0007-review-hint-costs-a-downgrade.md.
//
//   Retests (a word requeued after a wrong first answer) NEVER write SRS —
//   the first attempt's 重來 already rescheduled the word, and rating a
//   just-revealed answer again would stretch the relearn interval. Correct
//   retests flash-advance; wrong ones show the sheet as study material with
//   a single 下一題.
//
// Rating writes are optimistic: the UI advances immediately while the write
// goes to the DurableAnswerWriter in the background. The writer retries and, on
// exhaustion, parks the answer in the durable StudyAnswerOutbox (replayed on
// next launch/foreground) and reports `.parked`, which bumps `unsyncedCount`
// for CompleteView's notice.

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
    private(set) var queue: [StudyQueueItem]
    /// Distinct word count at start — the stable progress denominator so
    /// requeued re-tests don't inflate it.
    let originalCount: Int
    private(set) var index: Int = 0
    var finished: Bool = false

    /// The card in front of the user. Nil only for an empty queue, which the
    /// launcher does not present.
    private(set) var question: ReviewQuestion?

    private(set) var revealMode: ReviewRevealMode?
    private(set) var flash: ReviewFlash?
    /// Items the user actually answered (one per cleared item). Drives the
    /// "今天複習" tile row on CompleteView.
    private(set) var answered: [StudyQueueItem] = []
    /// Words already requeued once — enforces "one extra re-test per word".
    /// Also CompleteView's 答錯過 marker.
    private(set) var retriedIds: Set<String> = []
    /// Distinct words fully done (won't reappear). Drives the progress bar.
    private(set) var passedCount: Int = 0
    /// Times each word has been presented *and left* — folds into the MCQ
    /// option seed so a re-test reshuffles instead of letting "the answer was
    /// C" stand in for the word, and picks 聽句's sentence so a re-test hears
    /// the *other* one rather than the recording it just failed.
    private var presentedCounts: [String: Int] = [:]

    // MARK: - 聽句, the parts that belong to the session

    /// The user asked for no more listening questions this session.
    ///
    /// This is an "I cannot hear right now" escape, not a "this is too hard"
    /// one — 聽句 is the only question in the app that cannot be answered
    /// without audio, and no headphones on a train is not a difficulty problem.
    /// That is also why it carries no rating cost: switching to 選字 reveals
    /// nothing, it asks a different question.
    ///
    /// Session-scoped on purpose, matching what the button says (這輪). 再來一輪
    /// builds a fresh coordinator, so the next round starts asking again rather
    /// than silently inheriting a decision made about a different sitting.
    private(set) var listeningOptedOut: Bool = false
    /// The kind the previous presentation used — "no two 聽句 in a row".
    private var previousKind: ReviewQuestionKind?
    /// Words already asked as 聽句 this session, so their re-test keeps the
    /// question instead of being demoted by the spacing rule.
    private var heardWordIds: Set<String> = []

    private let audio: SpeechPlaying

    /// Held and primed rather than built at the tap.
    ///
    /// `UIImpactFeedbackGenerator(style:).impactOccurred()` on a fresh instance
    /// has to wake the Taptic Engine first, and that wake is the slow part: the
    /// buzz lands well after the row has already moved, which reads as the
    /// whole reaction being late even though the animation starts in the first
    /// frame after the tap (measured). `prepare()` keeps the engine warm across
    /// the window where an answer is likely.
    @ObservationIgnored private let softTap = UIImpactFeedbackGenerator(style: .light)
    @ObservationIgnored private let firmTap = UIImpactFeedbackGenerator(style: .medium)

    /// Everything that happens to an answer after it is handed to the writer:
    /// the drain, the mastery fold, the milestone, the parked count. Shared with
    /// 學新字 — see StudySessionWrites.
    let writes: StudySessionWrites

    private let queueProvider: StudyQueueProviding

    /// Where "now" comes from.
    ///
    /// Injected for the same reason the beats are. The rating suggestion turns
    /// on how long an answer took, and the only way to reach the slow branch
    /// used to be to reach into the coordinator and backdate `startedAt` — one
    /// of two properties left mutable purely for that, in tests that then
    /// carried a comment about it. A clock the caller supplies is the seam
    /// those pokes were standing in for.
    ///
    /// Not `@Sendable`: this class is `@MainActor` and so is every read.
    @ObservationIgnored private let clock: () -> Date

    // How long the flow pauses before advancing past an answered item.
    //
    // Injected for the same reason 學新字 injects its own: the advance beats
    // are 300–800 ms of real `Task.sleep`, and CI runs every `@MainActor`
    // suite in parallel on one actor — a starved run turned a 300 ms beat into
    // a minute and failed every assertion after it.

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
        audio: SpeechPlaying = LiveSpeechPlaying(),
        beat: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        now: @escaping () -> Date = { .now }
    ) {
        self.queue = queue
        self.originalCount = queue.count
        self.writes = StudySessionWrites(writer: writer)
        self.queueProvider = queueProvider
        self.audio = audio
        self.beats = AnswerBeat(sleep: beat)
        self.clock = now
        // Nothing has been missed yet, so the first card is never a re-test.
        self.question = queue.first.map {
            ReviewQuestion(item: $0, isRetest: false, now: now())
        }
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
        guard var q = self.question else { return }
        let item = q.item
        let presentation = self.choicesVariant(for: item)
        let example = ListeningQuestion.example(
            for: item,
            mastery: item.mastery,
            presentation: presentation
        )
        let clip = example?.audioUrls?[voice.rawValue]
        var kind = ListeningQuestion.kind(
            wordId: item.word.id,
            canHear: !self.listeningOptedOut
                && example != nil
                && self.audio.canPlay(clip, online: online),
            previous: self.previousKind,
            alreadyHeard: self.heardWordIds.contains(item.word.id)
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

        // Ready *before* the audio: the card is fully drawn and answerable
        // while the sentence plays. Only the clock waits for the audio.
        q.present(kind: kind, example: example, imageOptions: options, awaitsAudio: true)
        self.question = q
        // The next thing that happens on this card is a tap; warm the engine
        // for it while the question is still being drawn.
        self.primeHaptics()

        guard q.kind == .hearSentence, let example else { return }
        self.heardWordIds.insert(item.word.id)
        await self.playSentence(
            clip: clip,
            text: example.sentence,
            voice: voice,
            isReplay: false
        )
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
        guard var q = self.question, q.willReplay(), let example = q.example else { return }
        self.question = q
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
        guard var q = self.question, q.playbackBegan() else { return }
        // Which card asked. The await below can outlive it — an advance, or
        // 這輪不做聽句題 — and the outcome belongs to the question that asked
        // for it, not to whatever is on screen when it lands.
        let askedBy = q.item.card.id
        self.question = q
        let outcome = await self.audio.play(clip, text: text, voice: voice, rate: rate)
        guard var settled = self.question, settled.item.card.id == askedBy else { return }
        settled.playbackEnded(outcome, isReplay: isReplay, now: self.clock())
        self.question = settled
    }

    /// Word ids still to be asked this session. An image distractor drawn from
    /// them would be a free look at a question the user has not reached.
    private var upcomingWordIds: Set<String> {
        guard self.index < self.queue.count else { return [] }
        return Set(self.queue[self.index...].map(\.word.id))
    }

    /// 這輪不做聽句題. Silences the rest of the session as well as the card in
    /// front of the user — see `ReviewQuestion.optOutOfListening` for why the
    /// current card is converted too. The audio is cut for the same reason
    /// leaving cuts it.
    func optOutOfListening() {
        guard var q = self.question, q.optOutOfListening(now: self.clock()) else { return }
        self.listeningOptedOut = true
        self.audio.stop()
        self.question = q
    }

    /// Lift the blur (ADR-0014).
    func revealSentence() {
        guard var q = self.question else { return }
        q.revealSentence()
        self.question = q
    }

    /// Flip the image over to read the gloss, and back (ADR-0007).
    func toggleHint() {
        guard var q = self.question else { return }
        q.toggleHint()
        self.question = q
    }

    /// Fetch the next round's due queue for 再來一輪; empty ⇒ nothing left. The
    /// view uses this to spin up a fresh coordinator (a clean full reset), so the
    /// fetch is injected and testable instead of the view reaching
    /// `StudyQueueStore.shared`.
    func fetchAnotherRound() async -> [StudyQueueItem] {
        await (try? self.queueProvider.fetch(mode: .review)) ?? []
    }

    var current: StudyQueueItem? {
        self.question?.item
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

    // MARK: - What the screen reads

    //
    // The card's own state lives on `question`; these forward to it so a view
    // does not have to unwrap an optional that is only ever nil for a queue the
    // launcher refuses to present. The defaults are the values a fresh
    // question starts at, which is what an empty session should look like.

    var phase: ReviewPhase {
        self.question?.phase ?? .answer
    }

    var picked: ReviewChoice? {
        self.question?.picked
    }

    var wrongPicks: Set<String> {
        self.question?.wrongPicks ?? []
    }

    var hinted: Bool {
        self.question?.hinted ?? false
    }

    var hintFaceUp: Bool {
        self.question?.hintFaceUp ?? false
    }

    var wasCorrect: Bool {
        self.question?.wasCorrect ?? false
    }

    var suggested: SRSRating {
        self.question?.suggested ?? .good
    }

    var rated: SRSRating? {
        self.question?.rated
    }

    var startedAt: Date {
        self.question?.startedAt ?? .distantPast
    }

    var kind: ReviewQuestionKind {
        self.question?.kind ?? .pickWord
    }

    var listeningExample: StudyExample? {
        self.question?.example
    }

    var imageOptions: [ImageChoiceOption]? {
        self.question?.imageOptions
    }

    var sentenceRevealed: Bool {
        self.question?.sentenceRevealed ?? false
    }

    var replayCount: Int {
        self.question?.replayCount ?? 0
    }

    var audioFailed: Bool {
        self.question?.audioFailed ?? false
    }

    var isPlayingSentence: Bool {
        self.question?.isPlayingSentence ?? false
    }

    var awaitingAudio: Bool {
        self.question?.awaitingAudio ?? false
    }

    var questionReady: Bool {
        self.question?.ready ?? false
    }

    var convertedFromListening: Bool {
        self.question?.convertedFromListening ?? false
    }

    var isRetest: Bool {
        self.question?.isRetest ?? false
    }

    var canNudge: Bool {
        self.question?.canNudge ?? false
    }

    var availableRatings: [SRSRating] {
        self.question?.availableRatings ?? [.again, .hard]
    }

    var reportedSelection: String? {
        self.question?.reportedSelection
    }

    /// The rating a given answer suggests. Forwards to the rule's home so the
    /// two cannot drift; kept here because the nudge copy and the tests both
    /// ask the session.
    func computeSuggestion(
        correct: Bool,
        elapsed: TimeInterval?,
        mastery: Int?,
        hinted: Bool = false
    )
        -> SRSRating
    {
        ReviewQuestion.suggestion(
            correct: correct,
            elapsed: elapsed,
            mastery: mastery,
            hinted: hinted
        )
    }

    // MARK: - Answering

    /// One of the two pictures in 聽句.
    func pickImage(_ option: ImageChoiceOption) {
        guard var q = self.question else { return }
        let tap = q.pickImage(option, now: self.clock())
        self.question = q
        self.perform(tap)
    }

    /// 看圖選字.
    func pick(_ choice: String) {
        guard var q = self.question else { return }
        let tap = q.pick(choice, now: self.clock())
        self.question = q
        self.perform(tap)
    }

    private func perform(_ tap: ReviewTap) {
        switch tap {
        case .ignored:
            break
        case .ruledOut:
            self.firmTap.impactOccurred()
            // The question is still open, so another tap may be seconds away.
            self.primeHaptics()
        case let .resolved(resolution):
            self.settle(resolution)
        }
    }

    private func settle(_ resolution: ReviewResolution) {
        guard let q = self.question else { return }
        (q.wasCorrect ? self.softTap : self.firmTap).impactOccurred()
        self.recordAnswered(q.item)
        switch resolution {
        case .flashRetestPassed:
            self.countSettledWord()
            self.flash = .retestPassed
            self.scheduleAdvance(after: .milliseconds(700))
        case let .autoRated(rating):
            self.applyRating(rating)
            self.countSettledWord()
            self.flash = .autoRated(rating)
            self.scheduleAdvance(after: .milliseconds(700))
        case let .reveal(mode):
            // A retest is done either way — nothing rates it, so this is the
            // only moment it can be counted. Everything else waits for the
            // rating, because a wrong one puts the word back on the tail.
            self.countSettledWord()
            self.scheduleReveal(mode)
        }
    }

    /// How long the answered options stay uncovered before the sheet rises.
    ///
    /// The sheet used to go up in the same frame the options resolved, so the
    /// ink block and the frame that say *what just happened* were on screen for
    /// no time at all before a modal slid over them — the user was asked to
    /// rate an answer they had not been shown. It is shorter than the 700 ms
    /// flash-advance on purpose: that beat ends an item, this one is a pause on
    /// the way to something the user still has to act on.
    static let revealDelay: Duration = .milliseconds(600)

    /// Raise the sheet, a beat after the options have shown their result.
    ///
    /// Through `AnswerBeat` rather than a bare `Task` for the reason the beat
    /// exists: 先離開 during the pause must not raise a sheet over the screen
    /// the user just left for.
    private func scheduleReveal(_ mode: ReviewRevealMode) {
        self.beats.schedule(after: Self.revealDelay) { self.revealMode = mode }
    }

    /// Manual rating from the reveal sheet (revealMode == .rate only).
    func rate(_ r: SRSRating) {
        guard let q = self.question, q.phase == .review,
              self.revealMode == .rate, q.rated == nil
        else { return }
        self.softTap.impactOccurred()
        // Wrong first attempt → requeue the word once for an in-session
        // re-test (appended to the tail). The re-test itself never requeues
        // again, and a correct first answer passes straight through.
        if !q.wasCorrect {
            self.retriedIds.insert(q.item.word.id)
            self.queue.append(q.item)
        }
        self.applyRating(r)
        self.countSettledWord()
        // Fixed, network-independent beat so the button fill registers.
        self.scheduleAdvance(after: .milliseconds(300))
    }

    /// 下一題 on the retest-wrong sheet (revealMode == .continueOnly).
    func continueFromReveal() {
        guard self.phase == .review, self.revealMode == .continueOnly else { return }
        self.scheduleAdvance(after: .zero)
    }

    // MARK: - Internals

    /// Warm the Taptic Engine for the tap that is coming. Cheap, and idempotent
    /// — the system lets the readiness lapse on its own after a few seconds.
    private func primeHaptics() {
        self.softTap.prepare()
        self.firmTap.prepare()
    }

    /// One row per word on CompleteView, even when re-tested twice.
    private func recordAnswered(_ item: StudyQueueItem) {
        if !self.answered.contains(where: { $0.word.id == item.word.id }) {
            self.answered.append(item)
        }
    }

    /// Move the progress bar on, if this presentation has finished with its
    /// word.
    ///
    /// It used to be three `passedCount += 1` sites under three different
    /// conditions. The condition is one — `ReviewQuestion.settled` — and it is
    /// asked at the two moments a presentation can end: when it resolves, and
    /// when a rating comes back. The `counted` flag is what keeps one rule from
    /// becoming two counters.
    private func countSettledWord() {
        guard var q = self.question, q.settled, !q.counted else { return }
        q.markCounted()
        self.question = q
        self.passedCount += 1
    }

    /// Record + persist one SRS rating (optimistically, in the background).
    private func applyRating(_ r: SRSRating) {
        guard var q = self.question, q.applyRating(r) else { return }
        self.question = q
        self.writes.submit(
            q.payload(rating: r, listeningOptedOut: self.listeningOptedOut),
            wordId: q.item.word.id
        )
    }

    private func scheduleAdvance(after delay: Duration) {
        self.beats.schedule(after: delay) { self.advance() }
    }

    /// Drops everything this session still has in flight, and is what leaving
    /// calls. Without it the beat outlives the screen — and, since 聽句
    /// auto-plays, so does the sentence: walking out mid-clip used to narrate
    /// whichever screen the user went to instead.
    ///
    /// `awaitTerminal` is built on `withCheckedContinuation`, which is not
    /// cancellation-aware, so cancelling the view's `.task` does **not** reach
    /// the audio. It has to be told.
    func cancelPendingBeats() {
        self.beats.cancelAll()
        self.audio.stop()
    }

    private func advance() {
        if let leaving = self.question {
            self.presentedCounts[leaving.item.word.id, default: 0] += 1
            // Remembered across the rebuild below: "no two 聽句 in a row" is
            // the one piece of per-item state whose whole job is to outlive
            // its item.
            self.previousKind = leaving.kind
        }
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
            self.revealMode = nil
            self.flash = nil
            // The whole per-item reset. A new value starts at its start values,
            // so there is no list of fields to keep in step with the next
            // question kind someone adds.
            let item = self.queue[self.index]
            self.question = ReviewQuestion(
                item: item,
                isRetest: self.retriedIds.contains(item.word.id),
                now: self.clock()
            )
        }
    }
}
