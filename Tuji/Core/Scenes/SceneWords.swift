// A 問句's 相關詞條: its `wordIds` looked up in the dictionary `WordsStore`
// already holds. Nothing is bundled, so offline or before the first load the
// list is shorter or empty, and the screens hide it rather than explain.
//
// A lock only marks a topic this account may not study. Browsing is never
// gated, so a locked word still opens.

import Foundation

struct SceneWord: Identifiable, Hashable {
    let word: CardWord
    /// Studying this word's topic needs 永久會員.
    let isLocked: Bool

    var id: String {
        self.word.id
    }
}

enum SceneWords {
    /// Ids the dictionary does not have are dropped; the rest keep the JSON's order.
    ///
    /// - Parameter studyable: `Membership.studyableCategories`. nil = no gate,
    ///   so nothing is locked.
    /// - Parameter direction: the ids name 日文圖鑑 words, so a zh-en learner
    ///   gets none.
    static func resolve(
        ids: [String],
        in words: [CardWord],
        studyable: [String]?,
        direction: LearningDirection
    )
        -> [SceneWord]
    {
        guard direction == .zhJa else { return [] }
        let allowed = studyable.map(Set.init)
        return ids.compactMap { id in
            guard let word = words.first(where: { $0.id == id }) else { return nil }
            return SceneWord(word: word, isLocked: allowed.map { !$0.contains(word.category) } ?? false)
        }
    }
}
