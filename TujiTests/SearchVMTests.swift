// Pins SearchVM's local ranking (exact → prefix → contains, shorter first)
// and the local-first merge/dedupe the search screen builds on.

import Testing
@testable import Tuji

struct SearchVMTests {
    private func word(
        _ id: String,
        word: String,
        chinese: String = "",
        pronunciation: String = "",
        reading: String? = nil
    )
        -> CardWord
    {
        CardWord(
            id: id,
            word: word,
            chinese: chinese,
            imageUrl: "",
            category: "test",
            pronunciation: pronunciation,
            reading: reading
        )
    }

    @Test
    func ranksExactBeforePrefixBeforeContains() {
        let words = [
            self.word("contains", word: "wildcat"),
            self.word("prefix", word: "catalog"),
            self.word("exact", word: "cat"),
            self.word("miss", word: "dog")
        ]
        let hits = SearchVM.localMatches("cat", in: words)
        #expect(hits.map(\.id) == ["exact", "prefix", "contains"])
    }

    @Test
    func shorterWordWinsWithinSameRank() {
        let words = [
            self.word("long", word: "catalog"),
            self.word("short", word: "cats")
        ]
        let hits = SearchVM.localMatches("cat", in: words)
        #expect(hits.map(\.id) == ["short", "long"])
    }

    @Test
    func matchesChineseGloss() {
        let words = [
            self.word("zh-contains", word: "wildcat", chinese: "野貓"),
            self.word("zh-prefix", word: "cat", chinese: "貓")
        ]
        let hits = SearchVM.localMatches("貓", in: words)
        #expect(hits.map(\.id) == ["zh-prefix", "zh-contains"])
    }

    @Test
    func matchesKanaReading() {
        let words = [self.word("ja", word: "猫", chinese: "貓", reading: "ねこ")]
        #expect(SearchVM.localMatches("ねこ", in: words).map(\.id) == ["ja"])
    }

    @Test
    func emptyQueryReturnsNothing() {
        let words = [self.word("any", word: "cat")]
        #expect(SearchVM.localMatches("", in: words).isEmpty)
    }

    @Test
    func mergeKeepsLocalOrderAndDedupes() {
        let local = [self.word("a", word: "apple"), self.word("b", word: "banana")]
        let remote = [self.word("b", word: "banana"), self.word("c", word: "cherry")]
        let merged = SearchVM.merge(local: local, remote: remote)
        #expect(merged.map(\.id) == ["a", "b", "c"])
    }
}
