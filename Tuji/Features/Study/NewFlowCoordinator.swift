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
final class NewFlowCoordinator {
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
    var tiLocked: Bool = false

    /// Tiles tapped into slots, in tap order — indices into `tileUnits(for:)`.
    /// Index-based so duplicate units stay distinguishable. Owned here (not in
    /// TilesView) so the assemble-and-compare is a testable coordinator decision;
    /// reset when the spell task advances (correct) or requeues (wrong).
    private(set) var tilePicked: [Int] = []

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
    /// Wrong-attempt counts per word id: reshuffles MCQ options, re-seeds the
    /// spell variant, and re-scrambles the tiles on each retry so position
    /// memory doesn't stand in for the word.
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
    /// `resolveTiles` directly — which the app never calls — so the beats, the
    /// locks and everything between a tap and an SRS write had no coverage at
    /// all. It had already cost a duplicate: `resolveIdentify` carried a second
    /// latency capture whose only caller was the test suite.
    ///
    /// See `AnswerBeat`, which 複習 holds too.
    private let beats: AnswerBeat

    init(
        queue: [StudyQueueItem],
        writer: DurableAnswerWriting = DurableAnswerWriter(),
        beat: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.queue = queue
        self.beats = AnswerBeat(sleep: beat)
        self.ladder = StudyLadder(queue: queue)
        self.writes = StudySessionWrites(writer: writer)
        self.stampIdentifyShown()
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

    /// Stable identity for the current presentation: same task shown again
    /// after a wrong answer gets a new identity, so the task view's local
    /// state (e.g. assembled tiles) resets per attempt.
    var currentPresentationId: String {
        guard let task = ladder.current else { return "done" }
        let attempt = switch task.kind {
        case .recognize: 0
        case .identify: self.identifyAttempts[task.item.word.id] ?? 0
        case .spellTiles: self.spellAttempts[task.item.word.id] ?? 0
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
            steps.append(NewStageStep(kind: .spellTiles, state: state(.spellTiles, done: false)))
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
        self.stampIdentifyShown()
    }

    private func requeueCurrentTask() {
        self.ladder.requeueCurrent()
        self.stampIdentifyShown()
    }

    /// Start the first-attempt clock the moment a 選字 task reaches the head.
    /// Latency capture is this coordinator's business, not the ladder's, which
    /// is why it sits beside the mutation rather than inside it.
    private func stampIdentifyShown() {
        guard let task = ladder.current, task.kind == .identify,
              self.identifyShownAt[task.item.word.id] == nil
        else { return }
        self.identifyShownAt[task.item.word.id] = Date()
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
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
                Int(Date().timeIntervalSince(shownAt) * 1000)
        }
        let ok = choice == task.item.word.word
        // Correct answers clear faster than wrong ones: momentum for the
        // fast-learning feel, while a miss keeps time to read the reveal.
        self.beats.schedule(after: .milliseconds(ok ? 500 : 800)) {
            if ok {
                self.idLocked = false
                self.idPicked = nil
                self.resolveIdentify(correct: true)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                // Wrong: stay frozen on this item (keep idLocked / idPicked so
                // the wrong + answer highlight stays) and surface the peek
                // sheet. Advancing — requeue a few positions back — is
                // deferred to advanceFromPeek(), fired when the user taps
                // 下一題 / dismisses the sheet.
                self.resolveIdentify(correct: false)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
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

    // MARK: - 拼字塊 (letter tiles)

    /// Latched when the board fills, cleared when it resets. Also what the view
    /// used to reconstruct as `boardFull && tiLocked`.
    private(set) var tilesVerdict: Bool?

    var spellBoard: SpellBoard? {
        guard let task = ladder.current, task.kind == .spellTiles else { return nil }
        let item = task.item
        let units = self.tileUnits(for: item)
        let placed = self.tilePicked.filter { units.indices.contains($0) }
        return SpellBoard(
            slots: (0..<units.count).map { slot in
                SpellBoard.Slot(unit: slot < placed.count ? units[placed[slot]] : nil)
            },
            pool: units.enumerated().map { index, unit in
                SpellBoard.Tile(unit: unit, used: self.tilePicked.contains(index))
            },
            subject: TileBoard.spellSubject(for: item),
            tokenUnits: TileBoard.of(item).tokenUnits,
            verdict: self.tilesVerdict
        )
    }

    /// Scrambled tiles, seeded per (item, attempt) — see the core in
    /// NewFlowTasks.swift.
    func tileUnits(for item: StudyQueueItem) -> [String] {
        TileBoard.units(for: item, attempt: self.spellAttempts[item.word.id] ?? 0)
    }

    /// Tap a pool tile into the next slot. Auto-checks when the board fills. A
    /// no-op once locked, off a non-spell task, or if the tile is already placed.
    func pickTile(_ idx: Int) {
        guard !self.tiLocked, let task = current, task.kind == .spellTiles,
              !self.tilePicked.contains(idx)
        else { return }
        self.tilePicked.append(idx)
        let units = self.tileUnits(for: task.item)
        if self.tilePicked.count == units.count {
            let correct = self.tilesMatch(self.tilePicked, for: task.item)
            self.tilesVerdict = correct
            self.tilesAnswer(correct: correct)
        }
    }

    /// Tap a filled slot to take that tile back out (before the board locks).
    func unpickTile(atSlot slot: Int) {
        guard !self.tiLocked, slot < self.tilePicked.count else { return }
        self.tilePicked.remove(at: slot)
    }

    /// Does this pick sequence spell the target? Pure — the correctness decision
    /// the production step turns on, testable without driving the board.
    func tilesMatch(_ picked: [Int], for item: StudyQueueItem) -> Bool {
        let units = self.tileUnits(for: item)
        let assembled = picked.compactMap { units.indices.contains($0) ? units[$0] : nil }.joined()
        return assembled == TileBoard.of(item).target
    }

    /// Locks the board and, after a beat, resolves. Called by pickTile when the
    /// last slot fills.
    func tilesAnswer(correct: Bool) {
        guard !self.tiLocked, let task = current, task.kind == .spellTiles else { return }
        self.tiLocked = true
        self.beats.schedule(after: .milliseconds(correct ? 450 : 800)) {
            if correct {
                self.tiLocked = false
                self.resolveTiles(correct: true)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                // Stay frozen (tiles show red) and surface the peek; the
                // requeue + rescramble happen on advanceFromPeek().
                self.resolveTiles(correct: false)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }
    }

    /// Synchronous core, also reachable from tests.
    func resolveTiles(correct: Bool) {
        guard let task = ladder.current, task.kind == .spellTiles else { return }
        if correct {
            self.completeCurrentTask()
            // The next spell task (whenever it surfaces) starts from an empty
            // board. Wrong answers keep the picks so the red board stays until
            // advanceFromPeek() requeues + clears.
            self.tilePicked = []
            self.tilesVerdict = nil
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
        case .spellTiles:
            self.tiLocked = false
            self.tilePicked = []
            self.tilesVerdict = nil
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

    /// Drop the answer resolutions still waiting on their beat. Called when the
    /// user leaves the session: without it, an answer given moments before ✕
    /// still resolved — and still posted to the SRS — after the screen was gone.
    func cancelPendingBeats() {
        self.beats.cancelAll()
    }
}
