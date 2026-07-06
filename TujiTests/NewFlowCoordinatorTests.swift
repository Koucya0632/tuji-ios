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
        return try JSONDecoder().decode([StudyQueueItem].self, from: Data(json.utf8))
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
        return try JSONDecoder().decode([StudyQueueItem].self, from: Data(json.utf8))
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
        return try JSONDecoder().decode([StudyQueueItem].self, from: Data(json.utf8))
    }

    @Test
    func decodesIntAndStringCardIds() throws {
        let queue = try self.makeQueue()
        #expect(queue.map(\.card.id) == ["101", "202", "303"])
        #expect(queue[0].spellingChoices == ["appel", "aple"])
    }

    @Test
    func spellSubjectPrefersReading() throws {
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        #expect(c.spellSubject(for: queue[0]) == "apple")
        #expect(c.spellSubject(for: queue[1]) == "りんご")
    }

    @Test
    func spellUsesReadingOnlyWhenDistinctFromTerm() throws {
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        #expect(!c.spellUsesReading(for: queue[0]))
        #expect(c.spellUsesReading(for: queue[1]))
        // reading == word → the kana IS the term; no separate reading mode.
        #expect(!c.spellUsesReading(for: queue[2]))
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
            ("w-apple", .spellTiles),
            ("w-neko", .identify),
            ("w-ringo", .spellTiles),
            ("w-neko", .spellTiles)
        ]
        #expect(c.tasks.map(\.item.word.id) == expected.map(\.0))
        #expect(c.tasks.map(\.kind) == expected.map(\.1))
    }

    @Test
    func tileBoardSplitsPerGraphemeForShortSubjects() throws {
        let queue = try self.makeQueue()
        let apple = NewFlowCoordinator.tileBoard(for: queue[0])
        #expect(apple.tokenUnits == [["a", "p", "p", "l", "e"]])
        #expect(apple.target == "apple")
        let ringo = NewFlowCoordinator.tileBoard(for: queue[1])
        #expect(ringo.tokenUnits == [["り", "ん", "ご"]])
    }

    @Test
    func tileBoardChunksLongSubjectsWithinTokens() throws {
        // 12 base units > the 10-tile cap → chunk length 2, re-grouped per
        // token (never across the space), space itself is not a tile.
        let board = try NewFlowCoordinator.tileBoard(for: self.makeMultiWordQueue()[0])
        #expect(board.tokenUnits == [["cu", "tt", "in", "g"], ["bo", "ar", "d"]])
        #expect(board.target == "cuttingboard")
        #expect(board.unitCount == 7)
    }

    @Test
    func tileBoardMergesSmallKanaIntoPrecedingUnit() throws {
        let queue = try self.makeKanaEdgeQueue()
        let kyou = NewFlowCoordinator.tileBoard(for: queue[0])
        #expect(kyou.tokenUnits == [["きょ", "う"]])
        let me = NewFlowCoordinator.tileBoard(for: queue[1])
        #expect(me.unitCount == 1)
    }

    @Test
    func singleUnitSubjectSkipsSpellStageAndStillCommits() async throws {
        let queue = try [self.makeKanaEdgeQueue()[1]]
        let spy = SpyStudyRepository()
        let c = NewFlowCoordinator(queue: queue, repository: spy)
        // A 1-tile board is a free answer, so め gets no spell task…
        #expect(c.tasks.map(\.kind) == [.recognize, .identify])
        c.resolveRecognize(rating: .hard)
        #expect(abs(c.progress - 0.5) < 0.0001)
        c.resolveIdentify(correct: true)
        // …and the word commits after 選字 clears.
        #expect(c.finished)
        #expect(c.clearedWords == 1)
        #expect(c.progress == 1.0)
        await c.drainPendingWrites(within: .seconds(2))
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
        #expect(c.tasks.map(\.id) == [
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
        let spy = SpyStudyRepository()
        let c = NewFlowCoordinator(queue: queue, repository: spy)
        // Schedule r0 r1 i0 i1 s0 s1 → 已認識 on w-apple drops i0.
        var lastProgress = c.progress
        func expectMonotone() {
            #expect(c.progress >= lastProgress)
            lastProgress = c.progress
        }
        c.resolveRecognize(rating: .good)
        #expect(!c.tasks.contains { $0.kind == .identify && $0.item.word.id == "w-apple" })
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
        #expect(c.current?.kind == .spellTiles)
        #expect(c.current?.item.word.id == "w-apple")
        c.resolveTiles(correct: true)
        expectMonotone()
        // Denominator shrank to 5 (6 scheduled − 1 skipped): 4 clears in.
        #expect(abs(c.progress - 4.0 / 5.0) < 0.0001)
        c.resolveTiles(correct: true)
        #expect(c.finished)
        #expect(c.clearedWords == 2)
        #expect(c.progress == 1.0)
        await c.drainPendingWrites(within: .seconds(2))
        #expect(spy.answers.map(\.rating) == ["穩定", "困難"])
    }

    @Test
    func fastPathWrongTilesRequeuesWithoutStalling() async throws {
        let queue = try Array(self.makeQueue().prefix(1))
        let spy = SpyStudyRepository()
        let c = NewFlowCoordinator(queue: queue, repository: spy)
        c.resolveRecognize(rating: .good)
        // Identify skipped → straight to production.
        #expect(c.current?.kind == .spellTiles)
        c.resolveTiles(correct: false)
        #expect(c.peek?.id == "w-apple")
        c.advanceFromPeek()
        // Requeued tiles must come back (not be deferred by normalizeHead).
        #expect(c.current?.kind == .spellTiles)
        c.resolveTiles(correct: true)
        #expect(c.finished)
        await c.drainPendingWrites(within: .seconds(2))
        // The tile miss corrects the overconfident self-rating: 穩定 → 困難.
        #expect(spy.answers.map(\.rating) == ["困難"])
    }

    @Test
    func singleUnitWordRatedGoodCommitsAfterRecognize() async throws {
        let queue = try [self.makeKanaEdgeQueue()[1]]
        let spy = SpyStudyRepository()
        let c = NewFlowCoordinator(queue: queue, repository: spy)
        // め has no spell stage; 已認識 also drops 選字 → one-task word.
        c.resolveRecognize(rating: .good)
        #expect(c.finished)
        #expect(c.clearedWords == 1)
        #expect(c.progress == 1.0)
        await c.drainPendingWrites(within: .seconds(2))
        #expect(spy.answers.map(\.rating) == ["穩定"])
    }

    // MARK: - Seeded tile scrambles

    @Test
    func tileUnitsArePermutationNotAnswer() throws {
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        let apple = queue[0]
        let units = c.tileUnits(for: apple, attempt: 0)
        // Deterministic across re-renders.
        #expect(units == c.tileUnits(for: apple, attempt: 0))
        // A permutation of the subject's letters…
        #expect(units.sorted() == "apple".map(String.init).sorted())
        // …that never spells the answer outright.
        #expect(units.joined() != "apple")
        // Kana subjects tile the same way.
        let kana = c.tileUnits(for: queue[1], attempt: 0)
        #expect(kana.sorted() == "りんご".map(String.init).sorted())
        #expect(kana.joined() != "りんご")
    }

    @Test
    func tileUnitsOfChunkedSubjectRebuildTheTarget() throws {
        let board = try self.makeMultiWordQueue()[0]
        let c = NewFlowCoordinator(queue: [board])
        let units = c.tileUnits(for: board, attempt: 0)
        let expected = NewFlowCoordinator.tileBoard(for: board)
        // The pool is the board's chunks reshuffled — same multiset, never in
        // solved order, and a later attempt reshuffles differently.
        #expect(units.sorted() == expected.orderedUnits.sorted())
        #expect(units.joined() != expected.target)
        #expect((1...4).contains { c.tileUnits(for: board, attempt: $0) != units })
    }

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
        let base = studyChoices(for: apple, pool: pool, variant: 0)
        #expect(base.contains("apple"))
        // Some later variant must present a different order — otherwise a
        // requeued question can be answered from remembered positions.
        let reshuffled = (1...4).map { studyChoices(for: apple, pool: pool, variant: $0) }
        #expect(reshuffled.contains { $0 != base })
    }

    // MARK: - SRS commit (mistake downgrade + latency)

    @Test
    func cleanRunPostsSelfRating() async throws {
        let queue = try self.makeMultiWordQueue()
        let spy = SpyStudyRepository()
        let c = NewFlowCoordinator(queue: queue, repository: spy)
        c.resolveRecognize(rating: .hard)
        c.resolveIdentify(correct: true)
        c.resolveTiles(correct: true)
        #expect(c.finished)
        #expect(c.clearedWords == 1)
        await c.drainPendingWrites(within: .seconds(2))
        #expect(spy.answers.map(\.rating) == ["困難"])
        #expect(spy.answers.first?.responseMs != nil)
    }

    @Test
    func oneMistakeDowngradesOneLevel() async throws {
        let queue = try Array(self.makeQueue().prefix(1))
        let spy = SpyStudyRepository()
        let c = NewFlowCoordinator(queue: queue, repository: spy)
        // .good fast-paths to tiles; the one tile miss drops 穩定 → 困難.
        c.resolveRecognize(rating: .good)
        c.resolveTiles(correct: false)
        c.advanceFromPeek()
        c.resolveTiles(correct: true)
        #expect(c.finished)
        await c.drainPendingWrites(within: .seconds(2))
        #expect(spy.answers.map(\.rating) == ["困難"])
    }

    @Test
    func identifyMistakeDowngradesOnFullLadder() async throws {
        let queue = try Array(self.makeQueue().prefix(1))
        let spy = SpyStudyRepository()
        let c = NewFlowCoordinator(queue: queue, repository: spy)
        c.resolveRecognize(rating: .hard)
        c.resolveIdentify(correct: false)
        c.advanceFromPeek()
        c.resolveIdentify(correct: true)
        c.resolveTiles(correct: true)
        #expect(c.finished)
        await c.drainPendingWrites(within: .seconds(2))
        #expect(spy.answers.map(\.rating) == ["重來"])
    }

    @Test
    func twoMistakesPostAgain() async throws {
        let queue = try Array(self.makeQueue().prefix(1))
        let spy = SpyStudyRepository()
        let c = NewFlowCoordinator(queue: queue, repository: spy)
        c.resolveRecognize(rating: .good)
        c.resolveTiles(correct: false)
        c.advanceFromPeek()
        c.resolveTiles(correct: false)
        c.advanceFromPeek()
        c.resolveTiles(correct: true)
        #expect(c.finished)
        await c.drainPendingWrites(within: .seconds(2))
        #expect(spy.answers.map(\.rating) == ["重來"])
    }

    @Test
    func downgradeMapping() {
        #expect(SRSRating.easy.downgraded == .good)
        #expect(SRSRating.good.downgraded == .hard)
        #expect(SRSRating.hard.downgraded == .again)
        #expect(SRSRating.again.downgraded == .again)
    }
}

/// Records /api/study/answer payloads; other repository calls are unused by
/// the coordinator.
@MainActor
private final class SpyStudyRepository: StudyRepository {
    private(set) var answers: [StudyAnswerPayload] = []

    struct NotImplemented: Error {}

    func loadQueue(mode _: StudyMode, limit _: Int, newCount _: Int, categories _: [String]) async throws
        -> StudyQueueResponse
    {
        throw NotImplemented()
    }

    func loadStats() async throws -> StudyStatsResponse {
        throw NotImplemented()
    }

    func submitAnswer(_ payload: StudyAnswerPayload) async throws -> StudyAnswerResponse {
        self.answers.append(payload)
        throw NotImplemented()
    }

    func submitAnswerBestEffort(_ payload: StudyAnswerPayload) async {
        self.answers.append(payload)
    }

    func submitReport(_: StudyReportPayload) async throws {
        throw NotImplemented()
    }
}
