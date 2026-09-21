// Pins the synchronous parts of the interleaved new-word lesson: queue
// decoding (including the int-or-string card id the backend emits), the
// initial task interleave + the stage-ladder guard, the tile board layout +
// seeded scrambles, and the mistake-downgraded SRS commit. The async
// lock/sleep choreography is exercised in the app, not here — tests walk the
// scheduler through the resolve* synchronous cores.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct NewFlowCoordinatorTests {
    /// Three-item queue: an EN word (int card id, spellingChoices attached),
    /// a JA word with a kana reading distinct from the term (string card id),
    /// and a kana-only JA word whose reading equals the term.
    private func makeQueue() throws -> [StudyQueueItem] {
        let json = """
        [
          {
            "card": { "id": 101, "cardType": "flashcard", "deckKey": "core" },
            "word": {
              "id": "w-apple", "word": "apple", "chinese": "蘋果", "imageUrl": "",
              "pronunciation": "ˈæp.əl", "reading": null, "targetLanguage": "en", "category": "food"
            },
            "choices": ["apple", "banana", "cherry"],
            "spellingChoices": ["appel", "aple"],
            "mastery": 10
          },
          {
            "card": { "id": "202", "cardType": "flashcard", "deckKey": "core" },
            "word": {
              "id": "w-ringo", "word": "林檎", "chinese": "蘋果", "imageUrl": "",
              "pronunciation": "", "reading": "りんご", "targetLanguage": "ja", "category": "food"
            },
            "choices": null,
            "spellingChoices": null,
            "mastery": null
          },
          {
            "card": { "id": 303, "cardType": "flashcard", "deckKey": "core" },
            "word": {
              "id": "w-neko", "word": "ねこ", "chinese": "貓", "imageUrl": "",
              "pronunciation": "", "reading": "ねこ", "targetLanguage": "ja", "category": "animal"
            },
            "choices": null,
            "spellingChoices": null,
            "mastery": null
          }
        ]
        """
        return try JSONDecoder.tuji.decode([StudyQueueItem].self, from: Data(json.utf8))
    }

    /// Single multi-word EN item — 12 letters across two tokens, so its tile
    /// board chunks units and lays out two slot rows.
    private func makeMultiWordQueue() throws -> [StudyQueueItem] {
        let json = """
        [
          {
            "card": { "id": 404, "cardType": "flashcard", "deckKey": "core" },
            "word": {
              "id": "w-board", "word": "cutting board", "chinese": "砧板", "imageUrl": "",
              "pronunciation": "", "reading": null, "targetLanguage": "en", "category": "kitchen"
            },
            "choices": null,
            "spellingChoices": null,
            "mastery": null
          }
        ]
        """
        return try JSONDecoder.tuji.decode([StudyQueueItem].self, from: Data(json.utf8))
    }

    /// JA items exercising kana tiling: a yōon reading (きょう) whose small
    /// kana must merge into the preceding unit, and a single-kana reading (め)
    /// whose 1-tile board would be a free answer.
    private func makeKanaEdgeQueue() throws -> [StudyQueueItem] {
        let json = """
        [
          {
            "card": { "id": 505, "cardType": "flashcard", "deckKey": "core" },
            "word": {
              "id": "w-kyou", "word": "今日", "chinese": "今天", "imageUrl": "",
              "pronunciation": "", "reading": "きょう", "targetLanguage": "ja", "category": "time"
            },
            "choices": null,
            "spellingChoices": null,
            "mastery": null
          },
          {
            "card": { "id": 606, "cardType": "flashcard", "deckKey": "core" },
            "word": {
              "id": "w-me", "word": "目", "chinese": "眼睛", "imageUrl": "",
              "pronunciation": "", "reading": "め", "targetLanguage": "ja", "category": "body"
            },
            "choices": null,
            "spellingChoices": null,
            "mastery": null
          }
        ]
        """
        return try JSONDecoder.tuji.decode([StudyQueueItem].self, from: Data(json.utf8))
    }

    @Test
    func decodesIntAndStringCardIds() throws {
        let queue = try self.makeQueue()
        #expect(queue.map(\.card.id) == ["101", "202", "303"])
        #expect(queue[0].spellingChoices == ["appel", "aple"])
    }

    // MARK: - Scheduling

    @Test
    func initialScheduleInterleavesStages() throws {
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        // rec@3i, id@3i+4, spell@3i+8 sorted by position: each word's stages
        // stay ordered with other words' tasks between them.
        let expected: [(String, NewTaskKind)] = [
            ("w-apple", .recognize),
            ("w-ringo", .recognize),
            ("w-apple", .identify),
            ("w-neko", .recognize),
            ("w-ringo", .identify),
            ("w-apple", .spell),
            ("w-neko", .identify),
            ("w-ringo", .spell),
            ("w-neko", .spell)
        ]
        #expect(c.ladder.tasks.map(\.item.word.id) == expected.map(\.0))
        #expect(c.ladder.tasks.map(\.kind) == expected.map(\.1))
    }

    @Test
    func singleUnitSubjectSkipsSpellStageAndStillCommits() async throws {
        let queue = try [self.makeKanaEdgeQueue()[1]]
        let spy = SpyAnswerWriter()
        let c = NewFlowCoordinator(queue: queue, writer: spy)
        // A 1-tile board is a free answer, so め gets no spell task…
        #expect(c.ladder.tasks.map(\.kind) == [.recognize, .identify])
        c.resolveRecognize(rating: .hard)
        #expect(abs(c.progress - 0.5) < 0.0001)
        c.resolveIdentify(correct: true)
        // …and the word commits after 選字 clears.
        #expect(c.finished)
        #expect(c.clearedWords == 1)
        #expect(c.progress == 1.0)
        await c.writes.drainPendingWrites(within: .seconds(2))
        #expect(spy.answers.map(\.rating) == ["困難"])
    }

    @Test
    func wrongIdentifyRequeuesAFewBackAndSpellWaitsForIt() throws {
        let queue = try Array(self.makeQueue().prefix(2))
        let c = NewFlowCoordinator(queue: queue)
        // n=2 schedule: r0 r1 i0 i1 s0 s1. (.hard keeps the full ladder —
        // .good would fast-path past 選字.)
        c.resolveRecognize(rating: .hard)
        c.resolveRecognize(rating: .hard)
        #expect(c.current?.kind == .identify)
        // Wrong 選字 for w-apple: freeze + peek, requeue on peek dismiss.
        c.resolveIdentify(correct: false)
        #expect(c.peek?.id == "w-apple")
        c.advanceFromPeek()
        // Retry re-shuffles its options.
        #expect(c.choicesVariant(for: queue[0]) == 1)
        // Correct 選字 for w-ringo…
        #expect(c.current?.item.word.id == "w-ringo")
        c.resolveIdentify(correct: true)
        // …and apple's pre-scheduled 拼字 may now be at the head, but apple
        // hasn't cleared 選字 — the guard must keep the stage ladder intact:
        // ringo's spell first, then apple's identify retry, then apple's spell.
        #expect(c.ladder.tasks.map(\.id) == [
            "w-ringo#spell_tiles",
            "w-apple#identify",
            "w-apple#spell_tiles"
        ])
    }

    @Test
    func progressCountsStageClears() throws {
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        #expect(c.progress == 0)
        c.resolveRecognize(rating: .hard)
        // One cleared stage of 9 (3 items × 3 stages).
        #expect(abs(c.progress - 1.0 / 9.0) < 0.0001)
    }

    // MARK: - 已認識 fast path

    @Test
    func goodSelfRatingSkipsIdentifyAndKeepsProgressMonotone() async throws {
        let queue = try Array(self.makeQueue().prefix(2))
        let spy = SpyAnswerWriter()
        let c = NewFlowCoordinator(queue: queue, writer: spy)
        // Schedule r0 r1 i0 i1 s0 s1 → 已認識 on w-apple drops i0.
        var lastProgress = c.progress
        func expectMonotone() {
            #expect(c.progress >= lastProgress)
            lastProgress = c.progress
        }
        c.resolveRecognize(rating: .good)
        #expect(!c.ladder.tasks.contains { $0.kind == .identify && $0.item.word.id == "w-apple" })
        #expect(c.stagePlan(for: queue[0]).first { $0.kind == .identify }?.state == .skipped)
        expectMonotone()
        c.resolveRecognize(rating: .hard)
        expectMonotone()
        // w-ringo keeps its 選字; apple's tiles surface right after despite
        // never running 選字 (skip marks it cleared for normalizeHead).
        #expect(c.current?.kind == .identify)
        #expect(c.current?.item.word.id == "w-ringo")
        c.resolveIdentify(correct: true)
        expectMonotone()
        #expect(c.current?.kind == .spell)
        #expect(c.current?.item.word.id == "w-apple")
        c.resolveSpell(correct: true)
        expectMonotone()
        // Denominator shrank to 5 (6 scheduled − 1 skipped): 4 clears in.
        #expect(abs(c.progress - 4.0 / 5.0) < 0.0001)
        c.resolveSpell(correct: true)
        #expect(c.finished)
        #expect(c.clearedWords == 2)
        #expect(c.progress == 1.0)
        await c.writes.drainPendingWrites(within: .seconds(2))
        #expect(spy.answers.map(\.rating) == ["穩定", "困難"])
    }

    @Test
    func fastPathWrongTilesRequeuesWithoutStalling() async throws {
        let queue = try Array(self.makeQueue().prefix(1))
        let spy = SpyAnswerWriter()
        let c = NewFlowCoordinator(queue: queue, writer: spy)
        c.resolveRecognize(rating: .good)
        // Identify skipped → straight to production.
        #expect(c.current?.kind == .spell)
        c.resolveSpell(correct: false)
        #expect(c.peek?.id == "w-apple")
        c.advanceFromPeek()
        // Requeued tiles must come back (not be deferred by normalizeHead).
        #expect(c.current?.kind == .spell)
        c.resolveSpell(correct: true)
        #expect(c.finished)
        await c.writes.drainPendingWrites(within: .seconds(2))
        // The tile miss corrects the overconfident self-rating: 穩定 → 困難.
        #expect(spy.answers.map(\.rating) == ["困難"])
    }

    @Test
    func singleUnitWordRatedGoodCommitsAfterRecognize() async throws {
        let queue = try [self.makeKanaEdgeQueue()[1]]
        let spy = SpyAnswerWriter()
        let c = NewFlowCoordinator(queue: queue, writer: spy)
        // め has no spell stage; 已認識 also drops 選字 → one-task word.
        c.resolveRecognize(rating: .good)
        #expect(c.finished)
        #expect(c.clearedWords == 1)
        #expect(c.progress == 1.0)
        await c.writes.drainPendingWrites(within: .seconds(2))
        #expect(spy.answers.map(\.rating) == ["穩定"])
    }

    // MARK: - Seeded tile scrambles

    @Test
    func choicesReshuffleAcrossVariants() throws {
        let queue = try self.makeQueue()
        let apple = queue[0]
        let pool = [
            CardWord(id: "p1", word: "banana", chinese: "香蕉", imageUrl: "", category: "food", pronunciation: ""),
            CardWord(id: "p2", word: "cherry", chinese: "櫻桃", imageUrl: "", category: "food", pronunciation: ""),
            CardWord(id: "p3", word: "grape", chinese: "葡萄", imageUrl: "", category: "food", pronunciation: ""),
            CardWord(id: "p4", word: "lemon", chinese: "檸檬", imageUrl: "", category: "food", pronunciation: "")
        ]
        let base = studyChoices(for: apple, pool: pool, session: .en, variant: 0)
        #expect(base.contains("apple"))
        // Some later variant must present a different order — otherwise a
        // requeued question can be answered from remembered positions.
        let reshuffled = (1...4).map { studyChoices(for: apple, pool: pool, session: .en, variant: $0) }
        #expect(reshuffled.contains { $0 != base })
    }

    // MARK: - SRS commit (mistake downgrade + latency)

    @Test
    func cleanRunPostsSelfRating() async throws {
        let queue = try self.makeMultiWordQueue()
        let spy = SpyAnswerWriter()
        let c = NewFlowCoordinator(queue: queue, writer: spy)
        c.resolveRecognize(rating: .hard)
        c.resolveIdentify(correct: true)
        c.resolveSpell(correct: true)
        #expect(c.finished)
        #expect(c.clearedWords == 1)
        await c.writes.drainPendingWrites(within: .seconds(2))
        #expect(spy.answers.map(\.rating) == ["困難"])
    }

    @Test
    func theAnswerPathTheAppCallsRecordsLatency() async throws {
        // This used to be unreachable. The app calls `identifyPick`, which locks
        // and then resolves after a 500 ms beat inside an escaping Task; the
        // tests called `resolveIdentify` directly, which the app never does. So
        // the latency the scheduler actually learns from had no coverage, and
        // `resolveIdentify` grew a second capture whose only caller was a test.
        //
        // With the beat injected, the tested surface is the shipped one.
        //
        // With the clock injected too, the number itself is asserted — it used
        // to be read from `Date()` inline, and the most a test could say was
        // that it was not nil.
        let queue = try self.makeMultiWordQueue()
        let spy = SpyAnswerWriter()
        let clock = NewFlowTestClock()
        let c = NewFlowCoordinator(queue: queue, writer: spy, beat: { _ in }, now: { clock.now })
        c.resolveRecognize(rating: .hard) // 選字 surfaces now, and its clock starts
        clock.now += 2.5
        try c.identifyPick(#require(c.current).item.word.word)
        // Let the (now instant) beat run.
        await Task.yield()
        c.resolveSpell(correct: true)
        await c.writes.drainPendingWrites(within: .seconds(2))
        #expect(spy.answers.first?.responseMs == 2500)
    }

    @Test
    func leavingMidAnswerStopsTheResolution() async throws {
        // ✕ → 先離開 within the beat used to still resolve the answer and post
        // its SRS write, on a coordinator whose screen was already gone.
        let queue = try self.makeMultiWordQueue()
        let spy = SpyAnswerWriter()
        let c = NewFlowCoordinator(queue: queue, writer: spy, beat: { _ in
            // Long enough that cancellation lands first.
            try? await Task.sleep(for: .milliseconds(200))
        })
        c.resolveRecognize(rating: .hard)
        let before = c.clearedWords
        try c.identifyPick(#require(c.current).item.word.word)
        c.leave()
        try? await Task.sleep(for: .milliseconds(300))
        #expect(c.clearedWords == before)
        #expect(spy.answers.isEmpty)
    }

    /// The same guarantee for 認識, which never had it: that beat hardcoded its
    /// own sleep instead of the injected one and was never appended to
    /// `pendingBeats`, so 先離開 could not reach it. A single-unit word rated
    /// 已認識 skips 選字 and has no 拼字, so the tap alone runs the SRS write —
    /// which is exactly the case that leaked past the screen.
    @Test
    func leavingDuringTheRecognizeBeatStopsItsWrite() async throws {
        let queue = try self.makeKanaEdgeQueue() // w-me is a single-unit subject
        let spy = SpyAnswerWriter()
        let c = NewFlowCoordinator(queue: queue, writer: spy, beat: { _ in
            try? await Task.sleep(for: .milliseconds(200))
        })
        let before = c.clearedWords

        c.recognizeAnswer(rating: .good)
        c.leave()
        try? await Task.sleep(for: .milliseconds(300))
        await c.writes.drainPendingWrites(within: .milliseconds(200))

        #expect(c.clearedWords == before)
        #expect(spy.answers.isEmpty)
        #expect(c.recLocked) // frozen mid-answer; the screen is gone anyway
    }

    @Test
    func theRecognizeBeatResolvesWhenItIsNotCancelled() async throws {
        let queue = try self.makeKanaEdgeQueue()
        let spy = SpyAnswerWriter()
        let c = NewFlowCoordinator(queue: queue, writer: spy, beat: { _ in })

        c.recognizeAnswer(rating: .good)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(!c.recLocked)
        #expect(c.recRating == nil)
        #expect(c.current?.kind != .recognize || c.current?.item.word.id != "w-kyou")
    }

    @Test
    func oneMistakeDowngradesOneLevel() async throws {
        let queue = try Array(self.makeQueue().prefix(1))
        let spy = SpyAnswerWriter()
        let c = NewFlowCoordinator(queue: queue, writer: spy)
        // .good fast-paths to tiles; the one tile miss drops 穩定 → 困難.
        c.resolveRecognize(rating: .good)
        c.resolveSpell(correct: false)
        c.advanceFromPeek()
        c.resolveSpell(correct: true)
        #expect(c.finished)
        await c.writes.drainPendingWrites(within: .seconds(2))
        #expect(spy.answers.map(\.rating) == ["困難"])
    }

    @Test
    func identifyMistakeDowngradesOnFullLadder() async throws {
        let queue = try Array(self.makeQueue().prefix(1))
        let spy = SpyAnswerWriter()
        let c = NewFlowCoordinator(queue: queue, writer: spy)
        c.resolveRecognize(rating: .hard)
        c.resolveIdentify(correct: false)
        c.advanceFromPeek()
        c.resolveIdentify(correct: true)
        c.resolveSpell(correct: true)
        #expect(c.finished)
        await c.writes.drainPendingWrites(within: .seconds(2))
        #expect(spy.answers.map(\.rating) == ["重來"])
    }

    @Test
    func twoMistakesPostAgain() async throws {
        let queue = try Array(self.makeQueue().prefix(1))
        let spy = SpyAnswerWriter()
        let c = NewFlowCoordinator(queue: queue, writer: spy)
        c.resolveRecognize(rating: .good)
        c.resolveSpell(correct: false)
        c.advanceFromPeek()
        c.resolveSpell(correct: false)
        c.advanceFromPeek()
        c.resolveSpell(correct: true)
        #expect(c.finished)
        await c.writes.drainPendingWrites(within: .seconds(2))
        #expect(spy.answers.map(\.rating) == ["重來"])
    }

    @Test
    func downgradeMapping() {
        #expect(SRSRating.easy.downgraded == .good)
        #expect(SRSRating.good.downgraded == .hard)
        #expect(SRSRating.hard.downgraded == .again)
        #expect(SRSRating.again.downgraded == .again)
    }

    // MARK: - 拼字 (the production step's correctness decision)

    /// Advance past whatever stage is on screen, without answering wrongly —
    /// enough to walk the interleaved queue to the first 拼字 task.
    private func clearCurrentStage(_ c: NewFlowCoordinator) {
        switch c.current?.kind {
        case .recognize: c.resolveRecognize(rating: .hard)
        case .identify: c.resolveIdentify(correct: true)
        case .spell, .none: break
        }
    }

    /// Walk to one particular word's 拼字 task, clearing everything in front of
    /// it. Which board that task draws depends on the word — English takes the
    /// gap-fill and a kana reading the tile board — so a test has to name the
    /// word it means instead of taking the first 拼字 it reaches.
    private func walkToSpell(_ c: NewFlowCoordinator, wordId: String) {
        while let task = c.current, !(task.kind == .spell && task.item.word.id == wordId) {
            switch task.kind {
            case .recognize: c.resolveRecognize(rating: .hard)
            case .identify: c.resolveIdentify(correct: true)
            case .spell: c.resolveSpell(correct: true)
            }
        }
    }

    @Test
    func pickingTilesFillsSlotsAndDimsThePool() throws {
        // The board the view draws had no value to assert on: it was six
        // computed properties over `spellPicked` × `spellPool(for:)`, private to
        // TilesView. `pickSpell` and `unpickSpell` had no tests at all.
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        // 林檎 is quizzed on its kana reading, which still takes tiles.
        self.walkToSpell(c, wordId: "w-ringo")
        let board = try #require(c.spellBoard)
        #expect(board.slots.allSatisfy { $0.unit == nil })
        #expect(board.pool.allSatisfy { !$0.used })
        #expect(board.verdict == nil)

        c.pickSpell(0)
        let afterPick = try #require(c.spellBoard)
        #expect(afterPick.slots[0].unit == board.pool[0].unit)
        #expect(afterPick.pool[0].used)
        // A tile already placed cannot be placed twice.
        c.pickSpell(0)
        #expect(try #require(c.spellBoard).slots[1].unit == nil)

        c.unpickSpell(atSlot: 0)
        let afterUnpick = try #require(c.spellBoard)
        #expect(afterUnpick.slots[0].unit == nil)
        #expect(!afterUnpick.pool[0].used)
    }

    @Test
    func aWrongBoardFreezesWithItsVerdictAndTheAnswerUnderIt() throws {
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        self.walkToSpell(c, wordId: "w-ringo")
        let item = try #require(c.current).item
        let units = c.spellPool(for: item)
        // The scramble's own order is never the answer (pinned above), so
        // filling the board in index order is a guaranteed miss.
        for index in units.indices {
            c.pickSpell(index)
        }

        let board = try #require(c.spellBoard)
        #expect(board.verdict == false)
        #expect(board.isLocked)
        #expect(board.slots.allSatisfy { $0.unit != nil })
        // 正解 renders from the board, spaces intact — not re-derived by the view.
        #expect(board.subject == TileBoard.spellSubject(for: item))
    }

    @Test
    func tilesMatchScoresTheSpelling() throws {
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        let ringo = queue[1]
        let units = TileBoard.units(for: ringo, attempt: 0)
        let board = TileBoard.of(ringo)

        // The pick order that spells the target: consume each ordered unit from
        // the scramble by first-available index (handles duplicate units).
        var pool = Array(units.enumerated())
        var correct: [Int] = []
        for unit in board.orderedUnits {
            let pos = try #require(pool.firstIndex { $0.element == unit })
            correct.append(pool[pos].offset)
            pool.remove(at: pos)
        }
        #expect(c.spellMatches(correct, for: ringo))
        // The scramble's own order is, by construction, never the answer.
        #expect(!c.spellMatches(Array(units.indices), for: ringo))
    }

    // MARK: - 挖空拼字 (the English board)

    @Test
    func anEnglishWordTakesTheGapBoardAndAKanaReadingTheTiles() throws {
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)

        self.walkToSpell(c, wordId: "w-apple")
        #expect(c.gapBoard != nil)
        #expect(c.spellBoard == nil)

        self.walkToSpell(c, wordId: "w-ringo")
        #expect(c.spellBoard != nil)
        #expect(c.gapBoard == nil)
    }

    @Test
    func aGapBoardShowsTheWordAroundItsHoles() throws {
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        self.walkToSpell(c, wordId: "w-apple")
        let board = try #require(c.gapBoard)

        #expect(board.term == "apple")
        #expect(board.segments.count == board.slots.count + 1)
        #expect(board.slots.allSatisfy { $0.filled == nil })
        #expect(board.verdict == nil)
        // The visible text plus the answers rebuilds the word — the view draws
        // exactly these pieces, so a mismatch here is a mis-spelled prompt.
        let rebuilt = zip(board.segments, board.slots.map(\.answer) + [""])
            .map { $0 + $1 }
            .joined()
        #expect(rebuilt == "apple")
        // The pool carries every answer plus distractors to choose against.
        #expect(board.slots.allSatisfy { slot in board.pool.contains { $0.unit == slot.answer } })
        #expect(board.pool.count > board.slots.count)
    }

    @Test
    func pickingAnOptionFillsTheGapAndDimsIt() throws {
        // "cutting board" carries two holes, so the board does not auto-check
        // on the first pick. A one-hole word cannot be tested here at all —
        // see the next test for why.
        let queue = try self.makeMultiWordQueue()
        let c = NewFlowCoordinator(queue: queue)
        self.walkToSpell(c, wordId: "w-board")
        let item = try #require(c.current).item
        let options = c.spellPool(for: item)
        let board = try #require(c.gapBoard)
        #expect(board.slots.count == 2)
        #expect(board.activeSlot == 0)

        c.pickSpell(0)
        let afterPick = try #require(c.gapBoard)
        #expect(afterPick.slots[0].filled == options[0])
        #expect(afterPick.pool[0].used)
        #expect(afterPick.slots[1].filled == nil)
        #expect(afterPick.activeSlot == 1)

        // An option already placed cannot be placed twice.
        c.pickSpell(0)
        let afterDoubleTap = try #require(c.gapBoard)
        #expect(afterDoubleTap.slots[1].filled == nil)

        c.unpickSpell(atSlot: 0)
        let afterUnpick = try #require(c.gapBoard)
        #expect(afterUnpick.slots[0].filled == nil)
        #expect(!afterUnpick.pool[0].used)
        #expect(afterUnpick.activeSlot == 0)
    }

    @Test
    func aSingleGapBoardCommitsOnTheFirstTap() throws {
        // With one hole the first tap is the answer, so the board locks and the
        // pick cannot be taken back — the same contract as 選字, where the first
        // pick ends the question either way.
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        self.walkToSpell(c, wordId: "w-apple")
        #expect(try #require(c.gapBoard).slots.count == 1)

        c.pickSpell(0)
        let board = try #require(c.gapBoard)
        #expect(board.isLocked)
        #expect(board.activeSlot == nil)
        c.unpickSpell(atSlot: 0)
        #expect(try #require(c.gapBoard).slots[0].filled != nil)
    }

    @Test
    func spellMatchesScoresAGapFillSlotBySlot() throws {
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        let apple = queue[0]
        let options = c.spellPool(for: apple)
        guard case let .gaps(plan) = try #require(SpellForm.of(apple)) else {
            Issue.record("apple should take the gap board")
            return
        }

        let correct = try plan.answers.map { answer in
            try #require(options.firstIndex(of: answer))
        }
        #expect(c.spellMatches(correct, for: apple))

        let wrong = try #require(options.indices.first { !plan.answers.contains(options[$0]) })
        #expect(!c.spellMatches([wrong], for: apple))
    }

    @Test
    func aWrongGapFreezesTheBoardAndMarksTheSlotThatMissed() throws {
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        self.walkToSpell(c, wordId: "w-apple")
        let item = try #require(c.current).item
        let options = c.spellPool(for: item)
        let answers = try #require(c.gapBoard).slots.map(\.answer)

        // Fill every slot with something that is not its answer.
        for slot in answers.indices {
            let wrong = try #require(options.indices.first {
                options[$0] != answers[slot] && !c.spellPicked.contains($0)
            })
            c.pickSpell(wrong)
        }

        let board = try #require(c.gapBoard)
        #expect(board.verdict == false)
        #expect(board.isLocked)
        #expect(board.slots.allSatisfy { !$0.isCorrect })
        // 正解 renders from the board, not re-derived by the view.
        #expect(board.term == "apple")
    }

    @Test
    func aRetryReshufflesTheOptionsButNeverMovesTheGaps() throws {
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        self.walkToSpell(c, wordId: "w-apple")
        let item = try #require(c.current).item
        let before = try #require(c.gapBoard)
        let firstPool = c.spellPool(for: item)

        // Miss it, then take the peek's advance — the retry path.
        let answers = before.slots.map(\.answer)
        for slot in answers.indices {
            let wrong = try #require(firstPool.indices.first {
                firstPool[$0] != answers[slot] && !c.spellPicked.contains($0)
            })
            c.pickSpell(wrong)
        }
        c.resolveSpell(correct: false)
        c.advanceFromPeek()
        self.walkToSpell(c, wordId: "w-apple")

        let after = try #require(c.gapBoard)
        // The chunk they missed is the one worth asking again, so the holes
        // stay put; only the order of the options changes.
        #expect(after.segments == before.segments)
        #expect(after.slots.map(\.answer) == answers)
        let secondPool = c.spellPool(for: item)
        #expect(Set(secondPool) == Set(firstPool))
        #expect(secondPool != firstPool)
        #expect(after.slots.allSatisfy { $0.filled == nil })
    }

    @Test
    func parkedCommitBumpsParkedCount() async throws {
        let queue = try Array(self.makeQueue().prefix(1))
        let writer = SpyAnswerWriter()
        writer.outcome = .parked
        let c = NewFlowCoordinator(queue: queue, writer: writer)
        // .good fast-paths past 選字 to tiles; clearing tiles commits the one
        // held-back write, which the writer reports as parked (offline).
        c.resolveRecognize(rating: .good)
        c.resolveSpell(correct: true)
        #expect(c.finished)
        await c.writes.drainPendingWrites(within: .seconds(2))
        #expect(writer.answers.count == 1)
        #expect(c.writes.parkedCount == 1)
    }

    /// The server attaches a streak milestone to whichever answer crosses the
    /// threshold — a 學新字 write can be that answer. The new-word flow used to
    /// match only `.parked` and throw the `.synced` body away, so those
    /// milestones were dropped and could never be recovered.
    @Test
    func learnedCommitKeepsTheMilestoneTheServerAttached() async throws {
        let queue = try Array(self.makeQueue().prefix(1))
        let writer = SpyAnswerWriter()
        writer.outcome = .synced(
            StudyAnswerResponse(
                ok: true,
                milestone: Milestone(streak: 30),
                mastery: MasteryDelta(before: 0, after: 12, delta: 12)
            )
        )
        let c = NewFlowCoordinator(queue: queue, writer: writer)
        c.resolveRecognize(rating: .good)
        c.resolveSpell(correct: true)
        await c.writes.drainPendingWrites(within: .seconds(2))

        #expect(c.writes.milestone?.streak == 30)
        #expect(c.writes.masteryByWord["w-apple"]?.after == 12)
        #expect(c.writes.parkedCount == 0)
    }
}

@MainActor
private final class NewFlowTestClock {
    var now = Date(timeIntervalSince1970: 1000)
}

/// Records the held-back recognize writes the coordinator commits, and returns
/// a configurable outcome. Set `outcome = .parked` to exercise the offline
/// path, or attach a milestone/mastery to assert the response is folded in.
@MainActor
private final class SpyAnswerWriter: DurableAnswerWriting {
    private(set) var answers: [StudyAnswerPayload] = []
    var outcome: StudyWriteOutcome = .synced(
        StudyAnswerResponse(ok: true, milestone: nil, mastery: nil)
    )

    func submitAnswer(_ payload: StudyAnswerPayload) async -> StudyWriteOutcome {
        self.answers.append(payload)
        return self.outcome
    }
}
