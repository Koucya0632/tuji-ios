// 詞塊卡片的幾何 — where the card goes, and what outline it wears when it gets
// there.
//
// Pure arithmetic and one `Path`, kept out of `GlossCard.swift` because this is
// the half that can be wrong in ways a screenshot of one device at one text
// size will not show: a card running off the top of a short screen, a caret
// leaving the card when the word sits at the start of a line, the fallback
// quietly becoming unreachable. `ReviewRevealLayout` is the same move for the
// same reason — the answer a layout computes is testable, the layout itself is
// not.

import SwiftUI

/// Where the card goes relative to the 詞塊 it is about.
nonisolated enum GlossCalloutPlacement {
    /// 16 × 8. Both come off the spacing scale so the caret grows with nothing
    /// and stays the same shape everywhere.
    static let caretSize = CGSize(width: Space.s3, height: Space.s2)
    /// The page margin — the card shares the one horizontal boundary the rest
    /// of the app aligns to, rather than inventing a second.
    static let sideMargin = Space.s4
    /// Between the caret's tip and the 詞塊 it points at.
    static let anchorGap = Space.s2
    /// Between the card and the top or bottom of the host.
    static let edgeMargin = Space.s3

    /// The card is always this wide, placed or not. A width that depended on
    /// the placement would feed back into the height the placement is decided
    /// from, and the two would chase each other.
    static func cardWidth(in container: CGSize) -> CGFloat {
        max(0, container.width - 2 * self.sideMargin)
    }

    struct Result: Equatable {
        /// The card's top edge, in the host's coordinate space.
        let top: CGFloat
        /// The caret's centre, in the card's own coordinate space.
        let caretX: CGFloat
        /// Caret on the bottom edge — the card sits above the word.
        let pointsDown: Bool
    }

    /// nil ⇒ the card fits neither above nor below the word; the caller falls
    /// back to the bottom of the screen and draws no caret.
    ///
    /// `cardSize.height` already includes the caret's band, which is reserved
    /// on one side whichever way the caret ends up pointing — so the height
    /// does not depend on the answer this function is computing.
    static func place(anchor: CGRect, cardSize: CGSize, container: CGSize) -> Result? {
        guard cardSize.height > 0, container.height > 0 else { return nil }
        let above = anchor.minY - self.anchorGap - cardSize.height
        let below = anchor.maxY + self.anchorGap
        let pointsDown: Bool
        if above >= self.edgeMargin {
            // Above is the preference: the card lands between the reader's eye
            // and the word rather than under their thumb.
            pointsDown = true
        } else if below + cardSize.height <= container.height - self.edgeMargin {
            pointsDown = false
        } else {
            return nil
        }
        return Result(
            top: pointsDown ? above : below,
            caretX: self.caretX(anchor: anchor, cardWidth: cardSize.width),
            pointsDown: pointsDown
        )
    }

    /// The caret follows the word until it would leave the card — a word at the
    /// start or end of a line is the common case, not an edge one.
    static func caretX(anchor: CGRect, cardWidth: CGFloat) -> CGFloat {
        let half = self.caretSize.width / 2
        let lower = half + self.anchorGap
        let upper = cardWidth - half - self.anchorGap
        guard lower <= upper else { return cardWidth / 2 }
        return min(max(anchor.midX - self.sideMargin, lower), upper)
    }
}

/// The card's outline: a square-cornered block with one caret, as a single
/// path.
///
/// One path rather than a card plus a stuck-on triangle, because the 1px
/// `tujiRule` edge has to run round the caret without a seam — and the seam is
/// the only thing a hairline border can get wrong.
nonisolated struct GlossCalloutShape: Shape {
    struct Caret: Equatable {
        let x: CGFloat
        let pointsDown: Bool
    }

    /// nil ⇒ no caret. The card could not be placed beside the 詞塊 and is
    /// sitting at the bottom instead; a caret aimed at nothing is worse than
    /// no caret.
    let caret: Caret?

    func path(in rect: CGRect) -> Path {
        let band = GlossCalloutPlacement.caretSize.height
        let half = GlossCalloutPlacement.caretSize.width / 2
        // The band is reserved on the bottom when there is no caret, so the
        // card's height is the same either way.
        let pointsDown = self.caret?.pointsDown ?? true
        let body = CGRect(
            x: rect.minX,
            y: pointsDown ? rect.minY : rect.minY + band,
            width: rect.width,
            height: max(0, rect.height - band)
        )
        var path = Path()
        guard let caret = self.caret, body.width > GlossCalloutPlacement.caretSize.width else {
            path.addRect(body)
            return path
        }
        let x = min(max(caret.x, body.minX + half), body.maxX - half)
        if caret.pointsDown {
            path.move(to: CGPoint(x: body.minX, y: body.minY))
            path.addLine(to: CGPoint(x: body.maxX, y: body.minY))
            path.addLine(to: CGPoint(x: body.maxX, y: body.maxY))
            path.addLine(to: CGPoint(x: x + half, y: body.maxY))
            path.addLine(to: CGPoint(x: x, y: body.maxY + band))
            path.addLine(to: CGPoint(x: x - half, y: body.maxY))
            path.addLine(to: CGPoint(x: body.minX, y: body.maxY))
        } else {
            path.move(to: CGPoint(x: body.minX, y: body.maxY))
            path.addLine(to: CGPoint(x: body.minX, y: body.minY))
            path.addLine(to: CGPoint(x: x - half, y: body.minY))
            path.addLine(to: CGPoint(x: x, y: body.minY - band))
            path.addLine(to: CGPoint(x: x + half, y: body.minY))
            path.addLine(to: CGPoint(x: body.maxX, y: body.minY))
            path.addLine(to: CGPoint(x: body.maxX, y: body.maxY))
        }
        path.closeSubpath()
        return path
    }
}
