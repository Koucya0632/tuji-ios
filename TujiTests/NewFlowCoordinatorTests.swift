// Pins the synchronous parts of the interleaved new-word lesson: queue
// decoding (including the int-or-string card id the backend emits), the
// initial task interleave + the stage-ladder guard, the seeded spell/tile
// variants, and the mistake-downgraded SRS commit. The async lock/sleep
// choreography is exercised in the app, not here — tests walk the scheduler
// through the resolve* synchronous cores.

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

    /// Single multi-word EN item — too long for tiles, keeps the judge task.
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
    func spellStageKindFallsBackToJudgeForLongSubjects() throws {
        let queue = try self.makeQueue()
        // Short single tokens (apple / りんご / ねこ) get the tiles task.
        for item in queue {
            #expect(NewFlowCoordinator.spellStageKind(for: item) == .spellTiles)
        }
        // Multi-word subject keeps the judge task.
        let board = try self.makeMultiWordQueue()[0]
        #expect(NewFlowCoordinator.spellStageKind(for: board) == .spellJudge)
    }

    @Test
    func wrongIdentifyRequeuesAFewBackAndSpellWaitsForIt() throws {
        let queue = try Array(self.makeQueue().prefix(2))
        let c = NewFlowCoordinator(queue: queue)
        // n=2 schedule: r0 r1 i0 i1 s0 s1.
        c.resolveRecognize(rating: .good)
        c.resolveRecognize(rating: .good)
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
        c.resolveRecognize(rating: .good)
        // One cleared stage of 9 (3 items × 3 stages).
        #expect(abs(c.progress - 1.0 / 9.0) < 0.0001)
    }

    // MARK: - Seeded variants (no global alternation)

    @Test
    func spellShownIsDeterministicPerAttemptAndVaries() throws {
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        let apple = queue[0]
        // Deterministic: same (item, attempt) → same variant on re-render.
        #expect(c.spellShown(for: apple, attempt: 0) == c.spellShown(for: apple, attempt: 0))
        // Across attempts both the correct and a wrong variant must appear,
        // and a wrong variant never equals the subject.
        var sawCorrect = false
        var sawWrong = false
        for attempt in 0..<8 {
            let shown = c.spellShown(for: apple, attempt: attempt)
            if shown == "apple" {
                sawCorrect = true
            } else {
                sawWrong = true
                #expect(["appel", "aple"].contains(shown))
            }
        }
        #expect(sawCorrect && sawWrong)
        // Reading mode: variants are the subject or an on-device scramble of
        // the same kana — never empty, always the same letters.
        for attempt in 0..<8 {
            let shown = c.spellShown(for: queue[1], attempt: attempt)
            #expect(shown.map(String.init).sorted() == "りんご".map(String.init).sorted())
        }
    }

    @Test
    func tileLettersArePermutationNotAnswer() throws {
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        let apple = queue[0]
        let letters = c.tileLetters(for: apple, attempt: 0)
        // Deterministic across re-renders.
        #expect(letters == c.tileLetters(for: apple, attempt: 0))
        // A permutation of the subject's letters…
        #expect(letters.sorted() == "apple".map(String.init).sorted())
        // …that never spells the answer outright.
        #expect(letters.joined() != "apple")
        // Kana subjects tile the same way.
        let kana = c.tileLetters(for: queue[1], attempt: 0)
        #expect(kana.sorted() == "りんご".map(String.init).sorted())
        #expect(kana.joined() != "りんご")
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
        c.resolveRecognize(rating: .good)
        c.resolveIdentify(correct: true)
        c.resolveSpellJudge(judgedRight: true)
        #expect(c.finished)
        #expect(c.clearedWords == 1)
        await c.drainPendingWrites(within: .seconds(2))
        #expect(spy.answers.map(\.rating) == ["穩定"])
        #expect(spy.answers.first?.responseMs != nil)
    }

    @Test
    func oneMistakeDowngradesOneLevel() async throws {
        let queue = try Array(self.makeQueue().prefix(1))
        let spy = SpyStudyRepository()
        let c = NewFlowCoordinator(queue: queue, repository: spy)
        c.resolveRecognize(rating: .good)
        c.resolveIdentify(correct: false)
        c.advanceFromPeek()
        c.resolveIdentify(correct: true)
        c.resolveTiles(correct: true)
        #expect(c.finished)
        await c.drainPendingWrites(within: .seconds(2))
        #expect(spy.answers.map(\.rating) == ["困難"])
    }

    @Test
    func twoMistakesPostAgain() async throws {
        let queue = try Array(self.makeQueue().prefix(1))
        let spy = SpyStudyRepository()
        let c = NewFlowCoordinator(queue: queue, repository: spy)
        c.resolveRecognize(rating: .good)
        c.resolveIdentify(correct: false)
        c.advanceFromPeek()
        c.resolveIdentify(correct: true)
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
