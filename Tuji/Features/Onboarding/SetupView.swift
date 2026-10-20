// Step 3 of the run-in: the daily goal, shown once after the user's first
// sign-in.
//
// Themes are no longer asked here. Setup still writes them — the server needs
// at least one — but seeds them from `SetupChoices` without a question: the
// beginner set for a new account, the account's own for a returning one. A
// grid of twenty themes was the longest decision in the run-in, made before
// the user had seen a single card. 設定 › 學習主題 changes them later.
//
// Saves to /api/users/settings via APIClient and marks the per-user
// setupDone flag in OnboardingState; RootView then advances to MainTabs.
//
// The picker reads the real category list from CategoriesStore so the
// values written into UserSettings.studyCategories are canonical IDs
// (kitchen / bathroom / office / …) — the backend's
// normalizeStudyCategories filter is lowercase-kebab only, so writing
// display names like "廚房" used to be silently dropped.

import SwiftUI

struct SetupView: View {
    let userId: UUID
    let onDone: @MainActor () async -> Void

    @Environment(OnboardingState.self) private var onboarding
    @Environment(CategoriesStore.self) private var categories
    @Environment(AuthService.self) private var auth
    @Environment(SettingsStore.self) private var settingsStore
    init(userId: UUID, onDone: @escaping @MainActor () async -> Void) {
        self.userId = userId
        self.onDone = onDone
    }

    @State private var topicIds: Set<String> = []
    @State private var dailyGoal: Int = 10
    @State private var saving = false
    @State private var error: String?
    @State private var showReSignIn: Bool = false
    @State private var initializedDefaults = false

    var body: some View {
        VStack(spacing: 0) {
            OnboardingStepBar(step: .goal)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    MascotSpeechBubble(pose: .think, text: "最後一題！")
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("每天想學幾個字？")
                            .font(.tujiH1)
                            .foregroundStyle(.tujiInk)
                        Text("先從一個做得到的量開始，之後可以在設定裡調整。")
                            .font(.tujiBodySm)
                            .foregroundStyle(.tujiInk3)
                    }

                    VStack(spacing: Space.s2) {
                        ForEach(Self.goals, id: \.count) { goal in
                            OnboardingChoice(
                                title: Text("\(goal.count) 題"),
                                detail: Text(goal.detail),
                                selected: self.dailyGoal == goal.count,
                                action: { self.dailyGoal = goal.count }
                            ) {
                                if self.dailyGoal == goal.count {
                                    Image(systemName: "checkmark")
                                        .font(.tujiIcon(20, weight: .bold))
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                    }

                    if let error {
                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text(error)
                                .font(.tujiLabel)
                                .foregroundStyle(.tujiAlert)
                            if showReSignIn {
                                Button {
                                    Task { await auth.signOut() }
                                } label: {
                                    Text("重新登入")
                                        .font(.tujiBodySm(.strong))
                                        .foregroundStyle(.tujiBrandSecondary)
                                        .padding(.vertical, Space.s2)
                                        .padding(.horizontal, Space.s3)
                                        .background(
                                            Color.tujiBrandPrimary.opacity(0.18),
                                            in: .rect(cornerRadius: Radius.r0)
                                        )
                                }
                                .buttonStyle(.plain)
                            } else if !initializedDefaults {
                                Button("重試") {
                                    Task { await self.loadDefaults() }
                                }
                                .font(.tujiBodySm(.strong))
                                .foregroundStyle(.tujiBrandSecondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s5)
            }

            BBtn(
                // Not 「開始使用」: that is the tour's closing card, the next
                // thing this user sees.
                title: saving ? "儲存中..." : (initializedDefaults ? "開始學習" : "準備中..."),
                bg: .tujiBrandPrimary,
                fg: .tujiInk,
                fullWidth: true,
                action: save
            )
            .disabled(saving || topicIds.isEmpty)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s4)
        }
        .background(.tujiPaper)
        .task { await self.loadDefaults() }
        .onChange(of: categories.categories) { _, _ in
            seedDefaults()
        }
    }

    // MARK: - Bits

    private struct Goal {
        let count: Int
        let detail: LocalizedStringKey
    }

    private static let goals = [
        Goal(count: 5, detail: "輕鬆開始，零碎時間就夠"),
        Goal(count: 10, detail: "推薦，每天穩穩前進"),
        Goal(count: 20, detail: "認真衝刺，進步最快")
    ]

    /// Settings too: a returning account on a new device starts from its own
    /// themes and goal, and those are on the account, not here.
    private func loadDefaults() async {
        error = nil
        async let categoriesLoad: Void = categories.loadIfNeeded()
        async let settingsLoad: Void = settingsStore.loadIfNeeded()
        _ = await (categoriesLoad, settingsLoad)
        seedDefaults()
        if !initializedDefaults, categories.lastError != nil {
            error = tujiLocalized("載入失敗，請檢查網路後再試一次。")
        }
    }

    /// Sets the initial selection once categories have loaded — from the
    /// account when it has been set up before, otherwise from the beginner
    /// themes. See `SetupChoices`.
    private func seedDefaults() {
        guard !initializedDefaults, !categories.categories.isEmpty else { return }
        let seed = SetupChoices.seed(
            account: settingsStore.loadedForCurrentAccount ? settingsStore.current : nil,
            catalogIds: Set(categories.categories.map(\.id)),
            firstThemesFallback: categories.categories.map(\.id)
        )
        topicIds = seed.topicIds
        dailyGoal = seed.dailyGoal
        initializedDefaults = true
    }

    private func save() {
        Task {
            saving = true
            error = nil
            defer { saving = false }

            do {
                // Onto the account's own settings, through the store — see
                // `SettingsStore.completeSetup`.
                try await settingsStore.completeSetup(topicIds: topicIds, dailyGoal: dailyGoal)
                // The main shell needs the catalog for this newly persisted
                // direction. Keep Setup mounted (and its existing saving
                // state visible) until that attempt completes, rather than
                // showing the launch brand for a second time.
                await onDone()
                // Flips RootView to MainTabsView, which lands on 主頁 and lets
                // the first-run tour take it from here. Setup used to park a
                // study deep link and push straight into a session — that shut
                // the tour out entirely, since startTourIfNeeded() bails while
                // StudyLauncherView holds studyFocus.
                onboarding.markSetupDone(for: userId)
            } catch APIError.unauthorized {
                error = tujiLocalized("後端不認這次登入。可能要重新登入一次。")
                showReSignIn = true
            } catch let APIError.server(status: status, body: body) {
                error = tujiLocalized("儲存失敗（\(status)）：\(body ?? "")")
                showReSignIn = false
            } catch {
                self.error = tujiUserMessage(for: error)
                showReSignIn = false
            }
        }
    }
}

#Preview {
    SetupView(userId: UUID(), onDone: {})
        .environment(OnboardingState.shared)
        .environment(CategoriesStore.shared)
}
