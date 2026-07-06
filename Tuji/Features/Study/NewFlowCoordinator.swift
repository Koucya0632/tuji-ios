// State machine for the "learn new words" micro lesson (§III.P).
//
// The session is ONE interleaved task queue, not three blocked phases: each
// word walks 認識 → 選字 → 拼字 with other words' tasks in between, so the
// quiz retrieves from (short) memory instead of echoing the card just shown.
// Initial schedule places rec(wᵢ)@3i, id(wᵢ)@3i+4, spell(wᵢ)@3i+8 and sorts —
// a steady cadence with 2-3 tasks of lag between a word's stages. Wrong
// answers requeue the same task a few positions later; a requeued 選字 that
// would slip behind its word's pre-scheduled 拼字 is caught by normalizeHead()
// so the stage ladder always holds.
//
// SRS: the recognize self-rating is held back per word and posted once that
// word clears its final stage (今日目標 counts full completions only). The
// posted rating is downgraded by quiz performance — one wrong answer drops a
// level, two or more post 重來 — and carries the first-attempt 選字 latency
// as responseMs, so the scheduler learns from behaviour, not just self-report.
// 選字/拼字 are otherwise practice-only (no extra POST per answer).

import OSLog
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

    /// Consecutive correct quiz answers (選字/拼字; resets on a miss). At 3+
    /// the question bubbles swap the mascot to its cheer pose — a tiny
    /// momentum reward that costs nothing but reuses existing art.
    private(set) var combo = 0

    // Transient per-kind UI state (the task views read these).
    var recRating: SRSRating?
    var recLocked: Bool = false
    var idPicked: String?
    var idLocked: Bool = false
    var tiLocked: Bool = false

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

    var hasPendingWrites: Bool {
        self.pendingWriteRemaining > 0
    }

    private let log = Logger(subsystem: "app.tuji.ios", category: "new-flow")
    private let repository: StudyRepository

    /// How many tasks sit between a wrong answer and its retry.
    private static let requeueGap = 3

    init(queue: [StudyQueueItem], repository: StudyRepository = LiveStudyRepository.shared) {
        self.queue = queue
        let tasks = Self.initialSchedule(for: queue)
        self.tasks = tasks
        self.totalStages = tasks.count
        self.repository = repository
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
        self.completeCurrentTask()
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
        Task {
            try? await Task.sleep(for: .milliseconds(800))
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
        guard let task = current, task.kind == .identify else { return }
        // Fallback latency capture for callers that skip identifyPick (tests);
        // the app path already recorded a more accurate value at pick time.
        if let shownAt = self.identifyShownAt[task.item.word.id],
           self.identifyResponseMs[task.item.word.id] == nil
        {
            self.identifyResponseMs[task.item.word.id] =
                Int(Date().timeIntervalSince(shownAt) * 1000)
        }
        if correct {
            self.combo += 1
            self.identifyCleared.insert(task.item.word.id)
            self.completeCurrentTask()
        } else {
            self.combo = 0
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

    /// Scrambled tiles, seeded per (item, attempt) — see the core in
    /// NewFlowTasks.swift.
    func tileUnits(for item: StudyQueueItem) -> [String] {
        self.tileUnits(for: item, attempt: self.spellAttempts[item.word.id] ?? 0)
    }

    /// Called by TilesView once every slot is filled.
    func tilesAnswer(correct: Bool) {
        guard !self.tiLocked, let task = current, task.kind == .spellTiles else { return }
        self.tiLocked = true
        Task {
            try? await Task.sleep(for: .milliseconds(correct ? 600 : 800))
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

    /// Synchronous core for tests.
    func resolveTiles(correct: Bool) {
        guard let task = current, task.kind == .spellTiles else { return }
        if correct {
            self.combo += 1
            self.completeCurrentTask()
        } else {
            self.combo = 0
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
        // mastery — see pendingWrites / drainPendingWrites.
        self.pendingWriteRemaining += 1
        self.pendingWrites.append(Task {
            await self.repository.submitAnswerBestEffort(payload)
            self.pendingWriteRemaining -= 1
        })
    }

    /// Give the optimistic recognize writes a bounded window to land before the
    /// completion screen reloads mastery/stats. Mirrors ReviewFlowCoordinator.
    func drainPendingWrites(within timeout: Duration) async {
        // Module-qualified: unqualified would resolve to this instance method
        // (member lookup wins over the global), recursing forever.
        await Tuji.drainPendingWrites(self.pendingWrites, within: timeout)
    }
}
