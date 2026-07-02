// Pins the synchronous parts of the 3-step new-word lesson state machine:
// queue decoding (including the int-or-string card id the backend emits),
// the spell-step subject/parity rules, and the wrong-answer requeue moves.
// The async lock/sleep choreography is exercised in the app, not here.

import Foundation
import Testing
@testable import Tuji

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

    @Test
    func spellShownAlternatesByAttemptParity() throws {
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        // Even attempt: the correct subject is shown.
        #expect(c.spellShown(for: queue[0]) == "apple")
        #expect(c.spellShownIsCorrect)
        // Odd attempt: a wrong variant — the first non-correct spellingChoice.
        c.spellAdvance()
        #expect(c.spellShown(for: queue[0]) == "appel")
        // Reading mode has no term-based choices; the wrong variant is
        // scrambled on-device but must never equal the subject.
        #expect(c.spellShown(for: queue[1]) != "りんご")
    }

    @Test
    func identifyAdvanceRequeuesMissedWordToTail() throws {
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        c.identifyAdvance()
        #expect(c.idQueue.map(\.word.id) == ["w-ringo", "w-neko", "w-apple"])
        #expect(c.idPicked == nil)
        #expect(!c.idLocked)
    }

    @Test
    func spellAdvanceRequeuesAndBumpsParity() throws {
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        c.spellAdvance()
        #expect(c.spQueue.map(\.word.id) == ["w-ringo", "w-neko", "w-apple"])
        #expect(c.spAttempt == 1)
        #expect(c.spJudge == nil)
        #expect(!c.spLocked)
    }

    @Test
    func progressWalksRecognizeStep() async throws {
        let queue = try self.makeQueue()
        let c = NewFlowCoordinator(queue: queue)
        #expect(c.progress == 0)
        // One recognize answer = 1 of 9 total steps (3 items × 3 parts).
        await c.recognizeAnswer(rating: .good)
        #expect(c.recIdx == 1)
        #expect(abs(c.progress - 1.0 / 9.0) < 0.0001)
    }
}
