// Image tile for a CardWord. Used in Cards grid, Today themes, Search
// results, etc. Image loads via Nuke's LazyImage — cached on disk + in
// memory automatically.

import Nuke
import NukeUI
import SwiftUI

struct WordTile: View {
    let word: CardWord
    var height: CGFloat = 120
    var showLabel: Bool = true
    /// When true, overlays a mastery level badge + score (used by 圖鑑). Other
    /// reuse sites (Today / Search / Favorites) leave this off.
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
            ZStack {
                Rectangle().fill(.tujiCard)

                LazyImage(url: self.word.imageURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(Space.s2)
                    } else if state.error != nil {
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundStyle(.tujiInk4)
                    } else {
                        ProgressView()
                            .tint(.tujiTeal)
                    }
                }
                .pipeline(.shared)
            }
            .frame(height: self.height)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if self.showMastery {
                    MasteryBadge(level: self.masteryLevel)
                        .padding(Space.s2)
                }
            }

            if self.showLabel {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text(self.word.word)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.tujiInk)
                        if self.showMastery, let score = self.masteryScore {
                            Spacer(minLength: 0)
                            Text("\(score)")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(self.masteryLevel.color)
                        }
                    }

                    if self.settings.current.showZh {
                        Text(self.word.chinese)
                            .font(.tujiCaption)
                            .foregroundStyle(.tujiInk3)
                            .lineLimit(1)
                    }
                }
                .padding(Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.tujiCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
        )
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
    return ScrollView {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                WordTile(word: sample)
            }
        }
        .padding()
    }
    .background(.tujiBg)
    .environment(SettingsStore.shared)
}
