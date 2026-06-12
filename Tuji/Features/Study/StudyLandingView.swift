// Study landing (§III.O).
//
// Entry surface for the daily study session. Fetches /study/stats and
// shows: due / today-new-quota / learned / completion tiles, plus two
// big BBtns into the matching flow. `mode` parameter biases which CTA
// gets the prominent styling, but both are always shown.
//
// computeNewLimit() mirrors lib/scheduling.ts on the backend so the
// quota shown here matches what the queue will actually serve.

import OSLog
import Observation
import SwiftUI

enum StudyMode: Hashable {
    case new
    case review

    /// Optional category filter passed through from CategoryView entry
    /// points (W3 §III.G "開始這個主題的練習"). v1 not surfaced yet.
    var asPath: String {
        switch self {
        case .new: "new"
        case .review: "review"
        }
    }
}

@MainActor
@Observable
final class StudyLandingVM {
    var stats: StudyStats?
    var settings: UserSettings = .default
    var loading: Bool = true
    var error: Error?

    private let log = Logger(subsystem: "app.tuji.ios", category: "study-landing")

    func load() async {
        self.loading = true
        self.error = nil
        defer { self.loading = false }
        do {
            async let stats: StudyStatsResponse = APIClient.shared.get(.studyStats)
            async let me: UserMeResponse = APIClient.shared.get(.usersMe)
            let (s, m) = try await (stats, me)
            self.stats = s.stats
            // /api/users/me returns the full bundle including settings; for
            // v1 fall back to defaults if backend bundle doesn't carry them.
            _ = m
            self.log.info("loaded due=\(s.stats.due, privacy: .public) new=\(s.stats.new, privacy: .public)")
        } catch {
            self.error = error
            self.log.error("study landing load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var dailyGoal: Int {
        self.settings.dailyGoal
    }

    var newLimitToday: Int {
        Self.computeNewLimit(goal: self.dailyGoal, due: self.stats?.due ?? 0)
    }

    /// Mirrors lib/scheduling.ts::computeNewLimit. As backlog grows, new
    /// card quota tapers off so users dig out of their review pile first.
    static func computeNewLimit(goal: Int, due: Int) -> Int {
        switch due {
        case ...20: goal
        case 21...50: Int(Double(goal) * 0.75)
        case 51...100: Int(Double(goal) * 0.5)
        default: 0
        }
    }

    var newDisabled: Bool {
        self.newLimitToday == 0 || (self.stats?.todayNew ?? 0) >= self.newLimitToday
    }

    var reviewDisabled: Bool {
        (self.stats?.due ?? 0) == 0
    }

    var backlogWarning: Bool {
        (self.stats?.due ?? 0) > 100
    }
}

struct StudyLandingView: View {
    let initialMode: StudyMode
    @State private var vm = StudyLandingVM()
    @State private var showBlockedAlert = false
    @Environment(LocalCache.self) private var cache
    @Environment(WordsStore.self) private var words

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s6) {
                self.hero
                self.statGrid
                self.actions
                if self.vm.backlogWarning {
                    self.backlogCard
                }
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .background(.tujiBg)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await self.vm.load() }
        .task { await self.vm.load() }
        .alert("複習太多了", isPresented: self.$showBlockedAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("先把到期的字消化一些，新字就會再開放。")
        }
    }

    // MARK: - Bits

    private var hero: some View {
        VStack(spacing: Space.s3) {
            Mascot(pose: .wave, size: 84)
            Text("今天要學什麼？")
                .font(.tujiH2)
                .foregroundStyle(.tujiInk)
            Text(self.subtitle)
                .font(.tujiBody)
                .foregroundStyle(.tujiInk3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s5)
    }

    private var subtitle: String {
        if let due = vm.stats?.due, due > 0 {
            return "有 \(due) 個字到期；今天還能新學 \(self.vm.newLimitToday) 個"
        }
        if let new = vm.stats?.new, new > 0 {
            return "今天可以挑 \(self.vm.newLimitToday) 個新字"
        }
        return "看看新字或溫故知新"
    }

    private var statGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Space.s3),
                GridItem(.flexible(), spacing: Space.s3)
            ],
            spacing: Space.s3
        ) {
            self.statTile(
                label: "到期複習",
                value: "\(self.vm.stats?.due ?? 0)",
                tint: .tujiTeal,
                icon: "arrow.clockwise"
            )
            self.statTile(
                label: "今日新學",
                value: "\(self.vm.stats?.todayNew ?? 0)/\(self.vm.newLimitToday)",
                tint: .tujiCoral,
                icon: "sparkles"
            )
            self.statTile(
                label: "已學會",
                value: "\(self.learnedCount)",
                tint: .tujiYellow,
                icon: "checkmark.seal.fill"
            )
            self.statTile(
                label: "圖鑑完成",
                value: "\(self.completionPercent)%",
                tint: .tujiInk,
                icon: "book.fill"
            )
        }
    }

    private func statTile(label: String, value: String, tint: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.tujiOverline)
                    .tracking(2)
                    .foregroundStyle(.tujiInk3)
            }
            Text(value)
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.tujiInk)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var actions: some View {
        let due = self.vm.stats?.due ?? 0
        let newQ = self.vm.newLimitToday
        VStack(spacing: Space.s3) {
            // Review button: highlighted when initialMode == .review
            BBtn(
                title: self.vm.reviewDisabled ? "沒有到期的字" : "復習 \(due) 個字",
                bg: self.initialMode == .review ? .tujiYellow : .tujiTealSoft,
                fg: self.initialMode == .review ? .tujiInk : .tujiTeal,
                fullWidth: true,
                icon: "arrow.clockwise",
                action: self.startReview
            )
            .disabled(self.vm.reviewDisabled)

            BBtn(
                title: self.vm.newDisabled ? "今日新字額度用完" : "學 \(newQ) 個新字",
                bg: self.initialMode == .new ? .tujiYellow : .tujiTealSoft,
                fg: self.initialMode == .new ? .tujiInk : .tujiTeal,
                fullWidth: true,
                icon: "sparkles",
                action: self.startNew
            )
            .disabled(self.vm.newDisabled && self.vm.newLimitToday == 0)
        }
    }

    private var backlogCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.tujiCoral)
            VStack(alignment: .leading, spacing: 4) {
                Text("複習堆太高了")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.tujiInk)
                Text("到期字超過 100，新字暫停發放，先消化一輪。")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiCoral.opacity(0.08), in: .rect(cornerRadius: Radius.lg))
    }

    private var learnedCount: Int {
        self.cache.learnedIds.count
    }

    private var completionPercent: Int {
        let total = self.words.words.count
        guard total > 0 else { return 0 }
        return Int((Double(self.learnedCount) / Double(total)) * 100)
    }

    private func startReview() {
        guard !self.vm.reviewDisabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // W4 Part 3: push ReviewFlowView(queue: ...)
    }

    private func startNew() {
        if self.vm.newLimitToday == 0 {
            self.showBlockedAlert = true
            return
        }
        guard !self.vm.newDisabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // W4 Part 2: push NewFlowView(queue: ...)
    }
}

#Preview {
    NavigationStack {
        StudyLandingView(initialMode: .new)
            .environment(LocalCache.shared)
            .environment(WordsStore.shared)
    }
}
