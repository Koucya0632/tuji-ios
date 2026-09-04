// Pins the 熟練度 spread — the count behind 我 · 進度's depth half.
//
// The tier thresholds themselves belong to MasteryLevel; what is asserted here
// is the counting: that a 0 is not a tier, that the map's three key shapes all
// count, and that 未學 stays out of a readout that has no denominator for it.

import Testing
@testable import Tuji

struct MasteryDistributionTests {
    @Test("an empty map is empty, not a row of zeroes with a bar")
    func emptyMap() {
        let spread = MasteryDistribution.of(scores: [:])
        #expect(spread.isEmpty)
        #expect(spread.total == 0)
    }

    @Test("each tier boundary lands where MasteryLevel puts it")
    func tierBoundaries() {
        let spread = MasteryDistribution.of(scores: [
            "a": 1, "b": 34, // 知道
            "c": 35, "d": 59, // 熟悉
            "e": 60, "f": 79, // 熟練
            "g": 80, "h": 100 // 精通
        ])
        #expect(spread.know == 2)
        #expect(spread.familiar == 2)
        #expect(spread.proficient == 2)
        #expect(spread.expert == 2)
        #expect(spread.total == 8)
    }

    @Test("a score of 0 is 未學, and 未學 is not counted")
    func zeroIsNotKnow() {
        // A row can exist at 0 — decay reaches it. It must not read as 知道,
        // and there is no tier here for it to fall into either.
        let spread = MasteryDistribution.of(scores: ["a": 0, "b": 0, "c": 42])
        #expect(spread.know == 0)
        #expect(spread.familiar == 1)
        #expect(spread.total == 1)
    }

    @Test("自製圖鑑 and 物見 words count — the key shape is irrelevant")
    func everyKeyShapeCounts() {
        // Three key shapes share one map: bare dictionary ids, atlas:<itemId>
        // for 自製圖鑑, saved:<slug> for 物見. All three are words this account
        // studies, so all three belong in "how much have I accumulated".
        let spread = MasteryDistribution.of(scores: [
            "tomato": 85,
            "atlas:6f1c-item": 90,
            "saved:someones-cat": 95
        ])
        #expect(spread.expert == 3)
        #expect(spread.total == 3)
    }

    @Test("segments run in ladder order, so the bar and legend agree")
    func segmentsAreLadderOrdered() {
        let spread = MasteryDistribution.of(scores: ["a": 10, "b": 40, "c": 70, "d": 90])
        #expect(spread.segments.map(\.level) == [.know, .familiar, .proficient, .expert])
        #expect(spread.segments.map(\.words) == [1, 1, 1, 1])
    }

    @Test("total is studied words, never the dictionary size")
    func totalIsStudiedOnly() {
        // 完成度 owns the denominator question, with its scoping and its guest
        // branch. This readout deliberately has no denominator at all.
        let spread = MasteryDistribution.of(scores: ["a": 5, "b": 95])
        #expect(spread.total == 2)
    }
}
