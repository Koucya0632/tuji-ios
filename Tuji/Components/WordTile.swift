// Image tile for a CardWord. Used in the 圖鑑 grid, Today themes, Search
// results, Favorites.
//
// The card is gone. The tile used to be a white rounded rectangle with a border,
// which meant the most prominent thing in a grid of words was the *box*, not the
// picture or the word. Content now sits directly on the paper.
//
// This file owns the *container* — the square, the ground, the clip. How the
// picture meets it (fit vs fill, the inset, the multiply that removes a
// cut-out's white backdrop) belongs to `WordPicture`, which every screen showing
// a word's picture now shares.

import SwiftUI

struct WordTile: View {
    let word: CardWord
    /// Fixed image height. `nil` (the grid case) makes the image square.
    var height: CGFloat?
    var showLabel: Bool = true
    /// When true, shows the mastery scale (used by 圖鑑). Other reuse sites
    /// leave this off.
    var showMastery: Bool = false
    /// The word's 0–100 mastery score, or nil if never studied (→ 未學). Only
    /// consulted when `showMastery` is true.
    var masteryScore: Int?

    @Environment(SettingsStore.self) private var settings

    private var masteryLevel: MasteryLevel {
        MasteryLevel.from(score: self.masteryScore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.image
                .overlay(alignment: .topTrailing) { self.sourceDot }

            if self.showLabel {
                VStack(alignment: .leading, spacing: Space.s1) {
                    if self.showMastery {
                        MasteryBadge(level: self.masteryLevel, score: self.masteryScore)
                            .padding(.top, Space.s2)
                            .padding(.bottom, Space.s1)
                    }

                    // Two lines are reserved whether or not the word needs
                    // them, so the reading / 中文 under a short word sit on the
                    // same line as the ones under a wrapped neighbour.
                    // `reservesSpace` rather than a fixed `.frame`, which would
                    // stop scaling with Dynamic Type.
                    Text(self.word.word)
                        .font(.tujiH3)
                        .foregroundStyle(.tujiInk)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)

                    if let reading = ReadingLine.shown(self.word.reading, for: self.word.word) {
                        Text(reading)
                            .font(.tujiBodySm)
                            .foregroundStyle(.tujiInk3)
                            .lineLimit(1)
                            // A clipped reading is worthless — 「くれんじんぐうぉ…」
                            // tells you nothing about how to say the word — so a
                            // long one shrinks instead. The longest in the
                            // dictionary (mrt（たいわんのちかてつ）) needs ~196pt
                            // against a ~176pt tile.
                            .minimumScaleFactor(0.8)
                    }

                    if self.settings.current.showZh {
                        Text(self.word.chinese)
                            .font(.tujiBodySm)
                            .foregroundStyle(.tujiInk3)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The container is what holds the square, not the image. Putting
    /// `.aspectRatio` on `LazyImage` lets each picture's own proportions leak
    /// through, so a grid of tiles came out ragged — wide images sat short,
    /// tall ones sat long, and the two columns stopped lining up.
    private var image: some View {
        Group {
            if let height = self.height {
                Color.tujiPaper2.frame(height: height)
            } else {
                Color.tujiPaper2.aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay { self.picture }
        .clipped()
    }

    private var picture: some View {
        WordPicture(url: self.word.imageURL, kind: self.word.imageKind)
    }

    /// An 8pt square marking where the word came from. Ink = you made it,
    /// teal = you took it in from the community (teal means accumulation, and a
    /// saved word is exactly that). Dictionary words carry no mark, because
    /// "the dictionary" is the default and does not need saying.
    @ViewBuilder
    private var sourceDot: some View {
        switch self.word.category {
        case "custom":
            Rectangle().fill(.tujiInk).frame(width: 8, height: 8).padding(Space.s2)
        case "community":
            Rectangle().fill(.tujiAccumulation).frame(width: 8, height: 8).padding(Space.s2)
        default:
            EmptyView()
        }
    }
}

#Preview {
    let sample = CardWord(
        id: "tomato",
        word: "tomato",
        chinese: "蕃茄",
        imageUrl: "https://example.com/tomato.png",
        category: "kitchen",
        pronunciation: "/təˈmeɪtoʊ/"
    )
    ScrollView {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Space.s2),
                GridItem(.flexible(), spacing: Space.s2)
            ],
            spacing: Space.s4
        ) {
            ForEach(0..<4, id: \.self) { _ in
                WordTile(word: sample, showMastery: true, masteryScore: 62)
            }
        }
        .padding(.horizontal, Space.s4)
    }
    .background(.tujiPaper)
    .environment(SettingsStore.shared)
}
