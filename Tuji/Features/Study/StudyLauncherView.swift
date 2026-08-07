// Direct-entry launcher for the study flow. Replaces the old
// StudyLandingView ("今天要學什麼" intermediate page). Tapping 複習 /
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

    /// The queue source. Injected rather than reached for, so the four branches
    /// below — warm cache, live fetch, empty, throw — can be driven by a test.
    var queues: StudyQueueProviding = StudyQueueStore.shared

    @State private var pushQueue: QueuePush?
    @State private var queueFailure: QueueFailure?

    /// Why the launcher could not start a session.
    ///
    /// An empty queue used to be signalled with an `NSError` carrying a Chinese
    /// literal in `NSLocalizedDescriptionKey`. `localizedDescription` performs no
    /// catalogue lookup, so that literal shipped verbatim to every user — while
    /// the same string sat in `Localizable.xcstrings` fully translated, one
    /// mechanism away and unreachable. A transport error still has to render its
    /// own (already-localised) description, so the two cases are separate.
    enum QueueFailure {
        /// Nothing is due. Not an error — a state the copy can speak to.
        case empty
        /// The fetch failed. Carries the URLSession/API description.
        case transport(String)

        var message: LocalizedStringKey {
            switch self {
            case .empty: "目前沒有可以練習的字"
            case let .transport(detail): "\(detail)"
            }
        }
    }

    /// Latched once a flow has been pushed. The launcher is single-shot: when
    /// the flow pops back (✕ or 回首頁 on the summary), re-running loadQueue
    /// would fetch a fresh queue and immediately re-push the flow — the user
    /// could never get home while words remained due.
    @State private var hasLaunched = false

    private let log = Logger(subsystem: "app.tuji.ios", category: "study-launcher")

    var body: some View {
        ZStack {
            Color.tujiPaper.ignoresSafeArea()
            VStack(spacing: Space.s3) {
                TujiPageLoading()
                Text("載入練習中…")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk2)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { self.studyFocus.enter() }
        .onDisappear { self.studyFocus.exit() }
        .task {
            // Re-appear after the flow popped back: the launcher's job is
            // done, so head straight back to the caller. This also backstops
            // the onChange dismiss below when the stack swallows it mid
            // pop-transition.
            if self.hasLaunched {
                self.dismiss()
                return
            }
            // Both stores are cheap if already warm (store-level TTLs handle
            // it). settings.loadIfNeeded fixes the silent-default-10 bug the
            // old StudyLandingVM never noticed.
            await self.settings.loadIfNeeded()
            await self.studyStats.loadIfStale()
            await self.loadQueue()
        }
        .tujiPrompt(
            isPresented: Binding(
                get: { self.queueFailure != nil },
                set: { if !$0 { self.queueFailure = nil } }
            ),
            style: .error,
            title: "載入失敗",
            message: self.queueFailure?.message ?? "",
            primary: TujiPromptAction("再試一次") {
                self.queueFailure = nil
                Task { await self.loadQueue() }
            },
            secondary: TujiPromptAction("稍後再說", role: .cancel) {
                self.queueFailure = nil
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
            let queue: [StudyQueueItem] = if let cached = self.queues.take(mode: self.mode) {
                cached
            } else {
                try await self.queues.fetch(mode: self.mode)
            }
            if queue.isEmpty {
                self.queueFailure = .empty
                return
            }
            self.hasLaunched = true
            self.pushQueue = QueuePush(mode: self.mode, queue: queue)
        } catch {
            self.log
                .error("queue load failed: \(error.localizedDescription, privacy: .public)")
            self.queueFailure = .transport(error.localizedDescription)
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
