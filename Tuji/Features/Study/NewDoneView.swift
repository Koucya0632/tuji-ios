// Completion celebration shown after Step 3 wraps. Lists the words
// learned this session and a 完成 CTA back to the previous screen.

import Nuke
import NukeUI
import SwiftUI

struct NewDoneView: View {
    let queue: [StudyQueueItem]
    let onFinish: () -> Void

    @Environment(MasteryStore.self) private var mastery
    @Environment(StudyStatsStore.self) private var studyStats

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s5) {
                self.hero
                StudyWordGrid(items: self.queue)
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        // Learning new words writes mastery + creates user_cards (the deferred
        // recognize POSTs fired as each word cleared Spell). Bust both caches so
        // the just-learned words leave 未學 on the 圖鑑/詳情, and 今日目標 on Today
        // reflects this session's completions instead of waiting out the 30s TTL.
        .task {
            self.mastery.invalidate()
            self.studyStats.invalidate()
            await self.mastery.reload()
        }
        .safeAreaInset(edge: .bottom) {
            BBtn(
                title: "完成",
                bg: .tujiTeal,
                fg: .white,
                fullWidth: true,
                icon: "checkmark",
                action: self.onFinish
            )
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.s4)
        }
    }

    private var hero: some View {
        MascotCelebrationCard(
            title: "這節學了 \(self.queue.count) 個新字",
            accent: .tujiTeal
        ) {
            Text("它們已加入你的圖鑑")
                .font(.tujiBody)
                .foregroundStyle(.tujiInk3)
        }
        .padding(.top, Space.s8)
    }

}

/// Two-column word grid shown on the study-complete screens (new-word and
/// review), so both celebrate the session's words with the same tile style.
struct StudyWordGrid: View {
    let items: [StudyQueueItem]

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Space.s3),
                GridItem(.flexible(), spacing: Space.s3)
            ],
            spacing: Space.s3
        ) {
            ForEach(self.items) { item in
                self.tile(for: item)
            }
        }
    }

    private func tile(for item: StudyQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Rectangle().fill(.tujiCard)
                LazyImage(url: item.word.imageURL) { state in
                    if let image = state.image {
                        image.resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(Space.s2)
                    } else if state.error != nil {
                        Image(systemName: "photo")
                            .foregroundStyle(.tujiInk4)
                    } else {
                        ProgressView().tint(.tujiTeal)
                    }
                }
                .pipeline(.shared)
            }
            .frame(height: 100)
            .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(item.word.word)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.tujiInk)
                if self.settings.current.showZh {
                    Text(item.word.chinese)
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk3)
                        .lineLimit(1)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tujiCard)
        }
        .clipShape(.rect(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.15), lineWidth: 1)
        )
    }
}
