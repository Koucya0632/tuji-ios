// The 學新字 task queue, as list algebra.
//
// A session is ONE interleaved queue, not three blocked phases: each word walks
// 認識 → 選字 → 拼字 with other words' tasks in between, so the quiz retrieves
// from (short) memory instead of echoing the card just shown. This module owns
// that queue and nothing else — no beats, no locks, no SRS writes, no latency
// capture. It is a value type, so a test states a queue and reads an answer.
//
// It was already a module; it just had no interface. Living inside
// `NewFlowCoordinator` alongside six other responsibilities and twelve
// dictionaries, the only way to exercise it was through three internal methods
// — `resolveRecognize` / `resolveIdentify` / `resolveTiles` — that exist for the
// tests and that the app never calls. Eleven test call sites went through that
// door. **The interface is the test surface**: if the tests have to enter
// somewhere the app doesn't, the module is the wrong shape.

import Foundation

struct StudyLadder: Equatable {
    /// Pending tasks; `first` is on screen. Empty ⇒ the session is finished.
    private(set) var tasks: [NewStudyTask]

    /// Words whose 選字 was answered correctly — gates their 拼字 task.
    private(set) var identifyCleared: Set<String> = []

    /// Words whose 選字 was dropped by the 已認識 fast path (a subset of
    /// `identifyCleared`) — drawn as a dimmed check rather than a hole.
    private(set) var skippedIdentify: Set<String> = []

    /// Words that cleared every stage they were scheduled.
    private(set) var clearedWords = 0

    /// Completed stage count out of `totalStages`. Requeued retries don't
    /// inflate the denominator, so the header bar only moves forward.
    private(set) var stageClears = 0

    /// Stages actually scheduled: 3 per word, minus the 拼字 of single-unit
    /// subjects (a 1-tile board is a free answer, so those words finish after
    /// 選字). Shrinks again when the 已認識 fast path drops a 選字.
    private(set) var totalStages: Int

    /// How many tasks sit between a wrong answer and its retry.
    static let requeueGap = 3

    init(queue: [StudyQueueItem]) {
        let tasks = Self.initialSchedule(for: queue)
        self.tasks = tasks
        self.totalStages = tasks.count
        self.normalizeHead()
    }

    // MARK: - Reading

    var current: NewStudyTask? {
        self.tasks.first
    }

    var finished: Bool {
        self.tasks.isEmpty
    }

    var progress: Double {
        guard self.totalStages > 0 else { return 0 }
        return Double(self.stageClears) / Double(self.totalStages)
    }

    /// Whether this word still has a 拼字 stage on its ladder.
    func hasSpellStage(_ item: StudyQueueItem) -> Bool {
        TileBoard.of(item).unitCount >= 2
    }

    // MARK: - Mutating

    /// Pop the head after a completed stage.
    ///
    /// Returns the item **only when that word has no tasks left**, which is the
    /// signal the caller needs to flush its held-back SRS write. "No tasks left"
    /// rather than "拼字 done" because stage counts vary per word, and a wrong
    /// answer keeps its task queued — so this never reports early.
    @discardableResult
    mutating func completeCurrent() -> StudyQueueItem? {
        guard let task = self.tasks.first else { return nil }
        self.tasks.removeFirst()
        self.stageClears += 1
        let wordId = task.item.word.id
        let wordIsDone = !self.tasks.contains { $0.item.word.id == wordId }
        if wordIsDone {
            self.clearedWords += 1
        }
        self.normalizeHead()
        return wordIsDone ? task.item : nil
    }

    /// Requeue the head a few positions back after a wrong answer.
    mutating func requeueCurrent() {
        guard !self.tasks.isEmpty else { return }
        let task = self.tasks.removeFirst()
        self.tasks.insert(task, at: min(Self.requeueGap, self.tasks.count))
        self.normalizeHead()
    }

    /// Record that this word's 選字 was answered correctly.
    mutating func markIdentifyCleared(_ wordId: String) {
        self.identifyCleared.insert(wordId)
    }

    /// The 已認識 fast path: drop the word's pending 選字 task.
    ///
    /// Marking it cleared is load-bearing — `normalizeHead` gates a head 拼字 on
    /// `identifyCleared`, so without the insert the word's tiles would be
    /// deferred forever.
    mutating func skipIdentify(for item: StudyQueueItem) {
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

    // MARK: - Internals

    /// rec@3i, id@3i+4, spell@3i+8, stable-sorted by position. Guarantees each
    /// word's stages stay ordered while neighbouring words interleave between
    /// them (for w₀: 認識, then ~2 other tasks, then 選字, …). Words whose tile
    /// board has a single unit skip the 拼字 stage entirely.
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
            if TileBoard.of(item).unitCount >= 2 {
                add(3 * i + 8, NewStudyTask(item: item, kind: .spellTiles))
            }
        }
        return scheduled
            .sorted { ($0.pos, $0.order) < ($1.pos, $1.order) }
            .map(\.task)
    }

    /// A requeued 選字 can end up *behind* its word's pre-scheduled 拼字 task;
    /// spelling a word the user just failed to recognise breaks the stage
    /// ladder, so push the 拼字 back behind the pending 選字. The loop guard
    /// bounds the degenerate all-heads-blocked case.
    private mutating func normalizeHead() {
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
}
