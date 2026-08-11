// Pins the sizes a furigana headword may take.
//
// The bottom of this ladder is the one number the whole feature was shaped
// around: below ~13pt the CJK face's strokes merge, which is why TujiFont.swift
// removed that end of the scale and why the 圖鑑 grid gets no ruby at all. Ruby
// is half the headword, so the headword's floor depends on its own size — 0.47
// under a 56pt word, 0.77 under a 34pt one. These tests exist so that stays a
// property of the code rather than a fact someone has to remember.

import CoreGraphics
import Testing
@testable import Tuji

struct FuriganaScaleLadderTests {
    private let floor = FuriganaScaleLadder.minimumRubyPoint

    @Test
    func theLadderStartsAtFullSize() {
        #expect(FuriganaScaleLadder.steps(baseSize: 56).first == 1)
    }

    @Test
    func theLadderDescends() {
        let steps = FuriganaScaleLadder.steps(baseSize: 56)
        #expect(steps.count > 1)
        for (a, b) in zip(steps, steps.dropFirst()) {
            #expect(b < a)
        }
    }

    @Test
    func noRungPutsRubyBelowTheFloor() {
        // The whole point. Every size the view can choose has to stay legible.
        for base in [56.0, 44.0, 34.0, 28.0] as [CGFloat] {
            for step in FuriganaScaleLadder.steps(baseSize: base) {
                let ruby = base * 0.5 * step
                #expect(
                    ruby >= self.floor - 0.001,
                    "base \(base) step \(step) gives \(ruby)pt ruby"
                )
            }
        }
    }

    @Test
    func theFloorMovesWithTheBaseSize() throws {
        // A 34pt headword cannot shrink nearly as far as a 56pt one before its
        // ruby stops resolving — the ladder has to know that.
        let big = try #require(FuriganaScaleLadder.steps(baseSize: 56).last)
        let small = try #require(FuriganaScaleLadder.steps(baseSize: 34).last)
        #expect(big < small)
        #expect(abs(big - self.floor / 28) < 0.01)
        #expect(abs(small - self.floor / 17) < 0.01)
    }

    @Test
    func aBaseTooSmallToShrinkStillOffersOneSize() {
        // 20pt base → 10pt ruby, already under the floor. There is nothing to
        // choose between, but the view must still get something to draw.
        let steps = FuriganaScaleLadder.steps(baseSize: 20)
        #expect(steps == [1])
    }

    @Test
    func aDegenerateBaseDoesNotProduceAnEmptyLadder() {
        // Guards the call site that indexes the rungs: an empty array would
        // crash rather than merely look wrong.
        #expect(!FuriganaScaleLadder.steps(baseSize: 0).isEmpty)
        #expect(!FuriganaScaleLadder.steps(baseSize: 56, rubyRatio: 0).isEmpty)
    }

    @Test
    func theWidestCatalogueWordFitsWithRoomToSpare() {
        // 鶏ガラスープの素 and 背もたれクッション are the widest ruby-bearing
        // headwords in the catalogue: 9.0em against a ~290pt detail column, so
        // they need about 0.575. If a future change lifts the floor above that,
        // the two of them start overflowing instead of shrinking.
        let needed: CGFloat = 290 / (9.0 * 56)
        let steps = FuriganaScaleLadder.steps(baseSize: 56)
        #expect(steps.contains { $0 <= needed })
    }

    @Test
    func theShippedHeadwordSizeIsTheFloorItself() {
        // Why 26 and not 24 or 34. `TujiHeadword` sets one size for every screen
        // so that a short word is not twice the size of a long one, and 26 is
        // the smallest that still clears the ruby floor exactly: half of it is
        // 13pt. The ladder therefore has nowhere to shrink to and collapses to a
        // single rung, which is correct — every kanji word in the catalogue fits
        // its column at 26pt, so nothing needs to.
        let shipped: CGFloat = 26
        #expect(shipped * 0.5 == self.floor)
        #expect(FuriganaScaleLadder.steps(baseSize: shipped) == [1])
        // One point smaller and the kana stop resolving.
        #expect((shipped - 1) * 0.5 < self.floor)
    }
}
