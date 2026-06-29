// Direct-entry launcher for the study flow. Replaces the old
// StudyLandingView ("今天要學什麼" intermediate page). Tapping 復習 /
// 學新字 on Today (or via tuji://study?mode= deeplink) lands here
// briefly while we fetch /api/study/queue, then auto-pushes into
// ReviewFlowView or NewFlowView with the resulting queue.
//
// Empty queue or transport error → alert + dismiss back to caller.

import OSLog
import SwiftUI

struct StudyLauncherView: View {
    let mode: StudyMode

    @Environment(StudyStatsStore.self) private var studyStats
    @Environment(SettingsStore.self) private var settings
    @Environment(StudyFocus.self) private var studyFocus
    @Environment(\.dismiss) private var dismiss

    @State private var pushQueue: QueuePush?
    @State private var queueError: Error?

    private let log = Logger(subsystem: "app.tuji.ios", category: "study-launcher")

    var body: some View {
        ZStack {
            Color.tujiBg.ignoresSafeArea()
            VStack(spacing: Space.s3) {
                ProgressView().tint(.tujiTeal)
                Text("載入練習中…")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk2)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { self.studyFocus.enter() }
        .onDisappear { self.studyFocus.exit() }
        .task {
            // Both stores are cheap if already warm (store-level TTLs handle
            // it). settings.loadIfNeeded fixes the silent-default-10 bug the
            // old StudyLandingVM never noticed.
            await self.settings.loadIfNeeded()
            await self.studyStats.loadIfStale()
            await self.loadQueue()
        }
        .tujiPrompt(
            isPresented: Binding(
                get: { self.queueError != nil },
                set: { if !$0 { self.queueError = nil } }
            ),
            style: .error,
            title: "載入失敗",
            message: "\(self.queueError?.localizedDescription ?? "")",
            primary: TujiPromptAction("再試一次") {
                self.queueError = nil
                Task { await self.loadQueue() }
            },
            secondary: TujiPromptAction("稍後再說", role: .cancel) {
                self.queueError = nil
                self.dismiss()
            }
        )
        .navigationDestination(item: self.$pushQueue) { wrap in
            switch wrap.mode {
            case .new:
                NewFlowView(queue: wrap.queue)
            case .review:
                ReviewFlowView(queue: wrap.queue)
            }
        }
        // The launcher exists only to fetch a queue and forward to the
        // flow. When the user dismisses the flow (X → 離開練習), SwiftUI
        // resets pushQueue to nil — but the launcher would otherwise sit
        // on its loading spinner forever. Pop it too so the user lands
        // back on Today.
        .onChange(of: self.pushQueue) { old, new in
            if old != nil, new == nil { self.dismiss() }
        }
    }

    private func loadQueue() async {
        let due = self.studyStats.stats?.due ?? 0
        let goal = self.settings.current.dailyGoal
        let limit: Int
        let newCount: Int
        // New cards are drawn from the user's selected themes; review spans
        // every studied word regardless of theme, so it sends no filter.
        let categories: [String]
        switch self.mode {
        case .new:
            let n = StudyQuotas.computeNewLimit(goal: goal, due: due)
            limit = n
            newCount = n
            categories = self.settings.current.studyCategories
        case .review:
            limit = min(due, 30)
            newCount = 0
            categories = []
        }
        do {
            let resp: StudyQueueResponse = try await APIClient.shared.get(
                .studyQueue(
                    mode: self.mode.asPath,
                    limit: max(1, limit),
                    new: newCount,
                    categories: categories
                )
            )
            // A custom 自制圖鑑 item can carry more than one card (image_recall +
            // flashcard), but the unified flow studies a word once and the queue
            // is keyed by word.id (StudyQueueItem.id). Collapse to one item per
            // word so the same word can't surface twice in a session — keep the
            // first, since the server orders in-progress reviews ahead of new
            // cards.
            var seenWordIds = Set<String>()
            let queue = resp.queue.filter { seenWordIds.insert($0.word.id).inserted }
            if queue.isEmpty {
                self.queueError = NSError(
                    domain: "tuji.study",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "目前沒有可以練習的字"]
                )
                return
            }
            self.pushQueue = QueuePush(mode: self.mode, queue: queue)
        } catch {
            self.log
                .error("queue load failed: \(error.localizedDescription, privacy: .public)")
            self.queueError = error
        }
    }

    private struct QueuePush: Hashable, Identifiable {
        let mode: StudyMode
        let queue: [StudyQueueItem]
        var id: String {
            "\(self.mode.asPath)-\(self.queue.map(\.id).joined())"
        }
    }
}

#Preview {
    NavigationStack {
        StudyLauncherView(mode: .new)
            .environment(StudyStatsStore.shared)
            .environment(SettingsStore.shared)
            .environment(StudyFocus.shared)
    }
}
