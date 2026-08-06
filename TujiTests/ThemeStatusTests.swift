// The theme-tile completion rule. It was a private method on TodayView until
// 主題 (CategoryIndexView) needed the same answer; extracting it is what makes
// it testable, and the ordering between 全精通 and 完成 is the part worth
// pinning down — they can both be true at once.

import Testing
@testable import Tuji

struct ThemeStatusTests {
    /// No words behind the theme means nothing to be finished with.
    @Test
    func emptyThemeHasNoStatus() {
        let status = ThemeStatus.of(
            words: [],
            masteryScore: { _ in 100 },
            progress: [CategoryProgress(category: "kitchen", total: 0, seen: 0)],
            categoryId: "kitchen"
        )
        #expect(status == .none)
    }

    /// Every word at 精通 (≥ 80) — an unstudied word reads as 未學, so all-精通
    /// also means all-seen.
    @Test
    func everyWordAtExpertIsMastered() {
        let status = ThemeStatus.of(
            words: [self.word("a"), self.word("b")],
            masteryScore: { _ in 85 },
            progress: [],
            categoryId: "kitchen"
        )
        #expect(status == .mastered)
    }

    /// 全精通 wins over 完成 when both hold, since it is the stronger claim.
    @Test
    func masteredBeatsCompleted() {
        let status = ThemeStatus.of(
            words: [self.word("a")],
            masteryScore: { _ in 100 },
            progress: [CategoryProgress(category: "kitchen", total: 1, seen: 1)],
            categoryId: "kitchen"
        )
        #expect(status == .mastered)
    }

    /// Seen everything but decayed below 精通 → 完成, not 全精通.
    @Test
    func seenEverythingButDecayedIsCompleted() {
        let status = ThemeStatus.of(
            words: [self.word("a"), self.word("b")],
            masteryScore: { _ in 40 },
            progress: [CategoryProgress(category: "kitchen", total: 2, seen: 2)],
            categoryId: "kitchen"
        )
        #expect(status == .completed)
    }

    /// A progress row for a *different* theme must not count.
    @Test
    func progressRowForAnotherThemeIsIgnored() {
        let status = ThemeStatus.of(
            words: [self.word("a")],
            masteryScore: { _ in 10 },
            progress: [CategoryProgress(category: "bathroom", total: 1, seen: 1)],
            categoryId: "kitchen"
        )
        #expect(status == .none)
    }

    /// Guests have no mastery rows at all — nil scores read as 未學, which is
    /// not 精通, so the tile stays unmarked rather than claiming 全精通 over an
    /// empty map.
    @Test
    func unstudiedWordsAreNotMastered() {
        let status = ThemeStatus.of(
            words: [self.word("a"), self.word("b")],
            masteryScore: { _ in nil },
            progress: [],
            categoryId: "kitchen"
        )
        #expect(status == .none)
    }

    /// One straggler is enough to lose 全精通.
    @Test
    func oneUnmasteredWordBlocksMastered() {
        let status = ThemeStatus.of(
            words: [self.word("a"), self.word("b")],
            masteryScore: { id in id == "a" ? 100 : 79 },
            progress: [],
            categoryId: "kitchen"
        )
        #expect(status == .none)
    }

    private func word(_ id: String) -> CardWord {
        CardWord(
            id: id,
            word: id,
            chinese: id,
            imageUrl: "",
            category: "kitchen",
            pronunciation: ""
        )
    }
}
