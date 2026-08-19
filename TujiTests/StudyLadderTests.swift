// Pins the 學新字 interleave scheduler through its own interface.
//
// These assertions used to be reachable only by constructing a whole
// NewFlowCoordinator and calling `resolveRecognize` / `resolveIdentify` /
// `resolveTiles` — three internal methods that exist for the tests and that the
// app never calls. The queue algebra is a value type now, so a test states a
// queue and reads an answer.

import Foundation
import Testing
@testable import Tuji

struct StudyLadderTests {
    /// `apple` and `林檎` both spell to multi-unit boards (3 stages each);
    /// `ねこ` reads as its own term over two kana, so it does too. A
    /// single-character word is added where a 1-unit board is needed.
    private func makeQueue(_ json: String) throws -> [StudyQueueItem] {
        try JSONDecoder.tuji.decode([StudyQueueItem].self, from: Data(json.utf8))
    }

    private func word(id: String, word: String, reading: String? = nil) -> String {
        let readingField = reading.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "card": { "id": "\(id)-card", "cardType": "flashcard", "deckKey": "core" },
          "word": {
            "id": "\(id)", "word": "\(word)", "chinese": "x", "imageUrl": "",
            "pronunciation": "", "reading": \(readingField),
            "targetLanguage": "en", "category": "core"
          },
          "choices": null, "spellingChoices": null, "mastery": 0
        }
        """
    }

    private func standardQueue() throws -> [StudyQueueItem] {
        try self.makeQueue("[\(self.word(id: "w1", word: "apple")),\(self.word(id: "w2", word: "pear"))]")
    }

    @Test
    func initialScheduleInterleavesWordsAndKeepsEachLadderOrdered() throws {
        let ladder = try StudyLadder(queue: self.standardQueue())
        let ids = ladder.tasks.map { "\($0.item.word.id).\($0.kind.rawValue)" }

        // Every word's own stages stay in order…
        for wordId in ["w1", "w2"] {
            let kinds = ladder.tasks.filter { $0.item.word.id == wordId }.map(\.kind)
            #expect(kinds == [.recognize, .identify, .spellTiles])
        }
        // …and the two words interleave rather than blocking.
        #expect(ids.first == "w1.recognize")
        #expect(ids.contains("w2.recognize"))
        #expect(ladder.totalStages == 6)
        #expect(!ladder.finished)
    }

    @Test
    func aSingleUnitSubjectCarriesNoSpellStage() throws {
        // One grapheme ⇒ a 1-tile board ⇒ a free answer, so the stage is never
        // scheduled and the progress denominator shrinks with it.
        let queue = try makeQueue("[\(self.word(id: "w1", word: "a"))]")
        let ladder = StudyLadder(queue: queue)

        #expect(ladder.tasks.map(\.kind) == [.recognize, .identify])
        #expect(ladder.totalStages == 2)
        #expect(!ladder.hasSpellStage(queue[0]))
    }

    @Test
    func completingEveryStageOfAWordReportsItOnce() throws {
        var ladder = try StudyLadder(queue: self.standardQueue())
        var cleared: [String] = []

        while !ladder.finished {
            if ladder.current?.kind == .identify {
                try ladder.markIdentifyCleared(#require(ladder.current?.item.word.id))
            }
            if let done = ladder.completeCurrent() {
                cleared.append(done.word.id)
            }
        }

        #expect(cleared.sorted() == ["w1", "w2"])
        #expect(ladder.clearedWords == 2)
        #expect(ladder.progress == 1)
    }

    @Test
    func completingANonFinalStageReportsNothing() throws {
        var ladder = try StudyLadder(queue: self.standardQueue())
        #expect(ladder.completeCurrent() == nil)
        #expect(ladder.clearedWords == 0)
        #expect(ladder.stageClears == 1)
    }

    @Test
    func requeuePutsTheHeadBackAFewPositionsLater() throws {
        var ladder = try StudyLadder(queue: self.standardQueue())
        let head = try #require(ladder.current)
        let count = ladder.tasks.count

        ladder.requeueCurrent()

        #expect(ladder.tasks.count == count)
        #expect(ladder.current?.id != head.id)
        #expect(ladder.tasks.firstIndex { $0.id == head.id } == StudyLadder.requeueGap)
        // A retry must not inflate the denominator or the numerator.
        #expect(ladder.stageClears == 0)
        #expect(ladder.totalStages == count)
    }

    /// The load-bearing one: a requeued 選字 can land *behind* its word's
    /// pre-scheduled 拼字, and spelling a word you just failed to recognise
    /// breaks the ladder.
    @Test
    func aSpellTaskNeverSurfacesBeforeItsWordClearedIdentify() throws {
        var ladder = try StudyLadder(queue: self.standardQueue())

        // Walk the whole session answering every 選字 wrong the first time.
        var wrongOnce: Set<String> = []
        var guard_ = 0
        while !ladder.finished, guard_ < 200 {
            guard_ += 1
            let task = try #require(ladder.current)
            let wordId = task.item.word.id
            switch task.kind {
            case .recognize:
                ladder.completeCurrent()
            case .identify:
                if wrongOnce.contains(wordId) {
                    ladder.markIdentifyCleared(wordId)
                    ladder.completeCurrent()
                } else {
                    wrongOnce.insert(wordId)
                    ladder.requeueCurrent()
                }
            case .spellTiles:
                // This is the assertion: reaching a 拼字 head at all means the
                // word had already cleared 選字.
                #expect(ladder.identifyCleared.contains(wordId))
                ladder.completeCurrent()
            }
        }
        #expect(ladder.finished)
    }

    @Test
    func theFastPathDropsIdentifyAndShrinksTheDenominator() throws {
        let queue = try standardQueue()
        var ladder = StudyLadder(queue: queue)
        let before = ladder.totalStages

        ladder.skipIdentify(for: queue[0])

        #expect(ladder.totalStages == before - 1)
        #expect(ladder.identifyCleared.contains("w1"))
        #expect(ladder.skippedIdentify.contains("w1"))
        #expect(!ladder.tasks.contains { $0.item.word.id == "w1" && $0.kind == .identify })
        // Marking it cleared is what lets the word's 拼字 ever reach the head.
        #expect(ladder.tasks.contains { $0.item.word.id == "w1" && $0.kind == .spellTiles })
    }

    @Test
    func skippingIdentifyForAWordWithNoPendingIdentifyChangesNothing() throws {
        let queue = try standardQueue()
        var ladder = StudyLadder(queue: queue)
        ladder.skipIdentify(for: queue[0])
        let after = ladder

        ladder.skipIdentify(for: queue[0])

        #expect(ladder == after)
    }

    @Test
    func anEmptyQueueIsImmediatelyFinishedAndScoresZero() {
        var ladder = StudyLadder(queue: [])
        #expect(ladder.finished)
        #expect(ladder.progress == 0)
        #expect(ladder.completeCurrent() == nil)
    }
}
