// Per-user Setup picker shown once after the user's first sign-in.
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
    /// Injected rather than a hardcoded `.shared` stored property. `ReportFlow`
    /// names that shape as the defect it was carved out to fix — *no init seam,
    /// so no test could substitute it* — and it survived in eight more places.
    private let users: UserRepository

    init(
        userId: UUID,
        onDone: @escaping @MainActor () async -> Void,
        users: UserRepository = LiveUserRepository.shared
    ) {
        self.userId = userId
        self.onDone = onDone
        self.users = users
    }

    @State private var topicIds: Set<String> = []
    @State private var dailyGoal: Int = 10
    @State private var saving = false
    @State private var error: String?
    @State private var showReSignIn: Bool = false
    @State private var initializedDefaults = false

    private static let defaultTopicIds: [String] = StudyCategoryDefaults.beginnerCategoryIDs
    private let goals = [5, 10, 20]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("先幫你排一份\n學習節奏")
                        .font(.tujiH2)
                        .foregroundStyle(.tujiInk)
                        .padding(.top, Space.s4)
                        .padding(.horizontal, Space.s4)

                    section(title: "你對學習什麼主題有興趣？") {
                        if categories.categories.isEmpty {
                            HStack {
                                TujiProgressBar(progress: nil).frame(width: 56)
                                Text("載入主題中…")
                                    .font(.tujiLabel)
                                    .foregroundStyle(.tujiInk3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Space.s4)
                        } else {
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 3),
                                spacing: Space.s2
                            ) {
                                ForEach(categories.categories) { c in
                                    categoryTile(category: c, selected: topicIds.contains(c.id)) {
                                        if topicIds.contains(c.id) {
                                            topicIds.remove(c.id)
                                        } else {
                                            topicIds.insert(c.id)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    section(title: "每日目標") {
                        HStack(spacing: Space.s2) {
                            ForEach(goals, id: \.self) { g in
                                tile(label: "\(g) 題", selected: dailyGoal == g) {
                                    dailyGoal = g
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
                            }
                        }
                        .padding(.horizontal, Space.s4)
                    }
                }
                .padding(.bottom, Space.s4)
            }

            Divider().background(.tujiRule.opacity(0.2))

            BBtn(
                // Not 「開始使用」: that is already the last onboarding page's
                // button and the tour's closing card, and this is a third tap
                // in the same run-in.
                title: saving ? "儲存中..." : "完成設定",
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
        .task {
            await categories.loadIfNeeded()
            seedDefaults()
        }
        .onChange(of: categories.categories) { _, _ in
            seedDefaults()
        }
    }

    // MARK: - Bits

    private func section(title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title)
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
                .padding(.horizontal, Space.s4)
            content()
                .padding(.horizontal, Space.s4)
        }
    }

    private func tile(label: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.tujiBodySm(.strong))
                .foregroundStyle(.tujiInk2)
                .padding(.vertical, Space.s3)
                .frame(maxWidth: .infinity)
                .background(
                    selected ? Color.tujiCurrent.opacity(0.18) : .tujiPaper,
                    in: .rect(cornerRadius: Radius.r0)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.r0)
                        .stroke(
                            selected ? Color.tujiCurrent : .tujiRule,
                            lineWidth: selected ? 1.5 : 1
                        )
                )
        }
    }

    private func categoryTile(category: TujiCategory, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(category.nameZh)
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.vertical, Space.s4)
                .frame(maxWidth: .infinity)
                .background(
                    selected ? Color.tujiCurrent.opacity(0.18) : .tujiPaper,
                    in: .rect(cornerRadius: Radius.r0)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.r0)
                        .stroke(
                            selected ? Color.tujiCurrent : .tujiRule,
                            lineWidth: selected ? 1.5 : 1
                        )
                )
        }
    }

    /// Sets the initial selection once categories have loaded. Prefer the
    /// hand-picked beginner trio; fall back to the first three categories
    /// if any of those IDs don't exist in the dataset.
    private func seedDefaults() {
        guard !initializedDefaults, !categories.categories.isEmpty else { return }
        let allIds = Set(categories.categories.map(\.id))
        let preferred = Self.defaultTopicIds.filter { allIds.contains($0) }
        let atlasDefaults = StudyCategoryDefaults.atlasCategoryIDs.filter {
            allIds.contains($0)
        }
        if preferred.count == Self.defaultTopicIds.count {
            topicIds = Set(preferred).union(atlasDefaults)
        } else {
            topicIds = Set(categories.categories.prefix(3).map(\.id))
                .union(atlasDefaults)
        }
        initializedDefaults = true
    }

    private func save() {
        Task {
            saving = true
            error = nil
            defer { saving = false }

            let settings = UserSettings(
                dailyGoal: dailyGoal,
                accent: "us",
                showZh: true,
                studyCategories: topicIds.sorted(),
                studyDecks: [],
                learningDirection: onboarding.learningDirection ?? settingsStore.current.learningDirection,
                // The live value: device-detected on first run, or whatever
                // the user already picked in-app. Never hardcode — the server
                // clamps unknown codes, so what we send here sticks.
                uiLang: settingsStore.current.uiLang,
                fontSize: "md"
            )

            do {
                try await self.users.saveSettings(settings)
                // Seed the shared store too — the study-queue params and
                // Today's theme grid read SettingsStore.current, which would
                // otherwise stay at defaults until the next server load.
                settingsStore.adoptPersisted(settings)
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
