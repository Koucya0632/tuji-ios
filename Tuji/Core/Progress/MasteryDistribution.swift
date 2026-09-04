// How the account's studied words are spread across the mastery tiers.
//
// 我 · 進度 could say how *wide* the account had gone — 完成度 and the 明細 rows
// are both seen/total — and nothing anywhere said how *deep*. Pushing a word
// from 30 to 85 moved no number on that screen, and 精通, the tier
// `MasteryLevel` calls prestigious and the one holding the system's only 墨底
// pairing, was never counted at all. This is that count.
//
// A pure function over the score map, like `ThemeStatus.of` and
// `CategoryStat.breakdown`, so the arithmetic is reachable from a test rather
// than trapped in a `View`.

import Foundation

struct MasteryDistribution: Equatable {
    let know: Int
    let familiar: Int
    let proficient: Int
    let expert: Int

    /// Nothing counted. Both "this account has studied nothing" and "the store
    /// has not answered yet" — the screen tells those two apart by asking the
    /// store, not by asking this value, which cannot know the difference.
    static let empty = MasteryDistribution(know: 0, familiar: 0, proficient: 0, expert: 0)

    /// Studied words — every tier below, summed. Not the dictionary size.
    var total: Int {
        self.know + self.familiar + self.proficient + self.expert
    }

    var isEmpty: Bool {
        self.total == 0
    }

    /// One tier and how many words sit in it. A named value rather than a tuple
    /// because the views iterate these with `ForEach`, and Swift has no key path
    /// into a tuple element to identify them by.
    ///
    /// The field is `words`, not `count`: `segment.count > 0` reads to both a
    /// human and to SwiftLint's `empty_count` as a collection being non-empty,
    /// and this is a tally of words, not a collection at all.
    struct Segment: Identifiable, Equatable {
        let level: MasteryLevel
        let words: Int
        var id: MasteryLevel {
            self.level
        }
    }

    /// Ladder-ordered tiers, for the stacked bar and its legend. Ordered rather
    /// than a dictionary because the order *is* the meaning.
    var segments: [Segment] {
        [
            Segment(level: .know, words: self.know),
            Segment(level: .familiar, words: self.familiar),
            Segment(level: .proficient, words: self.proficient),
            Segment(level: .expert, words: self.expert)
        ]
    }

    /// Count `scores` — `MasteryStore.byId` — into tiers.
    ///
    /// **未學 is deliberately absent.** A word the user has never studied has no
    /// row and so no entry here, so counting it would need a denominator, and
    /// the only honest denominator is the one `CompletionReadout` already owns
    /// (scoped to the selected 學習主題, with its guest branch and its
    /// published-card total). Minting a second one here is how that module's
    /// documented bug — a percentage describing a selection nobody made —
    /// would come back under a new name. Width is 完成度's question; this
    /// answers depth, over the words that have an answer.
    ///
    /// Key *shape* is irrelevant: bare dictionary ids, `atlas:<itemId>` for
    /// 自製圖鑑 and `saved:<slug>` for 物見 are all words this account studies,
    /// and all three belong in "how much have I accumulated". The map is
    /// already scoped to the current 學習方向 by the `learning` query
    /// `MasteryStore` sends, so there is nothing further to filter.
    static func of(scores: [String: Int]) -> MasteryDistribution {
        var counts: [MasteryLevel: Int] = [:]
        for score in scores.values {
            // Via `MasteryLevel.from`, not a threshold copy: a 0 is 未學, and
            // the one place that rule lives should stay the one place.
            counts[MasteryLevel.from(score: score), default: 0] += 1
        }
        return MasteryDistribution(
            know: counts[.know] ?? 0,
            familiar: counts[.familiar] ?? 0,
            proficient: counts[.proficient] ?? 0,
            expert: counts[.expert] ?? 0
        )
    }
}
