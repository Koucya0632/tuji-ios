// The account's first-run settings, written without a screen of questions.
//
// Setup used to ask for themes and a daily goal. Neither is asked any more:
// a new user goes from sign-in straight to 今天. But the account still needs
// them written — the server will not hand out new words with no theme — so
// this runs once after the first sign-in on a device, behind the brand
// surface, and seeds both from `SetupChoices`: the default 主題組合 and the
// default goal for a new account, the account's own for a returning one.
// 設定 changes either later.
//
// Saves to /api/users/settings via SettingsStore and marks the per-user
// setupDone flag in OnboardingState; RootView then advances to MainTabs.
//
// The ids come from CategoriesStore so the values written into
// UserSettings.studyCategories are canonical IDs (kitchen / bathroom /
// office / …) — the backend's normalizeStudyCategories filter is
// lowercase-kebab only, so writing display names like "廚房" used to be
// silently dropped.

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

    @State private var running = false
    @State private var error: String?
    @State private var showReSignIn: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // The same surface launch shows, so a sign-in that sets up
            // smoothly reads as one continuous load into 今天.
            SplashView()

            if let error {
                VStack(spacing: Space.s3) {
                    Text(error)
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiAlert)
                        .multilineTextAlignment(.center)
                    BBtn(
                        title: "重試",
                        bg: .tujiBrandPrimary,
                        fg: .tujiInk,
                        fullWidth: true,
                        action: { Task { await self.run() } }
                    )
                    .disabled(self.running)
                    if self.showReSignIn {
                        Button {
                            Task { await self.auth.signOut() }
                        } label: {
                            Text("重新登入")
                                .font(.tujiBodySm(.strong))
                                .foregroundStyle(.tujiInk3)
                        }
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s5)
            }
        }
        .task { await self.run() }
    }

    private func run() async {
        guard !self.running else { return }
        self.running = true
        self.error = nil
        defer { self.running = false }

        // Settings too: a returning account on a new device keeps its own
        // themes and goal, and those are on the account, not here.
        async let categoriesLoad: Void = self.categories.loadIfNeeded()
        async let settingsLoad: Void = self.settingsStore.loadIfNeeded()
        _ = await (categoriesLoad, settingsLoad)

        guard !self.categories.categories.isEmpty else {
            self.error = tujiLocalized("載入失敗，請檢查網路後再試一次。")
            self.showReSignIn = false
            return
        }
        let seed = SetupChoices.seed(
            account: self.settingsStore.loadedForCurrentAccount ? self.settingsStore.current : nil,
            catalogIds: Set(self.categories.categories.map(\.id)),
            presets: self.categories.presets,
            firstThemesFallback: self.categories.categories.map(\.id)
        )

        do {
            // Onto the account's own settings, through the store — see
            // `SettingsStore.completeSetup`.
            try await self.settingsStore.completeSetup(topicIds: seed.topicIds, dailyGoal: seed.dailyGoal)
            // The main shell needs the catalog for this newly persisted
            // direction. Stay on the brand surface until that attempt
            // completes rather than flashing stale UI.
            await self.onDone()
            // Flips RootView to MainTabsView, which lands on 今天 and lets the
            // first-run tour take it from here.
            self.onboarding.markSetupDone(for: self.userId)
        } catch APIError.unauthorized {
            self.error = tujiLocalized("後端不認這次登入。可能要重新登入一次。")
            self.showReSignIn = true
        } catch let APIError.server(status: status, body: body) {
            self.error = tujiLocalized("儲存失敗（\(status)）：\(body ?? "")")
            self.showReSignIn = false
        } catch {
            self.error = tujiUserMessage(for: error)
            self.showReSignIn = false
        }
    }
}

#Preview {
    SetupView(userId: UUID(), onDone: {})
        .environment(OnboardingState.shared)
        .environment(CategoriesStore.shared)
}
