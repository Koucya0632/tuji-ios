// The resting height of 複習's reveal sheet.
//
// The rule is one sentence — the sheet rests as tall as the things it refuses
// to hide — and it was previously stated as a constant (`.fraction(0.4)`) that
// could not check itself against the content. It stopped being true once the
// rating section reached three explained rows, and nothing failed: the word the
// user had just answered was simply clipped in half behind the sheet's top edge.

import CoreGraphics
import Testing
@testable import Tuji

struct ReviewRevealLayoutTests {
    /// Measured on an iPhone 17 (874pt tall) in zh-Hant, correct-answer sheet:
    /// summary = headword + reading + 中文 beside the 44pt favourite/audio
    /// stack; rating = rule + label + three 56pt rows + padding.
    private static let measuredSummary: CGFloat = 96
    private static let measuredRating: CGFloat = 275

    /// The invariant the old constant could not promise.
    @Test
    func restIsNeverShorterThanTheThingsItMustShow() {
        let h = ReviewRevealLayout.restHeight(
            summary: Self.measuredSummary,
            rating: Self.measuredRating
        )
        #expect(h >= Self.measuredSummary + Self.measuredRating)
    }

    /// The regression itself: on the screen where this was found, the old
    /// `.fraction(0.4)` resolved to less than the content needed. Any future
    /// change that reintroduces a fraction-shaped guess has to beat this.
    @Test
    func fixedFractionCouldNotHaveFitted() {
        let screenHeight: CGFloat = 874
        let oldResting = ReviewRevealLayout.fallbackFraction * screenHeight
        let needed = ReviewRevealLayout.restHeight(
            summary: Self.measuredSummary,
            rating: Self.measuredRating
        )
        #expect(needed > oldResting)
    }

    /// Dynamic Type grows both measured parts; the resting height has to follow
    /// them, which is the second thing a fraction could not do.
    @Test
    func growsWithItsContent() {
        let base = ReviewRevealLayout.restHeight(summary: 96, rating: 275)
        let larger = ReviewRevealLayout.restHeight(summary: 140, rating: 360)
        // Exactly as much as the content grew, with no scaling fudge in
        // between — the sheet follows the text, it does not interpret it.
        let contentGrowth: CGFloat = (140 - 96) + (360 - 275)
        #expect(larger > base)
        #expect(larger - base == contentGrowth)
    }

    /// A wrong answer offers two ratings instead of three, so the sheet rests
    /// lower. The old constant was the same height either way.
    @Test
    func wrongAnswerSheetRestsLowerThanCorrectOne() {
        let twoRatings = ReviewRevealLayout.restHeight(summary: 96, rating: 275 - 64)
        let threeRatings = ReviewRevealLayout.restHeight(summary: 96, rating: 275)
        #expect(twoRatings < threeRatings)
    }
}
