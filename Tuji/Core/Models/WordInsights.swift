// 詞條延伸內容 — /api/words/:id/insights (tuji-web lib/word-insights-present.ts).
//
// Already in the reader's interface language and learning direction, and
// already cut to what this account may see: a non-member gets the 容易混淆
// entries plus how many 常見誤用 / 用法補充 are locked, never their text.

import Foundation

struct WordInsights: Decodable, Hashable {
    let confusables: [WordInsightConfusable]
    let mistakes: [WordInsightMistake]
    let usage: String?
    let lockedMistakesCount: Int
    let usageLocked: Bool

    var isEmpty: Bool {
        self.confusables.isEmpty && self.mistakes.isEmpty && self.usage == nil
            && self.lockedMistakesCount == 0 && !self.usageLocked
    }
}

struct WordInsightConfusable: Decodable, Hashable {
    let term: String
    /// The catalogue word it links to, when it is one.
    let catalogId: String?
    let distinction: String
}

struct WordInsightMistake: Decodable, Hashable {
    let wrong: String
    let right: String
    let why: String
}

struct WordInsightsResponse: Decodable {
    /// false under membership policy v1: the feature does not exist yet.
    let available: Bool
    let insights: WordInsights?
}
