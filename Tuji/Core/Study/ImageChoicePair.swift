// The two pictures 聽句 offers, and the four reasons a picture may not stand
// beside the answer.
//
// `DistractorPool` answers the same question for *labels* and this leans on it
// for two of the four rules, because "pan" and "frying pan" are no fairer as
// two photographs of a pan than as two words. The other two rules only exist
// once the options are pictures:
//
//   • **Not a word the sentence also names.** The example sentences deliberately
//     mention two catalogue nouns — "The air conditioner is in the bedroom." —
//     and 46% of the English set (47% of the Japanese) does. Draw the other one
//     and *both* pictures are correct: the user hears the sentence perfectly,
//     picks a thing that is in it, and the SRS records a failure. The server
//     knows which words a sentence names because it resolved them itself, so
//     the queue carries `mentionedWordIds` and this excludes them.
//   • **Same `WordImageKind`.** The dictionary's own artwork is a cut-out on
//     white; a captured or saved word is a photograph of a room. One of each
//     and the odd one out is visible without listening to anything. It also
//     keeps 自製圖鑑 out of the draw for free.
//
// And one rule about where the pool comes from rather than what is in it: never
// draw from the cards still queued this session. That word is going to be asked
// about later, and showing its picture now is a free look.

import Foundation

/// One of the two pictures. Carries the id so the coordinator can compare a
/// pick against the answer without comparing labels — two catalogue words can
/// share a label, they cannot share an id.
struct ImageChoiceOption: Hashable, Identifiable {
    let id: String
    let word: String
    let imageUrl: String
    let imageKind: WordImageKind

    var imageURL: URL? {
        URL(string: self.imageUrl)
    }
}

enum ImageChoicePair {
    /// The answer and one fair distractor, in a stable random order, or nil
    /// when the pool cannot produce a distractor.
    ///
    /// Nil is a real answer and not an error: the caller falls back to 選字,
    /// which is the same fallback every other ineligible card takes. A brand
    /// new account whose catalogue has not loaded, or a language with a thin
    /// pool, lands here.
    ///
    /// The order is seeded from the item id (and `variant`, which the
    /// coordinator bumps per presentation) rather than shuffled freshly, for
    /// the reason `studyChoices` spells out: `body` is re-evaluated on every
    /// redraw, so an unseeded shuffle makes the options jump under the user's
    /// thumb. `variant` is what makes a re-test re-draw instead of letting
    /// "the answer was on the left" stand in for the word.
    static func options(
        for item: StudyQueueItem,
        pool: [CardWord],
        session: TargetLanguage,
        mentionedWordIds: Set<String>,
        queuedWordIds: Set<String>,
        variant: Int = 0
    )
        -> [ImageChoiceOption]?
    {
        let answer = ImageChoiceOption(
            id: item.word.id,
            word: item.word.word,
            imageUrl: item.word.imageUrl,
            imageKind: item.word.imageKind
        )
        guard !answer.imageUrl.isEmpty else { return nil }

        var rng = SeededRNG(
            seed: studyStableHash("listen:" + item.id) &+ UInt64(variant) &* 0x9E3779B97F4A7C15
        )
        let fairness = DistractorPool(answer: answer.word, gloss: item.word.chinese, pool: pool)
        let language = item.word.language(in: session)

        /// Spelled out rather than one boolean chain: as a single `&&` run in a
        /// closure this is a type-check the compiler warns it cannot finish in
        /// reasonable time.
        func admits(_ candidate: CardWord) -> Bool {
            guard candidate.id != answer.id else { return false }
            guard !candidate.imageUrl.isEmpty else { return false }
            guard !mentionedWordIds.contains(candidate.id) else { return false }
            guard !queuedWordIds.contains(candidate.id) else { return false }
            guard candidate.imageKind == answer.imageKind else { return false }
            guard candidate.language(in: session) == language else { return false }
            return fairness.fairness(of: candidate.word) == .fair
        }

        let distractor = pool.filter(admits).shuffled(using: &rng).first

        guard let distractor else { return nil }
        return [
            answer,
            ImageChoiceOption(
                id: distractor.id,
                word: distractor.word,
                imageUrl: distractor.imageUrl,
                imageKind: distractor.imageKind
            )
        ].shuffled(using: &rng)
    }
}
