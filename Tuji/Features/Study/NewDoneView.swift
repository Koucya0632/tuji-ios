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
            VStack(spacing: Space.s4) {
                self.hero
                UnsyncedAnswersNotice(unsyncedCount: self.coord.parkedCount)
                StudyWordGrid(items: self.queue, mistakeCounts: self.coord.mistakeCounts)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s5)
        }
        // Learning new words writes mastery + creates user_cards + study_logs
        // (the deferred recognize POSTs fired as each word cleared Spell).
        // Reload — not just invalidate — every store the home surfaces read:
        // Today stays mounted under this push, so its .task won't re-run on
        // pop, and an invalidated-but-unreloaded store leaves 今日目標 0/10 and
        // the streak flame at 0 right after the session (until a tab swap).
        .task {
            await SessionRefresh(
                stores: [self.mastery, self.studyStats, self.progress],
                invalidateQueue: { StudyQueueStore.shared.invalidate() }
            ).run(draining: self.coord)
        }
        .safeAreaInset(edge: .bottom) {
            BBtn(
                title: "完成",
                bg: .tujiEye,
                fg: .tujiInk,
                fullWidth: true,
                icon: "checkmark",
                action: self.onFinish
            )
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s3)
        }
    }

    private var hero: some View {
        MascotCelebrationCard(
            title: "這節學了 \(self.queue.count) 個新字",
            accent: .tujiTeal
        ) {
            Text("它們已加入你的圖鑑")
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk3)
        }
        .padding(.top, Space.s5)
    }
}

/// Shown on both completion screens (new-word and review) when some SRS
/// ratings couldn't be sent and were parked in the durable outbox (offline /
/// server down). They replay automatically on the next launch/foreground, so
/// this is reassurance, not an error. Hidden when `count` is 0.
struct UnsyncedAnswersNotice: View {
    let unsyncedCount: Int

    var body: some View {
        if self.unsyncedCount > 0 {
            HStack(spacing: Space.s2) {
                Image(systemName: "icloud.slash")
                    .foregroundStyle(.tujiAlert)
                Text("有 \(self.unsyncedCount) 筆評分還沒送出，已排入待同步，連上網路後會自動補送。")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Space.s3)
            .background(.tujiAlert.opacity(0.12), in: .rect(cornerRadius: Radius.r0))
        }
    }
}

/// Two-column word grid shown on the study-complete screens (new-word and
/// review), so both celebrate the session's words with the same tile style.
struct StudyWordGrid: View {
    let items: [StudyQueueItem]
    /// Session mistakes by word id; words with retries get a 答錯 badge so
    /// the recap points at what to watch. Empty (the default) shows none.
    var mistakeCounts: [String: Int] = [:]

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
                Rectangle().fill(.tujiPaper)
                LazyImage(url: item.word.imageURL) { state in
                    if let image = state.image {
                        image.resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(Space.s2)
                    } else if state.error != nil {
                        Image(systemName: "photo")
                            .foregroundStyle(.tujiInk3)
                    } else {
                        ProgressView().tint(.tujiTeal)
                    }
                }
                .pipeline(.shared)
            }
            .frame(height: 100)
            .clipped()
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.word.word)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tujiInk)
                    Spacer(minLength: Space.s1)
                    if let wrongs = self.mistakeCounts[item.word.id], wrongs > 0 {
                        Text("答錯 \(wrongs) 次")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tujiAlert)
                            .lineLimit(1)
                    }
                }
                if self.settings.current.showZh {
                    Text(item.word.chinese)
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                        .lineLimit(1)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tujiPaper)
        }
        .clipShape(.rect(cornerRadius: Radius.r0))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.r0)
                .stroke(.tujiRule.opacity(0.15), lineWidth: 1)
        )
    }
}
