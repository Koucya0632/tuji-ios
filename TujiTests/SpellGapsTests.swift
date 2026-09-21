// 挖空拼字 — the placement contract.
//
// These are the rules that were tuned against the real corpus (530 English
// headwords) before the feature was written, and the ones a change is most
// likely to break silently: a cut that starts at the first letter, two cuts
// with nothing left between them, or a family loose enough to ask
// `bana[n]a`. The board looks fine in all three cases; only the question is
// ruined.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct SpellGapsTests {
    /// A spread of shapes: short, long, multi-token, suffix-heavy, doubled
    /// consonants, and the ones that fall through to a bare vowel.
    private let corpus = [
        "apple", "preservative", "refrigerator", "umbrella", "coffee",
        "chocolate", "necessary", "air conditioner", "toothbrush", "dishwasher",
        "bag", "oven", "comfortable", "television", "restaurant",
        "cutting board", "banana", "bus", "washing machine", "bathtub"
    ]

    private func plan(_ term: String) throws -> SpellGaps {
        try #require(SpellGaps.of(term: term), "\(term) should carry a gap-fill")
    }

    // MARK: - Invariants

    @Test
    func theVisibleTextAndTheAnswersRebuildTheWord() throws {
        for term in self.corpus {
            let plan = try self.plan(term)
            #expect(plan.term == term)
            #expect(plan.segments.count == plan.gaps.count + 1)
            var rebuilt = ""
            for (index, segment) in plan.segments.enumerated() {
                rebuilt += segment
                if index < plan.gaps.count { rebuilt += plan.gaps[index].answer }
            }
            #expect(rebuilt == term, "\(term) does not rebuild from its own pieces")
        }
    }

    @Test
    func everyAnswerIsInThePoolAndThePoolRepeatsNothing() throws {
        for term in self.corpus {
            let plan = try self.plan(term)
            for answer in plan.answers {
                #expect(plan.options.contains(answer), "\(term): \(answer) missing from the pool")
            }
            #expect(Set(plan.options).count == plan.options.count, "\(term): duplicate option")
            // Two holes wanting the same chunk would print the option twice and
            // read as a mistake in the pool.
            #expect(Set(plan.answers).count == plan.answers.count, "\(term): duplicate answer")
        }
    }

    @Test
    func aGapNeverEatsTheOpeningTheWholeWordOrASpace() throws {
        for term in self.corpus {
            let plan = try self.plan(term)
            let letters = term.count(where: { !$0.isWhitespace })
            let chars = Array(term)
            for gap in plan.gaps {
                // `contains(where:)` is rethrows, and #expect cannot decompose
                // it — the error lands in a generated macro file with no line
                // of ours in it. Compute first, assert on the Bool.
                let spansASpace = chars[gap.range].contains { $0.isWhitespace }
                #expect(gap.range.lowerBound > 0, "\(term): a gap starts at the first letter")
                #expect(gap.range.count < letters, "\(term): the gap is the whole word")
                #expect(!spansASpace, "\(term): a gap spans a space")
            }
            let blanked = plan.gaps.reduce(0) { $0 + $1.range.count }
            #expect(Double(blanked) <= Double(letters) * 0.55, "\(term): too much of the word is gone")
        }
    }

    @Test
    func gapsNeverTouch() throws {
        for term in self.corpus {
            let plan = try self.plan(term)
            for (left, right) in zip(plan.gaps, plan.gaps.dropFirst()) {
                // Adjacent holes render as one wide hole, so at least one
                // visible letter has to survive between them.
                #expect(
                    right.range.lowerBound > left.range.upperBound,
                    "\(term): two gaps run together"
                )
            }
            #expect(plan.segments.dropFirst().dropLast().allSatisfy { !$0.isEmpty })
        }
    }

    // MARK: - How many holes

    @Test
    func theWordLengthSetsTheTargetAndAShortageLowersIt() throws {
        // ≤5 letters → 1, 6–9 → 2, ≥10 → 3.
        let counts = try ["bag", "apple", "comfortable", "refrigerator", "umbrella"]
            .map { try self.plan($0).gaps.count }
        // umbrella is 8 letters, so it asks for 2 — but only one place in it is
        // worth cutting, and a shortage lowers the count rather than inventing
        // a bad hole.
        #expect(counts == [1, 1, 2, 3, 1])
    }

    @Test
    func atMostOneHoleIsABareVowel() throws {
        for term in self.corpus {
            let plan = try self.plan(term)
            let singles = plan.gaps.filter { $0.answer.count == 1 }
            #expect(singles.count <= 1, "\(term): more than one bare-vowel hole")
        }
    }

    // MARK: - Which chunk, and what it is asked against

    @Test
    func aConfusableChunkIsPreferredAndBringsItsOwnFamily() throws {
        // The r-controlled vowels are the classic English spelling error and
        // the shape the whole feature was built around.
        let preservative = try self.plan("preservative")
        #expect(preservative.answers.contains("er"))
        // Three holes share one capped pool, so each family contributes a
        // look-alike rather than all of its members.
        let rControlled = ["ar", "or", "ur", "ir"].filter { preservative.options.contains($0) }
        #expect(!rControlled.isEmpty)

        // A word with a single hole does get the whole family to choose from —
        // that is the five-option board the design started from.
        let apple = try self.plan("apple")
        #expect(apple.answers == ["le"])
        #expect(["el", "al", "il"].allSatisfy { apple.options.contains($0) })

        // A doubled consonant is cut as the pair, never as one letter — a bare
        // `bana[n]a` asking n/nn is the question this rule exists to prevent.
        let umbrella = try self.plan("umbrella")
        #expect(umbrella.answers == ["el"])

        // Suffix families are worth cutting even at the very end of the word.
        let television = try self.plan("television")
        let comfortable = try self.plan("comfortable")
        #expect(television.answers.contains("sion"))
        #expect(comfortable.answers.contains("able"))
    }

    @Test
    func aWordWithNoConfusableChunkStillGetsAVowel() throws {
        let bag = try self.plan("bag")
        #expect(bag.answers == ["a"])
        // beg / big / bog / bug are all real words, so these are honest
        // distractors rather than filler.
        #expect(bag.options.sorted() == ["a", "e", "i", "o", "u"])
    }

    @Test
    func theOptionCountFollowsTheHoleCount() throws {
        // answers + 4 distractors, capped at 8.
        for term in self.corpus {
            let plan = try self.plan(term)
            #expect(plan.options.count == min(plan.gaps.count + 4, 8), "\(term)")
        }
    }

    // MARK: - What cannot be asked this way

    @Test
    func acronymsAndVowellessWordsFallThrough() {
        // Nothing in these can be cut without the prompt becoming a riddle;
        // SpellForm sends them to the tile board instead.
        for term in ["MRT", "MSG", "TV", "thyme", "ox"] {
            #expect(SpellGaps.of(term: term) == nil, "\(term) should not get a gap-fill")
        }
    }

    // MARK: - Stability across renders and retries

    @Test
    func placementIsPureAndRepeatable() {
        for term in self.corpus {
            #expect(SpellGaps.of(term: term) == SpellGaps.of(term: term), "\(term)")
        }
    }

    @Test
    func aRetryReshufflesThePoolAndLeavesTheHolesWhereTheyWere() throws {
        let item = try self.item(word: "preservative")
        let first = SpellGaps.options(for: item, attempt: 0)
        let second = SpellGaps.options(for: item, attempt: 1)

        #expect(!first.isEmpty)
        #expect(Set(first) == Set(second))
        #expect(first != second)
        // Same order for the same attempt, so a SwiftUI re-render doesn't
        // reshuffle the pool under the user's finger.
        #expect(SpellGaps.options(for: item, attempt: 0) == first)
    }

    // MARK: - Which board a word takes

    @Test
    func englishTakesTheGapsAndAKanaReadingTakesTheTiles() throws {
        guard case .gaps = try #require(SpellForm.of(self.item(word: "preservative"))) else {
            Issue.record("an English word should take the gap board")
            return
        }
        // 林檎 is quizzed on its kana reading — no orthographic confusables to
        // cut, so it keeps the whole-string tile board.
        guard case .tiles = try #require(SpellForm.of(self.item(word: "林檎", reading: "りんご"))) else {
            Issue.record("a kana reading should take the tile board")
            return
        }
        // バスマット is a `.term` too, but it is not Latin script.
        guard case .tiles = try #require(SpellForm.of(self.item(word: "ねこ", reading: "ねこ"))) else {
            Issue.record("a kana term should take the tile board")
            return
        }
        // One unit left to arrange is no question at all — the ladder has
        // always skipped these, and the gate reads the same predicate.
        let single = try self.item(word: "め", reading: "め")
        #expect(SpellForm.of(single) == nil)
    }

    // MARK: - Fixtures

    private func item(word: String, reading: String? = nil) throws -> StudyQueueItem {
        let readingJSON = reading.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
          "card": { "id": "c-\(word)", "cardType": "flashcard", "deckKey": "core" },
          "word": {
            "id": "w-\(word)", "word": "\(word)", "chinese": "測試", "imageUrl": "",
            "pronunciation": "", "reading": \(readingJSON), "category": "test"
          },
          "choices": null, "spellingChoices": null, "mastery": null
        }
        """
        return try JSONDecoder.tuji.decode(StudyQueueItem.self, from: Data(json.utf8))
    }
}
