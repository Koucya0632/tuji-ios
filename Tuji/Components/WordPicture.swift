// How a word's picture meets its container — the one place that decides it.
//
// Seven screens hand-wrote the same three-part decision (fit vs fill, how far
// to inset, whether to multiply), and all three parts have to agree or the
// picture comes out wrong. They did not agree. There were four behaviours:
//
//   • 圖鑑 / 認識 / 複習 / 選字 — cut-out inset s3 and multiplied, photograph
//     filling the container edge to edge
//   • 完成頁 thumbnails — the same, inset s1
//   • 拼字 — always fit, inset s2, **no multiply at all**, on `tujiPaper`
//
// Two things were wrong with that spread. The third one still shows the white
// backdrop `WordTile` documents as "the app's most widespread visual flaw" —
// the fix never reached 拼字. And the first two gave a photograph the *larger*
// frame: a user's own capture bled to the screen edge at ~500pt while the
// dictionary's studio cut-out sat politely inset at ~260pt. The pictures in
// this app that most need composing — a phone snapshot of a table, taken
// one-handed — were the ones the layout shouted loudest.
//
// Both kinds are now placed the same way: inset on the ground by the caller's
// margin. What still differs is only what genuinely differs — a cut-out is
// fitted whole and multiplied into the paper, a photograph fills its inset
// rect and is cropped to it.

import Nuke
import NukeUI
import SwiftUI

/// Whether a photograph may be cropped to its container's shape.
///
/// Only photographs have anything at stake: a cut-out is a single object on
/// white and is always fitted whole. But 拍照新增 deliberately lets the user box
/// the subject at **any aspect ratio** — `ImageCropView` is four corner handles
/// precisely because squaring the frame would cut the thing being identified —
/// and then every surface cropped it back to the container's shape anyway. The
/// capture flow respected the user's framing and the display did not.
enum WordFraming {
    /// Cropped to fill. The picture is an identifier here — a row's thumbnail,
    /// a tile in a recap grid — and a tidy grid is worth more than the corners.
    case cropped
    /// Shown whole, letterboxed on the ground. For the screens that hold the
    /// picture up and ask *what is this*: cutting the subject out of frame
    /// there damages the question itself.
    case whole
}

struct WordPicture: View {
    let url: URL?
    let kind: WordImageKind
    /// Margin between the picture and its container's edge. The page margin
    /// (`s3`) for a hero, smaller for a thumbnail — a 48pt thumb inset by 16
    /// would have nothing left in the middle.
    var inset: CGFloat = Space.s3
    /// Only consulted for a photograph; a cut-out is always whole.
    var framing: WordFraming = .cropped
    /// The "this picture did not load" glyph, sized to its container.
    var glyphSize: CGFloat = 24

    var body: some View {
        LazyImage(url: self.url) { state in
            if let image = state.image {
                self.placed(image)
                    .padding(self.inset)
                    // White × any ground = that ground, so a cut-out's backdrop
                    // disappears and the object keeps its own colour. A
                    // photograph has no backdrop to remove and multiplying one
                    // would just darken the whole frame.
                    .blendMode(self.kind == .cutout ? .multiply : .normal)
            } else if state.error != nil {
                Image(systemName: "photo")
                    .font(.tujiIcon(self.glyphSize))
                    .foregroundStyle(.tujiInk3)
            } else {
                TujiImagePlaceholder()
            }
        }
        .pipeline(.shared)
    }

    /// How the picture meets the inset rect — the only thing the two kinds
    /// still disagree about, besides the blend mode.
    @ViewBuilder
    private func placed(_ image: Image) -> some View {
        switch (self.kind, self.framing) {
        case (.cutout, _), (.photograph, .whole):
            // Fitted whole. A cut-out is an object with nothing around it, so
            // cropping one cuts into the thing being named; a photograph on a
            // `.whole` surface is the question the screen is asking.
            image.resizable().aspectRatio(contentMode: .fit)
        case (.photograph, .cropped):
            // Filled and cropped to the inset rect. The explicit frame is what
            // makes that deterministic: `.aspectRatio(.fill)` alone reports a
            // layout size that depends on the picture's own proportions, so in
            // one grid a landscape photo sat edge to edge while a portrait one
            // kept side margins — the ragged-columns problem the square
            // container exists to prevent.
            GeometryReader { proxy in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
        }
    }
}
