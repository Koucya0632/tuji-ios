// Pins where the 詞塊 card goes, and what its outline does when it gets there.
//
// This is the half of the feature a screenshot cannot check: one device, one
// text size and one tapped word show one of the answers below. The failures
// worth catching are a card that runs off the top of a short screen, a caret
// that leaves the card when the word sits at the start of a line, and the
// fallback — no anchor, no caret — quietly becoming unreachable.

import CoreGraphics
import Testing
@testable import Tuji

struct GlossCalloutPlacementTests {
    /// Roughly an iPhone's safe area, and the card width that follows from it.
    private let container = CGSize(width: 393, height: 780)
    private var cardWidth: CGFloat {
        GlossCalloutPlacement.cardWidth(in: self.container)
    }

    private func card(height: CGFloat) -> CGSize {
        CGSize(width: self.cardWidth, height: height)
    }

    private func word(x: CGFloat = 180, y: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: 70, height: 20)
    }

    // MARK: - Which side

    @Test
    func theCardIsInsetByOnePageMarginOnEachSide() {
        #expect(self.cardWidth == self.container.width - 2 * Space.s4)
    }

    /// Above is the preference: the card lands between the reader's eye and the
    /// word rather than under the hand that just tapped it.
    @Test
    func aWordWithRoomAboveItGetsACardAboveIt() throws {
        let anchor = self.word(y: 400)
        let placement = try #require(
            GlossCalloutPlacement.place(anchor: anchor, cardSize: self.card(height: 160), container: self.container)
        )
        #expect(placement.pointsDown)
        #expect(placement.top == anchor.minY - GlossCalloutPlacement.anchorGap - 160)
    }

    @Test
    func aWordNearTheTopGetsACardBelowIt() throws {
        let anchor = self.word(y: 100)
        let placement = try #require(
            GlossCalloutPlacement.place(anchor: anchor, cardSize: self.card(height: 160), container: self.container)
        )
        #expect(!placement.pointsDown)
        #expect(placement.top == anchor.maxY + GlossCalloutPlacement.anchorGap)
    }

    /// The card is measured, not constant, so a larger text size makes it
    /// taller — and a gap that fitted at one size stops fitting at the next.
    /// The same word must then flip rather than run off the screen.
    @Test
    func aTallerCardTurnsAFitIntoAFlip() throws {
        let anchor = self.word(y: 180)
        let short = try #require(
            GlossCalloutPlacement.place(anchor: anchor, cardSize: self.card(height: 150), container: self.container)
        )
        let tall = try #require(
            GlossCalloutPlacement.place(anchor: anchor, cardSize: self.card(height: 160), container: self.container)
        )
        #expect(short.pointsDown)
        #expect(!tall.pointsDown)
    }

    /// The fallback the whole design leans on: neither side fits, so the caller
    /// parks the card at the bottom and draws no caret at all.
    @Test
    func aCardThatFitsNeitherWayIsNotPlaced() {
        #expect(
            GlossCalloutPlacement.place(
                anchor: self.word(y: 300),
                cardSize: self.card(height: 700),
                container: self.container
            ) == nil
        )
    }

    /// An unmeasured card has no height yet, and placing it would put the caret
    /// at the word's edge for the one frame before the measurement lands.
    @Test
    func anUnmeasuredCardIsNotPlaced() {
        #expect(
            GlossCalloutPlacement.place(
                anchor: self.word(y: 300),
                cardSize: CGSize(width: self.cardWidth, height: 0),
                container: self.container
            ) == nil
        )
    }

    // MARK: - Where the caret points

    @Test
    func theCaretFollowsTheWord() {
        let anchor = self.word(x: 180, y: 400)
        #expect(
            GlossCalloutPlacement.caretX(anchor: anchor, cardWidth: self.cardWidth)
                == anchor.midX - Space.s4
        )
    }

    /// A word at the start or end of a line is the common case, not an edge
    /// one — English sentences wrap and Japanese ones have no spaces at all.
    @Test
    func theCaretStopsInsideTheCardAtEitherEndOfALine() {
        let half = GlossCalloutPlacement.caretSize.width / 2
        let atStart = GlossCalloutPlacement.caretX(
            anchor: CGRect(x: 2, y: 400, width: 20, height: 20),
            cardWidth: self.cardWidth
        )
        let atEnd = GlossCalloutPlacement.caretX(
            anchor: CGRect(x: 360, y: 400, width: 20, height: 20),
            cardWidth: self.cardWidth
        )
        #expect(atStart >= half)
        #expect(atEnd <= self.cardWidth - half)
    }

    // MARK: - The outline

    /// The caret is part of the card's one path, so the path has to reach past
    /// the block to the tip — that is what a stuck-on triangle would not do.
    @Test
    func theCaretExtendsThePathToItsTip() {
        let rect = CGRect(x: 0, y: 0, width: 345, height: 160)
        let down = GlossCalloutShape(caret: .init(x: 100, pointsDown: true)).path(in: rect)
        let up = GlossCalloutShape(caret: .init(x: 100, pointsDown: false)).path(in: rect)
        #expect(down.boundingRect.maxY == rect.maxY)
        #expect(up.boundingRect.minY == rect.minY)
    }

    /// The caret's band is reserved whether or not there is a caret, so the
    /// height a placement is decided from never depends on the placement.
    @Test
    func aCardWithNoCaretIsAPlainBlockAndTheSameHeight() {
        let rect = CGRect(x: 0, y: 0, width: 345, height: 160)
        let plain = GlossCalloutShape(caret: nil).path(in: rect)
        let band = GlossCalloutPlacement.caretSize.height
        #expect(plain.boundingRect == CGRect(x: 0, y: 0, width: 345, height: 160 - band))
    }

    /// The word can sit anywhere on the line, including outside the card the
    /// caret belongs to; the shape clamps rather than drawing a spike hanging
    /// off the corner.
    @Test
    func aCaretPastTheCornerIsPulledBackInside() {
        let rect = CGRect(x: 0, y: 0, width: 345, height: 160)
        let path = GlossCalloutShape(caret: .init(x: 900, pointsDown: true)).path(in: rect)
        #expect(path.boundingRect.maxX <= rect.maxX)
    }
}
