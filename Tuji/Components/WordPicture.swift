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
                // Fitted whole, always. 拍照新增 deliberately lets the user box
                // the subject at **any aspect ratio** — `ImageCropView` is four
                // corner handles precisely because squaring the frame would cut
                // the thing being identified — and the server stores what they
                // framed (`fit: "inside"`, which never crops). Filling to the
                // container's shape was the one place that took it back, so the
                // card you made did not match the crop you made.
                //
                // The grid survives it: the *containers* are still identical
                // squares, so the columns line up. What varies is how much
                // ground shows around each picture, and that is the picture's
                // own proportions being told the truth about.
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
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
}
