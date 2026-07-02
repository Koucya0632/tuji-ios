// Pins WordsStore.merge: custom (自製圖鑑) words override public ones by id,
// duplicate server ids never trap, and the result keeps the category → word
// ordering every list view assumes.

import Testing
@testable import Tuji

struct WordsStoreMergeTests {
    private func word(_ id: String, word: String, category: String = "animal") -> CardWord {
        CardWord(
            id: id,
            word: word,
            chinese: "",
            imageUrl: "",
            category: category,
            pronunciation: ""
        )
    }

    @Test
    func customWordOverridesPublicWithSameId() {
        let merged = WordsStore.merge(
            publicWords: [self.word("w1", word: "old")],
            customWords: [self.word("w1", word: "new")]
        )
        #expect(merged.count == 1)
        #expect(merged.first?.word == "new")
    }

    @Test
    func duplicatePublicIdsDoNotTrap() {
        // Dictionary(uniqueKeysWithValues:) would crash here; merge must not.
        let merged = WordsStore.merge(
            publicWords: [self.word("dup", word: "first"), self.word("dup", word: "second")],
            customWords: []
        )
        #expect(merged.count == 1)
        #expect(merged.first?.word == "second")
    }

    @Test
    func sortsByCategoryThenWordCaseInsensitive() {
        let merged = WordsStore.merge(
            publicWords: [
                self.word("1", word: "Zebra", category: "animal"),
                self.word("2", word: "apple", category: "food"),
                self.word("3", word: "ant", category: "animal")
            ],
            customWords: []
        )
        #expect(merged.map(\.id) == ["3", "1", "2"])
    }
}
