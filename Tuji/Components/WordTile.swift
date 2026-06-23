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
    /// The word's soonest next-review date, or nil if unscheduled. Only shown
    /// when `showMastery` is true.
    var nextReviewDate: Date?

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
                    // 圖鑑 surfaces the mastery *level* via the badge overlay on
                    // the image; the numeric score stays on the detail page only.
                    Text(self.word.word)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.tujiInk)

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
        // Bottom-right corner of the whole card (below the label).
        .overlay(alignment: .bottomTrailing) {
            if self.showMastery, let due = self.nextReviewDate {
                self.countdownPill(due)
                    .padding(Space.s2)
            }
        }
    }

    /// Next-review countdown pill for the tile's bottom-right corner. Neutral
    /// grey on a white capsule (matches the de-emphasized badge palette and
    /// stays legible over artwork).
    private func countdownPill(_ date: Date) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
            Text(ReviewSchedule.countdownLabel(until: date))
        }
        .font(.system(size: 10, weight: .heavy))
        .foregroundStyle(.tujiInk3)
        .lineLimit(1)
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 3)
        .background(.tujiCard.opacity(0.95), in: .capsule)
        .overlay(Capsule().stroke(.tujiInk4.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
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
