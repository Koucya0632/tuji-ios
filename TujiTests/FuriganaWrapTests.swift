// Pins where a furigana headword breaks and when it shrinks.
//
// The order matters and is the same order the plain headwords already use:
// wrap first, shrink only when wrapping has run out of lines. Roughly a tenth
// of the catalogue's kanji words overrun a phone's detail column once ruby
// widens them, and none of them overruns two lines — so if this ever starts
// scaling the common case, something has regressed.

import CoreGraphics
import Testing
@testable import Tuji

struct FuriganaWrapTests {
    @Test
    func aRowThatFitsIsNeitherWrappedNorScaled() {
        let solution = FuriganaWrap.solve(
            widths: [56, 56, 56],
            available: 361,
            maxLines: 2,
            minScale: 0.5
        )
        #expect(solution.scale == 1)
        #expect(solution.lines == [[0, 1, 2]])
    }

    @Test
    func anOverlongRowWrapsBeforeItShrinks() {
        // 400pt of segments in a 200pt column: two lines at full size, which is
        // strictly better than one line at half size.
        let solution = FuriganaWrap.solve(
            widths: [100, 100, 100, 100],
            available: 200,
            maxLines: 2,
            minScale: 0.5
        )
        #expect(solution.scale == 1)
        #expect(solution.lines == [[0, 1], [2, 3]])
    }

    @Test
    func shrinkingStartsOnlyWhenTheLinesRunOut() {
        // Six 100pt segments cannot make two 200pt lines at full size, so this
        // is the case scaling exists for.
        let solution = FuriganaWrap.solve(
            widths: [100, 100, 100, 100, 100, 100],
            available: 200,
            maxLines: 2,
            minScale: 0.5
        )
        #expect(solution.scale < 1)
        #expect(solution.lines.count <= 2)
        // Every line must actually fit at the chosen scale.
        for line in solution.lines {
            let width = line.reduce(0.0) { total, _ in total + 100 * solution.scale }
            #expect(width <= 200.001)
        }
    }

    @Test
    func scaleNeverGoesBelowTheFloor() {
        // A word that cannot be made to fit overruns rather than becoming
        // unreadable — the same trade the old headword made at 0.5.
        let solution = FuriganaWrap.solve(
            widths: Array(repeating: 100, count: 40),
            available: 200,
            maxLines: 2,
            minScale: 0.5
        )
        #expect(solution.scale >= 0.5)
    }

    @Test
    func aSingleSegmentWiderThanTheColumnStaysOnOneLine() {
        // 豆板醤 → トウバンジャン is one indivisible segment. There is no break
        // to take, so it must not produce an empty first line.
        let solution = FuriganaWrap.solve(
            widths: [500],
            available: 200,
            maxLines: 2,
            minScale: 0.5
        )
        #expect(solution.lines == [[0]])
        #expect(solution.lines.allSatisfy { !$0.isEmpty })
    }

    @Test
    func everySegmentIsPlacedExactlyOnce() {
        let widths: [CGFloat] = [40, 120, 30, 90, 200, 60, 75]
        let solution = FuriganaWrap.solve(
            widths: widths,
            available: 180,
            maxLines: 2,
            minScale: 0.5
        )
        #expect(solution.lines.flatMap(\.self).sorted() == Array(widths.indices))
        #expect(solution.lines.flatMap(\.self) == Array(widths.indices))
    }

    @Test
    func noSegmentsIsNotALine() {
        let solution = FuriganaWrap.solve(widths: [], available: 361, maxLines: 2, minScale: 0.5)
        #expect(solution.lines.isEmpty)
    }

    @Test
    func anUnboundedProposalDoesNotWrap() {
        // `sizeThatFits` can be asked with no width at all; that must not be
        // read as "zero width available" and break after every segment.
        let solution = FuriganaWrap.solve(
            widths: [100, 100, 100],
            available: .infinity,
            maxLines: 2,
            minScale: 0.5
        )
        #expect(solution.lines == [[0, 1, 2]])
        #expect(solution.scale == 1)
    }
}
