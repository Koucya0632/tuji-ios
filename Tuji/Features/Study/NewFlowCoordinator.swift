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

    /// Pending tasks; `tasks.first` is on screen. Empty ⇒ session finished.
    private(set) var tasks: [NewStudyTask]
    private(set) var finished = false

    /// Words that fully cleared all three stages (drives the header count).
    private(set) var clearedWords = 0

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
    /// Words whose 選字 was answered correctly — gates their 拼字 task.
    private var identifyCleared: Set<String> = []
    /// Words whose 選字 was dropped by the 已認識 fast path (subset of
    /// identifyCleared) — shown as a dimmed check in the stage pips.
    private var skippedIdentify: Set<String> = []
    /// Wrong-attempt counts per word id: reshuffles MCQ options, re-seeds the
    /// spell variant, and re-scrambles the tiles on each retry so position
    /// memory doesn't stand in for the word.
    private var identifyAttempts: [String: Int] = [:]
    private var spellAttempts: [String: Int] = [:]

    /// Completed stage count (recognize taps + correct 選字 + correct 拼字)
    /// out of `totalStages` — requeued retries don't inflate the denominator,
    /// so the header bar only ever moves forward.
    private var stageClears = 0
    /// Stages actually scheduled: 3 per word, minus the spell stage of
    /// single-tile subjects (a 1-tile board is a free answer, so those words
    /// finish after 選字).
    private var totalStages: Int

    /// In-flight SRS writes (POST /api/study/answer) fired by commitLearned.
    /// NewDoneView drains these before reloading mastery so the just-learned
    /// words don't show stale on the 圖鑑/詳情 (the write would otherwise race
    /// the reload, since it's fired optimistically without awaiting).
    private var pendingWrites: [Task<Void, Never>] = []
    /// Writes fired but not yet landed. The last word's write starts moments
    /// before the done screen's drain, so it's the one most likely to miss the
    /// bounded window — NewDoneView checks this to know a second drain +
    /// mastery reload is needed (otherwise that word stays 未學).
    private(set) var pendingWriteRemaining = 0

    /// Held-back recognize writes whose retries all failed — parked in the
    /// durable outbox by the writer. NewDoneView surfaces the count so an
    /// offline session doesn't silently look fully saved (mirrors
    /// ReviewFlowCoordinator.unsyncedCount).
    private(set) var parkedCount = 0

    var hasPendingWrites: Bool {
        self.pendingWriteRemaining > 0
    }

    private let writer: DurableAnswerWriting

    /// How long the app pauses on a locked answer before resolving it.
    ///
    /// Injected so the tested surface is the one the app calls. Before this,
    /// tests drove `resolveRecognize` / `resolveIdentify` / `resolveTiles`
    /// directly — which the app never calls — so the beats, the locks and
    /// everything between a tap and an SRS write had no coverage at all. It had
    /// already cost a duplicate: `resolveIdentify` carried a second latency
    /// capture whose only caller was the test suite.
    private let beat: @Sendable (Duration) async -> Void

    /// The answer resolutions in flight. Unstructured `Task`s that outlive the
    /// view: leaving mid-answer used to still fire the resolution — and its SRS
    /// write — on a coordinator whose screen was gone.
    private var pendingBeats: [Task<Void, Never>] = []

    /// How many tasks sit between a wrong answer and its retry.
    private static let requeueGap = 3

    init(
        queue: [StudyQueueItem],
        writer: DurableAnswerWriting = DurableAnswerWriter(),
        beat: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.queue = queue
        self.beat = beat
        let tasks = Self.initialSchedule(for: queue)
        self.tasks = tasks
        self.totalStages = tasks.count
        self.writer = writer
        self.afterMutation()
    }

    /// rec@3i, id@3i+4, spell@3i+8, stable-sorted by position. Guarantees each
    /// word's stages stay ordered while neighbouring words interleave between
    /// them (for w₀: 認識, then ~2 other tasks, then 選字, …). Words whose
    /// tile board has a single unit skip the spell stage entirely.
    private static func initialSchedule(for queue: [StudyQueueItem]) -> [NewStudyTask] {
        struct Slot {
            let pos: Int
            let order: Int
            let task: NewStudyTask
        }
        var scheduled: [Slot] = []
        func add(_ pos: Int, _ task: NewStudyTask) {
            scheduled.append(Slot(pos: pos, order: scheduled.count, task: task))
        }
        for (i, item) in queue.enumerated() {
            add(3 * i, NewStudyTask(item: item, kind: .recognize))
            add(3 * i + 4, NewStudyTask(item: item, kind: .identify))
            if self.tileBoard(for: item).unitCount >= 2 {
                add(3 * i + 8, NewStudyTask(item: item, kind: .spellTiles))
            }
        }
        return scheduled
            .sorted { ($0.pos, $0.order) < ($1.pos, $1.order) }
            .map(\.task)
    }

    var current: NewStudyTask? {
        self.tasks.first
    }

    var progress: Double {
        guard self.totalStages > 0 else { return 0 }
        return Double(self.stageClears) / Double(self.totalStages)
    }

    /// Stable identity for the current presentation: same task shown again
    /// after a wrong answer gets a new identity, so the task view's local
    /// state (e.g. assembled tiles) resets per attempt.
    var currentPresentationId: String {
        guard let task = current else { return "done" }
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
        let currentKind = self.current?.item.word.id == wordId ? self.current?.kind : nil

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
                state: self.skippedIdentify.contains(wordId)
                    ? .skipped
                    : state(.identify, done: self.identifyCleared.contains(wordId))
            )
        ]
        if Self.tileBoard(for: item).unitCount >= 2 {
            steps.append(NewStageStep(kind: .spellTiles, state: state(.spellTiles, done: false)))
        }
        return steps
    }

    // MARK: - Queue mechanics

    /// Pop the head after a completed stage. If the word has no tasks left,
    /// flush its held-back SRS write. "No tasks left" instead of "spell done"
    /// because stage counts vary per word (single-tile subjects skip spell);
    /// a wrong answer keeps its task queued, so this never commits early.
    private func completeCurrentTask() {
        guard let task = self.tasks.first else { return }
        self.tasks.removeFirst()
        self.stageClears += 1
        let wordId = task.item.word.id
        if !self.tasks.contains(where: { $0.item.word.id == wordId }) {
            self.clearedWords += 1
            self.commitLearned(task.item)
        }
        self.afterMutation()
    }

    /// Requeue the head a few positions back after a wrong answer.
    private func requeueCurrentTask() {
        guard !self.tasks.isEmpty else { return }
        let task = self.tasks.removeFirst()
        self.tasks.insert(task, at: min(Self.requeueGap, self.tasks.count))
        self.afterMutation()
    }

    private func afterMutation() {
        self.normalizeHead()
        if self.tasks.isEmpty {
            self.finished = true
        } else if let task = current, task.kind == .identify,
                  self.identifyShownAt[task.item.word.id] == nil
        {
            self.identifyShownAt[task.item.word.id] = Date()
        }
    }

    /// A requeued 選字 can end up *behind* its word's pre-scheduled 拼字 task;
    /// spelling a word the user just failed to recognise breaks the stage
    /// ladder, so push the 拼字 back behind the pending 選字. The loop guard
    /// bounds the degenerate all-heads-blocked case.
    private func normalizeHead() {
        var moved = 0
        while let head = tasks.first,
              head.kind == .spellTiles,
              !self.identifyCleared.contains(head.item.word.id),
              moved <= self.tasks.count
        {
            let spell = self.tasks.removeFirst()
            let idIdx = self.tasks.firstIndex {
                $0.kind == .identify && $0.item.word.id == spell.item.word.id
            }
            if let idIdx {
                self.tasks.insert(spell, at: min(idIdx + Self.requeueGap, self.tasks.count))
            } else {
                // No pending 選字 for this word (shouldn't happen) — tail it.
                self.tasks.append(spell)
            }
            moved += 1
        }
    }

    // MARK: - 認識 (recognize)

    func recognizeAnswer(rating: SRSRating) async {
        guard !self.recLocked, let task = current, task.kind == .recognize else { return }
        self.recLocked = true
        self.recRating = rating
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        try? await Task.sleep(for: .milliseconds(450))
        self.recRating = nil
        self.recLocked = false
        self.resolveRecognize(rating: rating)
    }

    /// Synchronous core, split from the button handler so unit tests can walk
    /// the scheduler without real sleeps.
    func resolveRecognize(rating: SRSRating) {
        guard let task = current, task.kind == .recognize else { return }
        // Hold the rating back; the SRS write fires only once this word clears
        // its final stage (see commitLearned). This keeps 今日目標 counting
        // full completions instead of bare recognize taps.
        self.pendingRatings[task.item.card.id] = rating
        // 已認識 fast path: skip straight to production. Tiles still gate the
        // commit, and a tile miss downgrades the rating — an overconfident
        // self-rating gets corrected there instead of by an easy MCQ.
        if rating == .good {
            self.skipIdentify(for: task.item)
        }
        self.completeCurrentTask()
    }

    /// Drop the word's pending 選字 task. Marking it cleared is load-bearing:
    /// normalizeHead() gates a head 拼字 on identifyCleared, so without the
    /// insert the word's tiles would be deferred forever.
    private func skipIdentify(for item: StudyQueueItem) {
        let wordId = item.word.id
        guard let idx = self.tasks.firstIndex(where: {
            $0.kind == .identify && $0.item.word.id == wordId
        })
        else { return }
        self.tasks.remove(at: idx)
        self.identifyCleared.insert(wordId)
        self.skippedIdentify.insert(wordId)
        self.totalStages -= 1
    }

    // MARK: - 選字 (identify)

    func identifyPick(_ choice: String) {
        guard !self.idLocked, let task = current, task.kind == .identify else { return }
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
        self.pendingBeats.append(Task {
            // Correct answers clear faster than wrong ones: momentum for the
            // fast-learning feel, while a miss keeps time to read the reveal.
            await self.beat(.milliseconds(ok ? 500 : 800))
            guard !Task.isCancelled else { return }
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
        })
    }

    /// Synchronous core: correct clears the stage; wrong records the mistake
    /// and raises the peek (requeue happens on advanceFromPeek()).
    func resolveIdentify(correct: Bool) {
        guard let task = current, task.kind == .identify else { return }
        if correct {
            self.identifyCleared.insert(task.item.word.id)
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

    /// The spell board as the view should draw it.
    ///
    /// `tilePicked` is one flat `[Int]` shared across every word, indexing a
    /// per-item, per-attempt unit list. Handing the view those two raw pieces
    /// meant both sides had to subscript one with the other — and they disagreed
    /// about what an out-of-range index means: `tilesMatch` bounds-checks and
    /// returns `false`, `TilesView.slotBox` did not and would trap. One frame
    /// during the `.id(currentPresentationId)` swap between a 7-tile board and a
    /// 3-tile board hits both readers at once.
    ///
    /// The view also re-derived the verdict the coordinator had just computed
    /// and thrown away. It is stored now, so "did they get it right" is answered
    /// once, where the answer is made.
    struct SpellBoard: Equatable {
        struct Slot: Equatable {
            /// nil = still empty.
            var unit: String?
        }

        struct Tile: Equatable {
            var unit: String
            var used: Bool
        }

        var slots: [Slot]
        var pool: [Tile]
        /// The original subject, spaces intact — what the 正解 line reveals.
        var subject: String
        /// How the units group into rows (a multi-word subject spells one row
        /// per word).
        var tokenUnits: [[String]]
        /// nil until the board fills and locks.
        var verdict: Bool?

        var isLocked: Bool {
            self.verdict != nil
        }
    }

    /// Latched when the board fills, cleared when it resets. Also what the view
    /// used to reconstruct as `boardFull && tiLocked`.
    private(set) var tilesVerdict: Bool?

    var spellBoard: SpellBoard? {
        guard let task = current, task.kind == .spellTiles else { return nil }
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
            subject: self.spellSubject(for: item),
            tokenUnits: Self.tileBoard(for: item).tokenUnits,
            verdict: self.tilesVerdict
        )
    }

    /// Scrambled tiles, seeded per (item, attempt) — see the core in
    /// NewFlowTasks.swift.
    func tileUnits(for item: StudyQueueItem) -> [String] {
        self.tileUnits(for: item, attempt: self.spellAttempts[item.word.id] ?? 0)
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
        return assembled == Self.tileBoard(for: item).target
    }

    /// Locks the board and, after a beat, resolves. Called by pickTile when the
    /// last slot fills.
    func tilesAnswer(correct: Bool) {
        guard !self.tiLocked, let task = current, task.kind == .spellTiles else { return }
        self.tiLocked = true
        self.pendingBeats.append(Task {
            await self.beat(.milliseconds(correct ? 450 : 800))
            guard !Task.isCancelled else { return }
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
        })
    }

    /// Synchronous core, also reachable from tests.
    func resolveTiles(correct: Bool) {
        guard let task = current, task.kind == .spellTiles else { return }
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
        guard let task = current else { return }
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
        // mastery — see pendingWrites / drainPendingWrites. A write the writer
        // can't land is parked; count it so the done screen can say so.
        self.pendingWriteRemaining += 1
        self.pendingWrites.append(Task {
            if case .parked = await self.writer.submitAnswer(payload) {
                self.parkedCount += 1
            }
            self.pendingWriteRemaining -= 1
        })
    }

    /// Give the optimistic recognize writes a bounded window to land before the
    /// completion screen reloads mastery/stats. Mirrors ReviewFlowCoordinator.
    /// Drop the answer resolutions still waiting on their beat. Called when the
    /// user leaves the session: without it, an answer given moments before ✕
    /// still resolved — and still posted to the SRS — after the screen was gone.
    func cancelPendingBeats() {
        for task in self.pendingBeats {
            task.cancel()
        }
        self.pendingBeats.removeAll()
    }

    func drainPendingWrites(within timeout: Duration) async {
        // Module-qualified: unqualified would resolve to this instance method
        // (member lookup wins over the global), recursing forever.
        await Tuji.drainPendingWrites(self.pendingWrites, within: timeout)
    }
}
