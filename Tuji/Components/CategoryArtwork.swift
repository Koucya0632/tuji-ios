// A theme's picture, wherever a theme is drawn large enough to have one.
//
// Two screens ask for it now — 圖鑑·官方's shelf tiles and 主題's bleeding hero —
// and the answer has three branches (a bundled asset, the catalogue's remote
// cover, nothing at all), which is exactly the shape of rule this codebase has
// historically written twice and then fixed once.
//
// It fills whatever it is given and nothing else: the frame, the aspect ratio
// and the clipping belong to the caller, because a 16:9 hero and a tile's
// header want different ones from the same image.

import Nuke
import NukeUI
import SwiftUI

struct CategoryArtwork: View {
    let category: TujiCategory

    var body: some View {
        if self.category.id == "kitchen" {
            // Bundled rather than fetched: 廚房 is the first theme most people
            // open, and its cover is the one picture worth having before the
            // network answers.
            Image("category-kitchen-hero")
                .resizable()
                .scaledToFill()
        } else if let url = self.category.imageURL {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFill()
                } else {
                    TujiImagePlaceholder()
                }
            }
            .pipeline(.shared)
        } else {
            // A theme with no cover (`imageUrl` is an empty string for a few of
            // them) gets paper, not a broken-image glyph.
            Color.tujiPaper2
        }
    }
}
