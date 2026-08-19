// Pins the four unfairness rules the MCQ option set is built on.
//
// The module's header named all four; none of them was pinned. They lived in
// file-private functions with no test file at all, reachable only through a
// seeded shuffle whose output you would have to assert *by absence* — "this
// label did not appear", which passes just as well when the shuffle simply put
// something else in the slot. `DistractorFairness` is a returned value now, so
// each rule is one assertion.

import Foundation
import Testing
@testable import Tuji

struct DistractorPoolTests {
    private func word(_ term: String, _ gloss: String) -> CardWord {
        CardWord(
            id: term,
            word: term,
            chinese: gloss,
            imageUrl: "",
            category: "kitchen",
            pronunciation: "",
            targetLanguage: .en
        )
    }

    private var dictionary: [CardWord] {
        [
            self.word("pan", "平底鍋"),
            self.word("frying pan", "平底鍋"),
            self.word("pot", "鍋子 / 湯鍋"),
            self.word("knife", "刀"),
            self.word("kitchen knife", "菜刀"),
            self.word("時計", "時鐘"),
            self.word("腕時計", "手錶"),
            self.word("banana", "香蕉")
        ]
    }

    private func pool(answer: String, gloss: String) -> DistractorPool {
        DistractorPool(answer: answer, gloss: gloss, pool: self.dictionary)
    }

    @Test
    func aPlainUnrelatedWordIsFair() {
        #expect(self.pool(answer: "pan", gloss: "平底鍋").fairness(of: "banana") == .fair)
    }

    @Test
    func theAnswerItselfIsNeverADistractor() {
        let pool = self.pool(answer: "pan", gloss: "平底鍋")
        #expect(pool.fairness(of: "pan") == .sameTerm)
        // Case is not a difference a learner can act on.
        #expect(pool.fairness(of: "Pan") == .sameTerm)
    }

    /// knife / kitchen knife: a learner who knows 刀 can defend either.
    @Test
    func oneTermsTokensContainingTheOthersIsUnfair() {
        #expect(
            self.pool(answer: "knife", gloss: "刀").fairness(of: "kitchen knife") == .tokenSubset
        )
        // …and in the other direction.
        #expect(
            self.pool(answer: "kitchen knife", gloss: "菜刀").fairness(of: "knife") == .tokenSubset
        )
    }

    /// CJK has no whitespace to tokenise on, so substring stands in for it.
    @Test
    func aCJKTermContainingTheOtherIsUnfair() {
        #expect(self.pool(answer: "時計", gloss: "時鐘").fairness(of: "腕時計") == .cjkSubstring)
        #expect(self.pool(answer: "腕時計", gloss: "手錶").fairness(of: "時計") == .cjkSubstring)
    }

    /// The rule this module was built for: the dictionary translates both
    /// identically, so the question has two right answers on screen.
    @Test
    func sharingAChineseGlossIsUnfair() {
        // "frying pan" also trips the token rule, so assert the gloss rule with
        // a pair that shares only the gloss.
        let pool = DistractorPool(
            answer: "wok",
            gloss: "平底鍋",
            pool: self.dictionary + [self.word("wok", "平底鍋")]
        )
        #expect(pool.fairness(of: "pan") == .sharedGloss)
    }

    /// Glosses are packed as "鍋子 / 湯鍋" — sharing *any* one of them is enough.
    @Test
    func aSharedGlossInsideAPackedListStillCounts() {
        let pool = DistractorPool(
            answer: "saucepan",
            gloss: "湯鍋、深鍋",
            pool: self.dictionary + [self.word("saucepan", "湯鍋、深鍋")]
        )
        #expect(pool.fairness(of: "pot") == .sharedGloss)
    }

    @Test
    func anAnswerWithNoGlossFallsBackToTheOtherRulesOnly() {
        let pool = DistractorPool(answer: "pan", gloss: "", pool: self.dictionary)
        #expect(pool.fairness(of: "frying pan") == .tokenSubset)
        #expect(pool.fairness(of: "banana") == .fair)
    }

    // MARK: - The assembled set

    private func item(_ term: String, gloss: String, choices: [String]?) throws -> StudyQueueItem {
        let choicesJSON = choices.map { "[\($0.map { "\"\($0)\"" }.joined(separator: ","))]" } ?? "null"
        let json = """
        {
          "card": { "id": "c-\(term)", "cardType": "flashcard", "deckKey": "core" },
          "word": {
            "id": "w-\(term)", "word": "\(term)", "chinese": "\(gloss)", "imageUrl": "",
            "pronunciation": "", "reading": null, "targetLanguage": "en", "category": "kitchen"
          },
          "choices": \(choicesJSON), "spellingChoices": null, "mastery": 0
        }
        """
        return try JSONDecoder.tuji.decode(StudyQueueItem.self, from: Data(json.utf8))
    }

    @Test
    func theUnfairServerDistractorIsScrubbedAndTheSetToppedUp() throws {
        // The server draw is category-scoped, so it can offer the answer's own
        // near-synonym. That is the case this whole module exists for.
        let item = try self.item("pan", gloss: "平底鍋", choices: ["frying pan", "pot", "knife"])
        let choices = studyChoices(for: item, pool: self.dictionary, session: .en)

        #expect(choices.contains("pan"))
        #expect(!choices.contains("frying pan"))
        #expect(choices.count == 4)
        #expect(Set(choices).count == 4)
    }

    @Test
    func theOrderIsStableForTheSameVariantAndMovesWithIt() throws {
        let item = try self.item("pan", gloss: "平底鍋", choices: ["pot", "knife", "banana"])
        let first = studyChoices(for: item, pool: self.dictionary, session: .en, variant: 0)

        #expect(first == studyChoices(for: item, pool: self.dictionary, session: .en, variant: 0))
        #expect(first != studyChoices(for: item, pool: self.dictionary, session: .en, variant: 1))
    }

    @Test
    func aCustomCardWithNoServerChoicesIsBuiltEntirelyFromThePool() throws {
        let item = try self.item("pan", gloss: "平底鍋", choices: nil)
        let choices = studyChoices(for: item, pool: self.dictionary, session: .en)

        #expect(choices.contains("pan"))
        #expect(!choices.contains("frying pan"))
        #expect(choices.count == 4)
    }
}
