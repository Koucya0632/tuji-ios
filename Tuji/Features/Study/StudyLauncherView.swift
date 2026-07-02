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
        do {
            // Warm path: TodayView pre-fetched this queue in the background, so
            // take() returns instantly and the spinner only flashes for a frame.
            // Cache miss → live fetch (the old behaviour). Both share the param
            // computation + dedupe inside StudyQueueStore.
            let queue: [StudyQueueItem]
            if let cached = StudyQueueStore.shared.take(mode: self.mode) {
                queue = cached
            } else {
                queue = try await StudyQueueStore.shared.fetch(mode: self.mode)
            }
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
