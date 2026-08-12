// Pins the tile board: what the 拼字 stage asks for (拼字題目), how the board
// splits into units, and the seeded scramble. These used to live in
// NewFlowCoordinatorTests because the functions hung off the coordinator as a
// `nonisolated static` extension — they belong to TileBoard, and so do they.

import Foundation
import Testing
@testable import Tuji

struct TileBoardTests {
    /// An EN word, a JA word whose 振假名 differs from the term, and a kana-only
    /// JA word whose reading *is* the term.
    private func makeQueue() throws -> [StudyQueueItem] {
        let json = """
        [
          {
            "card": { "id": 101, "cardType": "flashcard", "deckKey": "core" },
            "word": {
              "id": "w-apple", "word": "apple", "chinese": "\u{860B}\u{679C}", "imageUrl": "",
              "pronunciation": "", "reading": null, "targetLanguage": "en", "category": "food"
            },
            "choices": null, "spellingChoices": null, "mastery": null
          },
          {
            "card": { "id": "202", "cardType": "flashcard", "deckKey": "core" },
            "word": {
              "id": "w-ringo", "word": "\u{6797}\u{6A8E}", "chinese": "x", "imageUrl": "",
              "pronunciation": "", "reading": "\u{308A}\u{3093}\u{3054}", "targetLanguage": "ja", "category": "food"
            },
            "choices": null, "spellingChoices": null, "mastery": null
          },
          {
            "card": { "id": 303, "cardType": "flashcard", "deckKey": "core" },
            "word": {
              "id": "w-neko", "word": "\u{306D}\u{3053}", "chinese": "x", "imageUrl": "",
              "pronunciation": "", "reading": "\u{306D}\u{3053}", "targetLanguage": "ja", "category": "animal"
            },
            "choices": null, "spellingChoices": null, "mastery": null
          }
        ]
        """
        return try JSONDecoder().decode([StudyQueueItem].self, from: Data(json.utf8))
    }

    /// 12 letters across two tokens — over the 10-tile cap, so it chunks.
    private func makeMultiWordQueue() throws -> [StudyQueueItem] {
        let json = """
        [
          {
            "card": { "id": 404, "cardType": "flashcard", "deckKey": "core" },
            "word": {
              "id": "w-board", "word": "cutting board", "chinese": "x", "imageUrl": "",
              "pronunciation": "", "reading": null, "targetLanguage": "en", "category": "kitchen"
            },
            "choices": null, "spellingChoices": null, "mastery": null
          }
        ]
        """
        return try JSONDecoder().decode([StudyQueueItem].self, from: Data(json.utf8))
    }

    /// A yo\u{304A}n reading whose small kana must merge into the preceding unit,
    /// and a single-kana reading whose 1-tile board would be a free answer.
    private func makeKanaEdgeQueue() throws -> [StudyQueueItem] {
        let json = """
        [
          {
            "card": { "id": 505, "cardType": "flashcard", "deckKey": "core" },
            "word": {
              "id": "w-kyou", "word": "\u{4ECA}\u{65E5}", "chinese": "x", "imageUrl": "",
              "pronunciation": "", "reading": "\u{304D}\u{3087}\u{3046}", "targetLanguage": "ja", "category": "time"
            },
            "choices": null, "spellingChoices": null, "mastery": null
          },
          {
            "card": { "id": 606, "cardType": "flashcard", "deckKey": "core" },
            "word": {
              "id": "w-me", "word": "\u{76EE}", "chinese": "x", "imageUrl": "",
              "pronunciation": "", "reading": "\u{3081}", "targetLanguage": "ja", "category": "body"
            },
            "choices": null, "spellingChoices": null, "mastery": null
          }
        ]
        """
        return try JSONDecoder().decode([StudyQueueItem].self, from: Data(json.utf8))
    }

    @Test
    func spellSubjectPrefersReading() throws {
        let queue = try self.makeQueue()
        #expect(TileBoard.spellSubject(for: queue[0]) == .term("apple"))
        #expect(TileBoard.spellSubject(for: queue[1]) == .reading("りんご"))
    }

    @Test
    func aKanaOnlyWordIsQuizzedAsATermNotAReading() throws {
        let queue = try self.makeQueue()
        // queue[2] (ねこ) is Japanese and its 振假名 is itself, so there is no
        // separate reading to quiz — the stage asks for the 詞形. This is the
        // case where 拼字題目 and the word's *language* give different answers,
        // which is why they are different questions.
        #expect(TileBoard.spellSubject(for: queue[2]).isReading == false)
        #expect(TileBoard.spellSubject(for: queue[0]).isReading == false)
        #expect(TileBoard.spellSubject(for: queue[1]).isReading == true)
    }

    @Test
    func everySubjectCarriesTheStringBeingAssembled() throws {
        let queue = try self.makeQueue()
        #expect(TileBoard.spellSubject(for: queue[0]).text == "apple")
        #expect(TileBoard.spellSubject(for: queue[1]).text == "りんご")
    }

    @Test
    func tileBoardSplitsPerGraphemeForShortSubjects() throws {
        let queue = try self.makeQueue()
        let apple = TileBoard.of(queue[0])
        #expect(apple.tokenUnits == [["a", "p", "p", "l", "e"]])
        #expect(apple.target == "apple")
        let ringo = TileBoard.of(queue[1])
        #expect(ringo.tokenUnits == [["り", "ん", "ご"]])
    }

    @Test
    func tileBoardChunksLongSubjectsWithinTokens() throws {
        // 12 base units > the 10-tile cap → chunk length 2, re-grouped per
        // token (never across the space), space itself is not a tile.
        let board = try TileBoard.of(self.makeMultiWordQueue()[0])
        #expect(board.tokenUnits == [["cu", "tt", "in", "g"], ["bo", "ar", "d"]])
        #expect(board.target == "cuttingboard")
        #expect(board.unitCount == 7)
    }

    @Test
    func tileBoardMergesSmallKanaIntoPrecedingUnit() throws {
        let queue = try self.makeKanaEdgeQueue()
        let kyou = TileBoard.of(queue[0])
        #expect(kyou.tokenUnits == [["きょ", "う"]])
        let me = TileBoard.of(queue[1])
        #expect(me.unitCount == 1)
    }

    @Test
    func tileUnitsArePermutationNotAnswer() throws {
        let queue = try self.makeQueue()
        let apple = queue[0]
        let units = TileBoard.units(for: apple, attempt: 0)
        // Deterministic across re-renders.
        #expect(units == TileBoard.units(for: apple, attempt: 0))
        // A permutation of the subject's letters…
        #expect(units.sorted() == "apple".map(String.init).sorted())
        // …that never spells the answer outright.
        #expect(units.joined() != "apple")
        // Kana subjects tile the same way.
        let kana = TileBoard.units(for: queue[1], attempt: 0)
        #expect(kana.sorted() == "りんご".map(String.init).sorted())
        #expect(kana.joined() != "りんご")
    }

    @Test
    func tileUnitsOfChunkedSubjectRebuildTheTarget() throws {
        let board = try self.makeMultiWordQueue()[0]
        let c = NewFlowCoordinator(queue: [board])
        let units = TileBoard.units(for: board, attempt: 0)
        let expected = TileBoard.of(board)
        // The pool is the board's chunks reshuffled — same multiset, never in
        // solved order, and a later attempt reshuffles differently.
        #expect(units.sorted() == expected.orderedUnits.sorted())
        #expect(units.joined() != expected.target)
        #expect((1...4).contains { TileBoard.units(for: board, attempt: $0) != units })
    }
}
