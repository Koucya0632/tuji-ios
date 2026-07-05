// Completion celebration shown after Step 3 wraps. Lists the words
// learned this session and a 完成 CTA back to the previous screen.

import Nuke
import NukeUI
import SwiftUI

struct NewDoneView: View {
    let coord: NewFlowCoordinator
    let queue: [StudyQueueItem]
    let onFinish: () -> Void

    @Environment(MasteryStore.self) private var mastery
    @Environment(StudyStatsStore.self) private var studyStats
    @Environment(ProgressStore.self) private var progress

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
        // Learning new words writes mastery + creates user_cards + study_logs
        // (the deferred recognize POSTs fired as each word cleared Spell).
        // Reload — not just invalidate — every store the home surfaces read:
        // Today stays mounted under this push, so its .task won't re-run on
        // pop, and an invalidated-but-unreloaded store leaves 今日目標 0/10 and
        // the streak flame at 0 right after the session (until a tab swap).
        .task {
            // The recognize POSTs are optimistic, so wait for them to land (cap
            // at 2s) before reloading — otherwise the reload races the write
            // and the just-learned words show stale on the 圖鑑/詳情.
            await self.coord.drainPendingWrites(within: .seconds(2))
            self.mastery.invalidate()
            self.studyStats.invalidate()
            self.progress.invalidate()
            // Drop any prefetched queue — the cards just learned changed the
            // SRS state, so the next 復習 / 學新字 must re-fetch.
            StudyQueueStore.shared.invalidate()
            async let masteryReload: Void = self.mastery.reload()
            async let statsReload: Void = self.studyStats.reload()
            async let progressReload: Void = self.progress.reload()
            _ = await (masteryReload, statsReload, progressReload)
            // The last word's write starts moments before this task, so it's
            // the one most likely to miss the window (it may also be retrying).
            // Wait it out and reload once more so no word is left 未學.
            if self.coord.hasPendingWrites {
                await self.coord.drainPendingWrites(within: .seconds(15))
                self.mastery.invalidate()
                self.studyStats.invalidate()
                self.progress.invalidate()
                async let mastery2: Void = self.mastery.reload()
                async let stats2: Void = self.studyStats.reload()
                async let progress2: Void = self.progress.reload()
                _ = await (mastery2, stats2, progress2)
            }
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
                Rectangle().fill(.tujiBg)
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
                    .font(.system(size: 14, weight: .semibold))
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
