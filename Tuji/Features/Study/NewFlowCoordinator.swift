// State machine for the "learn new words" micro lesson (§III.P).
//
// The session is ONE interleaved task queue, not three blocked phases: each
// word walks 認識 → 選字 → 拼字 with other words' tasks in between, so the
// quiz retrieves from (short) memory instead of echoing the card just shown.
// Initial schedule places rec(wᵢ)@3i, id(wᵢ)@3i+4, spell(wᵢ)@3i+8 and sorts —
// a steady cadence with 2-3 tasks of lag between a word's stages. Wrong
// answers requeue the same task a few positions later; a requeued 選字 that
// would slip behind its word's pre-scheduled 拼字 is caught by normalizeHead()
// so the stage ladder always holds. The ladder length varies: an 已認識
// self-rating drops the word's 選字 (fast path — production still gates the
// commit) and single-tile subjects carry no 拼字 at all.
//
// SRS: the recognize self-rating is held back per word and posted once that
// word clears its final stage (今日目標 counts full completions only). The
// posted rating is downgraded by quiz performance — one wrong answer drops a
// level, two or more post 重來 — and carries the first-attempt 選字 latency
// as responseMs, so the scheduler learns from behaviour, not just self-report.
// 選字/拼字 are otherwise practice-only (no extra POST per answer).

import Observation
import SwiftUI

@MainActor
@Observable
final class NewFlowCoordinator: StudySession {
    /// The session's words, in server order. NewDoneView renders this grid.
    let queue: [StudyQueueItem]

    /// The interleaved task queue: what is on screen, what comes next, what a
    /// wrong answer does to the order, and how far through the ladder we are.
    /// A value type with its own tests — see StudyLadder.
    private(set) var ladder: StudyLadder

    // Transient per-kind UI state (the task views read these).
    var recRating: SRSRating?
    var recLocked: Bool = false
    var idPicked: String?
    var idLocked: Bool = false
    var spellLocked: Bool = false

    /// Pool entries tapped into slots, in tap order — indices into
    /// `spellPool(for:)`, shared by both 拼字 boards. Index-based so duplicate
    /// units stay distinguishable. Owned here (not in the task views) so the
    /// assemble-and-compare is a testable coordinator decision; reset when the
    /// spell task advances (correct) or requeues (wrong).
    private(set) var spellPicked: [Int] = []

    /// Surface to NewFlowView so it can present WordPeek for wrong answers.
    var peek: StudyQueueWord?

    /// Recognize-step ratings held back until the word clears its final
    /// stage — keyed by card id. See commitLearned(_:).
    private var pendingRatings: [String: SRSRating] = [:]
    /// Wrong 選字/拼字 answers per word id — downgrades the posted rating.
    private var mistakes: [String: Int] = [:]
    /// When the word's 選字 task first surfaced / how long the first pick
    /// took. First-attempt-only: retries after the peek sheet aren't timed.
    private var identifyShownAt: [String: Date] = [:]
    private var identifyResponseMs: [String: Int] = [:]
    /// Wrong-attempt counts per word id: reshuffles MCQ options and re-seeds the
    /// 拼字 pool on each retry so position memory doesn't stand in for the word.
    /// The board itself does not move — a gap-fill re-cuts the same chunks,
    /// because the chunk they missed is the one worth asking again.
    private var identifyAttempts: [String: Int] = [:]
    private var spellAttempts: [String: Int] = [:]

    /// Everything that happens to an answer after it is handed to the writer:
    /// the drain NewDoneView needs before reloading mastery, the mastery fold,
    /// the milestone, and the parked count. Shared with 複習 — see
    /// StudySessionWrites. Learning new words used to discard the `.synced`
    /// body entirely, which is why a streak milestone crossed by a
    /// `new_recognize` write was dropped and could never be recovered.
    let writes: StudySessionWrites

    /// How long the app pauses on a locked answer before resolving it, and the
    /// resolutions currently waiting out that pause.
    ///
    /// The sleep is injected so the tested surface is the one the app calls.
    /// Before that, tests drove `resolveRecognize` / `resolveIdentify` /
    /// `resolveSpell` directly — which the app never calls — so the beats, the
    /// locks and everything between a tap and an SRS write had no coverage at
    /// all. It had already cost a duplicate: `resolveIdentify` carried a second
    /// latency capture whose only caller was the test suite.
    ///
    /// See `AnswerBeat`, which 複習 holds too.
    private let beats: AnswerBeat

    /// Where "now" comes from — 選字's first-attempt latency is the one number
    /// here the scheduler learns from, and with `Date()` read inline a test
    /// could only assert that it was not nil. Same seam 複習 has.
    @ObservationIgnored private let clock: () -> Date

    /// Only ever told to stop: 認識 plays the headword as each card arrives,
    /// and leaving mid-word must not finish saying it over the next screen.
    private let audio: SpeechPlaying

    /// Held and primed rather than built at each resolution — see `StudyHaptics`.
    @ObservationIgnored private let haptics = StudyHaptics()

    init(
        queue: [StudyQueueItem],
        writer: DurableAnswerWriting = DurableAnswerWriter(),
        audio: SpeechPlaying = LiveSpeechPlaying(),
        beat: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        now: @escaping () -> Date = { .now }
    ) {
        self.queue = queue
        self.beats = AnswerBeat(sleep: beat)
        self.ladder = StudyLadder(queue: queue)
        self.writes = StudySessionWrites(writer: writer)
        self.audio = audio
        self.clock = now
        self.taskSurfaced()
    }

    var current: NewStudyTask? {
        self.ladder.current
    }

    var finished: Bool {
        self.ladder.finished
    }

    var progress: Double {
        self.ladder.progress
    }

    var clearedWords: Int {
        self.ladder.clearedWords
    }

    /// 報錯: the task on screen, which stage it is, and what the user chose on
    /// it — the self-rating in 認識, the pick in 選字, whatever is on the board
    /// in 拼字.
    var reportSubject: StudyReportSubject? {
        guard let task = self.ladder.current else { return nil }
        let answer: String? = switch task.kind {
        case .recognize: self.recRating?.rawValue
        case .identify: self.idPicked
        case .spell: self.spellAttemptText
        }
        return StudyReportSubject(item: task.item, phase: task.kind.rawValue, selectedAnswer: answer)
    }

    /// Stable identity for the current presentation: same task shown again
    /// after a wrong answer gets a new identity, so the task view's local
    /// state (e.g. assembled tiles) resets per attempt.
    var currentPresentationId: String {
        guard let task = ladder.current else { return "done" }
        let attempt = switch task.kind {
        case .recognize: 0
        case .identify: self.identifyAttempts[task.item.word.id] ?? 0
        case .spell: self.spellAttempts[task.item.word.id] ?? 0
        }
        return "\(task.id)#\(attempt)"
    }

    /// Session mistake counts by word id (wrong 選字/拼字 attempts) — the
    /// done screen badges words that needed retries.
    var mistakeCounts: [String: Int] {
        self.mistakes
    }

    /// The current word's stage ladder for the header pips: which of
    /// 認識/選字/拼字 it walks and where it stands. Words with a single-tile
    /// subject carry no spell entry.
    func stagePlan(for item: StudyQueueItem) -> [NewStageStep] {
        let wordId = item.word.id
        let currentKind = self.ladder.current?.item.word.id == wordId ? self.ladder.current?.kind : nil

        func state(_ kind: NewTaskKind, done: Bool) -> NewStageStep.State {
            if currentKind == kind { return .active }
            return done ? .done : .pending
        }

        var steps = [
            NewStageStep(
                kind: .recognize,
                state: state(.recognize, done: self.pendingRatings[item.card.id] != nil)
            ),
            NewStageStep(
                kind: .identify,
                state: self.ladder.skippedIdentify.contains(wordId)
                    ? .skipped
                    : state(.identify, done: self.ladder.identifyCleared.contains(wordId))
            )
        ]
        if self.ladder.hasSpellStage(item) {
            steps.append(NewStageStep(kind: .spell, state: state(.spell, done: false)))
        }
        return steps
    }

    // MARK: - Queue mechanics

    /// Advance the ladder past a cleared stage, flushing the word's held-back
    /// SRS write if that was its last one. The ordering rule — write on "no
    /// tasks left for this word", not on "拼字 done" — belongs to the ladder,
    /// which reports it; the write belongs here.
    private func completeCurrentTask() {
        if let cleared = self.ladder.completeCurrent() {
            self.commitLearned(cleared)
        }
        self.taskSurfaced()
    }

    private func requeueCurrentTask() {
        self.ladder.requeueCurrent()
        self.taskSurfaced()
    }

    /// A task reached the head. Warm the engine for the tap it asks for, and
    /// start the first-attempt clock if it is a 選字. Latency capture is this
    /// coordinator's business, not the ladder's, which is why it sits beside
    /// the mutation rather than inside it.
    private func taskSurfaced() {
        self.haptics.prime()
        guard let task = ladder.current, task.kind == .identify,
              self.identifyShownAt[task.item.word.id] == nil
        else { return }
        self.identifyShownAt[task.item.word.id] = self.clock()
    }

    // MARK: - 認識 (recognize)

    /// The self-rating tap. Beats, then resolves — through `AnswerBeat`, like the
    /// other two stages and like 複習's advance.
    ///
    /// It used to hardcode its sleep and run an untracked `Task`, so 先離開 could
    /// not reach it: rating a single-unit word 已認識 and leaving immediately
    /// still ran the resolution — and its SRS write — on a coordinator whose
    /// screen was gone. The class doc claimed that defect was fixed; it was
    /// fixed for 選字 only. That is why the waiting is a module now.
    func recognizeAnswer(rating: SRSRating) {
        guard !self.recLocked, let task = ladder.current, task.kind == .recognize else { return }
        self.recLocked = true
        self.recRating = rating
        self.haptics.success()
        self.beats.schedule(after: .milliseconds(450)) {
            self.recRating = nil
            self.recLocked = false
            self.resolveRecognize(rating: rating)
        }
    }

    /// Synchronous core, split from the button handler so unit tests can walk
    /// the scheduler without real sleeps.
    func resolveRecognize(rating: SRSRating) {
        guard let task = ladder.current, task.kind == .recognize else { return }
        // Hold the rating back; the SRS write fires only once this word clears
        // its final stage (see commitLearned). This keeps 今日目標 counting
        // full completions instead of bare recognize taps.
        self.pendingRatings[task.item.card.id] = rating
        // 已認識 fast path: skip straight to production. Tiles still gate the
        // commit, and a tile miss downgrades the rating — an overconfident
        // self-rating gets corrected there instead of by an easy MCQ.
        if rating == .good {
            self.ladder.skipIdentify(for: task.item)
        }
        self.completeCurrentTask()
    }

    // MARK: - 選字 (identify)

    func identifyPick(_ choice: String) {
        guard !self.idLocked, let task = ladder.current, task.kind == .identify else { return }
        self.idPicked = choice
        self.idLocked = true
        // First-attempt latency only — a retry after the peek sheet has seen
        // the answer, so its speed says nothing about recall.
        if let shownAt = self.identifyShownAt[task.item.word.id],
           self.identifyResponseMs[task.item.word.id] == nil
        {
            self.identifyResponseMs[task.item.word.id] =
                Int(self.clock().timeIntervalSince(shownAt) * 1000)
        }
        let ok = choice == task.item.word.word
        // Correct answers clear faster than wrong ones: momentum for the
        // fast-learning feel, while a miss keeps time to read the reveal.
        self.beats.schedule(after: .milliseconds(ok ? 500 : 800)) {
            if ok {
                self.idLocked = false
                self.idPicked = nil
                self.resolveIdentify(correct: true)
                self.haptics.success()
            } else {
                // Wrong: stay frozen on this item (keep idLocked / idPicked so
                // the wrong + answer highlight stays) and surface the peek
                // sheet. Advancing — requeue a few positions back — is
                // deferred to advanceFromPeek(), fired when the user taps
                // 下一題 / dismisses the sheet.
                self.resolveIdentify(correct: false)
                self.haptics.warning()
            }
        }
    }

    /// Synchronous core: correct clears the stage; wrong records the mistake
    /// and raises the peek (requeue happens on advanceFromPeek()).
    func resolveIdentify(correct: Bool) {
        guard let task = ladder.current, task.kind == .identify else { return }
        if correct {
            self.ladder.markIdentifyCleared(task.item.word.id)
            self.completeCurrentTask()
        } else {
            self.mistakes[task.item.word.id, default: 0] += 1
            self.peek = task.item.word
        }
    }

    /// MCQ option variant for this word — bumps on every wrong attempt so the
    /// retry can't be answered from remembered option positions.
    func choicesVariant(for item: StudyQueueItem) -> Int {
        self.identifyAttempts[item.word.id] ?? 0
    }

    // MARK: - 拼字

    /// Latched when the board fills, cleared when it resets. Also what the view
    /// used to reconstruct as `boardFull && spellLocked`.
    private(set) var spellVerdict: Bool?

    /// 拼字塊 — the whole-string tile board. Japanese readings only now: English
    /// words take the gap-fill below.
    var spellBoard: SpellBoard? {
        guard let task = ladder.current, task.kind == .spell,
              let form = SpellForm.of(task.item),
              case let .tiles(board) = form
        else { return nil }
        let item = task.item
        let units = self.spellPool(for: item)
        let placed = self.spellPicked.filter { units.indices.contains($0) }
        return SpellBoard(
            slots: (0..<units.count).map { slot in
                SpellBoard.Slot(unit: slot < placed.count ? units[placed[slot]] : nil)
            },
            pool: units.enumerated().map { index, unit in
                SpellBoard.Tile(unit: unit, used: self.spellPicked.contains(index))
            },
            subject: TileBoard.spellSubject(for: item),
            tokenUnits: board.tokenUnits,
            verdict: self.spellVerdict
        )
    }

    /// 挖空拼字 — the English board: the word with a few chunks cut out of it.
    var gapBoard: SpellGapBoard? {
        guard let task = ladder.current, task.kind == .spell,
              let form = SpellForm.of(task.item),
              case let .gaps(plan) = form
        else { return nil }
        let options = self.spellPool(for: task.item)
        let placed = self.spellPicked.filter { options.indices.contains($0) }
        return SpellGapBoard(
            term: plan.term,
            segments: plan.segments,
            slots: plan.gaps.enumerated().map { index, gap in
                SpellGapBoard.Slot(
                    answer: gap.answer,
                    filled: index < placed.count ? options[placed[index]] : nil
                )
            },
            pool: options.enumerated().map { index, option in
                SpellBoard.Tile(unit: option, used: self.spellPicked.contains(index))
            },
            widestOption: options.max { $0.count < $1.count } ?? "",
            verdict: self.spellVerdict
        )
    }

    /// What the learner can tap, in display order — scrambled tiles for a tile
    /// board, shuffled chunks for a gap-fill. Seeded per (item, attempt): a
    /// re-render keeps the order, a retry gets a fresh one.
    func spellPool(for item: StudyQueueItem) -> [String] {
        let attempt = self.spellAttempts[item.word.id] ?? 0
        return switch SpellForm.of(item) {
        case .tiles: TileBoard.units(for: item, attempt: attempt)
        case .gaps: SpellGaps.options(for: item, attempt: attempt)
        case nil: []
        }
    }

    /// Tap a pool entry into the next empty slot. Auto-checks when the last slot
    /// fills. A no-op once locked, off a non-spell task, or if already placed.
    ///
    /// One path serves both boards on purpose: filling a gap is the same gesture
    /// as laying a tile — a shuffled pool, slots filled left to right, tap a
    /// filled slot to take it back. Only the slot count differs, and the form
    /// answers that; the pool cannot, because a gap-fill's pool carries
    /// distractors that belong in no slot at all.
    func pickSpell(_ idx: Int) {
        guard !self.spellLocked, let task = current, task.kind == .spell,
              let form = SpellForm.of(task.item),
              !self.spellPicked.contains(idx)
        else { return }
        self.haptics.soft()
        self.spellPicked.append(idx)
        if self.spellPicked.count == form.slotCount {
            let correct = self.spellMatches(self.spellPicked, for: task.item)
            self.spellVerdict = correct
            self.spellAnswer(correct: correct)
        }
    }

    /// Tap a filled slot to take that entry back out (before the board locks).
    func unpickSpell(atSlot slot: Int) {
        guard !self.spellLocked, slot < self.spellPicked.count else { return }
        self.spellPicked.remove(at: slot)
    }

    /// Does this pick sequence spell the word? Pure — the correctness decision
    /// the production step turns on, testable without driving the board.
    ///
    /// The two forms ask different questions of the same picks: a tile board
    /// wants the assembled string, a gap-fill wants each chunk in its own slot.
    /// Joining a gap-fill's picks would accept them in any order.
    func spellMatches(_ picked: [Int], for item: StudyQueueItem) -> Bool {
        let pool = self.spellPool(for: item)
        let chosen = picked.compactMap { pool.indices.contains($0) ? pool[$0] : nil }
        return switch SpellForm.of(item) {
        case let .tiles(board): chosen.joined() == board.target
        case let .gaps(plan): chosen == plan.answers
        case nil: false
        }
    }

    /// What is on the board right now, as one readable string — the 報錯
    /// snapshot's "what did they choose". 拼字 used to report nothing, because a
    /// half-assembled tile board had no obvious answer to name; a gap-fill does,
    /// so the report can finally say what the learner put in the holes.
    var spellAttemptText: String? {
        guard let task = ladder.current, task.kind == .spell,
              let form = SpellForm.of(task.item), !self.spellPicked.isEmpty
        else { return nil }
        let pool = self.spellPool(for: task.item)
        let chosen = self.spellPicked.compactMap { pool.indices.contains($0) ? pool[$0] : nil }
        switch form {
        case .tiles:
            return chosen.joined()
        case let .gaps(plan):
            return plan.segments.enumerated().reduce(into: "") { out, pair in
                let (index, segment) = pair
                out += segment
                guard index < plan.gaps.count else { return }
                out += index < chosen.count ? chosen[index] : "_"
            }
        }
    }

    /// Locks the board and, after a beat, resolves. Called by pickSpell when the
    /// last slot fills.
    func spellAnswer(correct: Bool) {
        guard !self.spellLocked, let task = current, task.kind == .spell else { return }
        self.spellLocked = true
        self.beats.schedule(after: .milliseconds(correct ? 450 : 800)) {
            if correct {
                self.spellLocked = false
                self.resolveSpell(correct: true)
                self.haptics.success()
            } else {
                // Stay frozen (the board shows red) and surface the peek; the
                // requeue + reshuffle happen on advanceFromPeek().
                self.resolveSpell(correct: false)
                self.haptics.warning()
            }
        }
    }

    /// Synchronous core, also reachable from tests.
    func resolveSpell(correct: Bool) {
        guard let task = ladder.current, task.kind == .spell else { return }
        if correct {
            self.completeCurrentTask()
            // The next spell task (whenever it surfaces) starts from an empty
            // board. Wrong answers keep the picks so the red board stays until
            // advanceFromPeek() requeues + clears.
            self.spellPicked = []
            self.spellVerdict = nil
        } else {
            self.mistakes[task.item.word.id, default: 0] += 1
            self.peek = task.item.word
        }
    }

    // MARK: - Wrong-answer advance

    /// Advance after a wrong answer: requeue the missed task a few positions
    /// back, bump its attempt (new options / variant / scramble), and unlock.
    /// Wired to the peek sheet's onDismiss so the 下一題 button and a
    /// swipe-down behave identically and never double-advance.
    func advanceFromPeek() {
        self.peek = nil
        guard let task = ladder.current else { return }
        switch task.kind {
        case .identify:
            self.idPicked = nil
            self.idLocked = false
            self.identifyAttempts[task.item.word.id, default: 0] += 1
            self.requeueCurrentTask()
        case .spell:
            self.spellLocked = false
            self.spellPicked = []
            self.spellVerdict = nil
            self.spellAttempts[task.item.word.id, default: 0] += 1
            self.requeueCurrentTask()
        case .recognize:
            break
        }
    }

    // MARK: - SRS write

    /// Flush the deferred recognize SRS write for a word that has now cleared
    /// all stages. The posted rating folds in quiz performance: one wrong
    /// 選字/拼字 answer drops a level, two or more post 重來 — the self-rating
    /// alone said nothing about whether the user could actually retrieve the
    /// word. Fire-and-forget — UI shouldn't block on it. Pops the rating so
    /// each word writes exactly once; the backend tolerates duplicates.
    private func commitLearned(_ item: StudyQueueItem) {
        guard let rating = self.pendingRatings.removeValue(forKey: item.card.id) else { return }
        let wrongs = self.mistakes[item.word.id] ?? 0
        let effective: SRSRating = switch wrongs {
        case 0: rating
        case 1: rating.downgraded
        default: .again
        }
        let payload = StudyAnswerPayload(
            cardId: item.card.id,
            rating: effective,
            responseMs: self.identifyResponseMs[item.word.id],
            activity: "new_recognize"
        )
        // Tracked (not detached) so NewDoneView can drain it before reloading
        // mastery. Everything the response carries — mastery delta, streak
        // milestone, or a park — is folded in by StudySessionWrites.
        self.writes.submit(payload, wordId: item.word.id)
    }

    /// The user left. Drop the answer resolutions still waiting on their beat —
    /// without it, an answer given moments before ✕ still resolved, and still
    /// posted to the SRS, after the screen was gone — and stop the headword
    /// 認識 may still be saying.
    ///
    /// It used to be reached only from the ✕ prompt. A swipe-back skipped it;
    /// 複習 had covered that case since #189. The shell now calls this for both.
    func leave() {
        self.beats.cancelAll()
        self.audio.stop()
    }
}
