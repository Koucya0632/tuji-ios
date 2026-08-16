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

struct WordPicture: View {
    let url: URL?
    let kind: WordImageKind
    /// Margin between the picture and its container's edge. The page margin
    /// (`s3`) for a hero, smaller for a thumbnail — a 48pt thumb inset by 16
    /// would have nothing left in the middle.
    var inset: CGFloat = Space.s3
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
                    .font(.system(size: self.glyphSize))
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
        switch self.kind {
        case .cutout:
            // Fitted whole. A cut-out is an object with nothing around it, so
            // cropping one cuts into the thing being named.
            image.resizable().aspectRatio(contentMode: .fit)
        case .photograph:
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
