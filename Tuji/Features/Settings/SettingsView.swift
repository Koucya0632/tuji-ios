// Settings (§III.N). Every change applies immediately — controls write
// straight to SettingsStore.current, which auto-persists via POST
// /api/users/settings (debounced). No save button, no discard step.
// v1 ships the 學習 / 顯示 / 帳號 sections; 提醒 / 字體大小 / 深色模式
// come online when the matching backend infra is ready.

import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(LocalCache.self) private var cache
    @Environment(ProgressStore.self) private var progress
    @Environment(StudyStatsStore.self) private var studyStats
    private let users: UserRepository = LiveUserRepository.shared

    @State private var showSignOutConfirm = false
    @State private var showDeleteFirst = false
    @State private var showDeleteSecond = false
    @State private var deleting = false
    @State private var deleteError: Error?
    // 清除學習進度 (moved here from the Progress tab so a destructive,
    // account-wide wipe isn't one tap from the stats screen).
    @State private var progressVM = ProgressVM()
    @State private var showClearConfirm = false
    @State private var showClearSuccess = false

    /// Guests have no server account, so the 帳號 section (edit profile /
    /// sign out) and the clear-progress / delete-account section — both of
    /// which act on a server record — don't apply and are hidden.
    private var isGuest: Bool {
        if case .signedIn = self.auth.state { return false }
        return true
    }

    var body: some View {
        self.list
            .background(.tujiBg)
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .task { await self.store.loadIfNeeded() }
            .tujiPrompt(
                isPresented: self.$showSignOutConfirm,
                style: .confirmation,
                title: "要登出 Tuji 嗎？",
                message: "收藏與設定會保留在伺服器。",
                primary: TujiPromptAction("登出") {
                    Task { await self.auth.signOut() }
                },
                secondary: TujiPromptAction("取消", role: .cancel) {}
            )
            .tujiPrompt(
                isPresented: self.$showDeleteFirst,
                style: .destructive,
                title: "刪除你的帳號？",
                message: "此操作無法復原。",
                detail: "收藏、學習紀錄、設定與個人資料都會永久刪除。",
                primary: TujiPromptAction("繼續", role: .destructive) {
                    self.showDeleteSecond = true
                },
                secondary: TujiPromptAction("取消", role: .cancel) {}
            )
            .tujiPrompt(
                isPresented: self.$showDeleteSecond,
                style: .destructive,
                title: "最後一次確認",
                message: "確定要永久刪除帳號嗎？",
                detail: "刪除後將立即登出，所有資料都無法恢復。",
                primary: TujiPromptAction("永久刪除", role: .destructive) {
                    Task { await self.deleteAccount() }
                },
                secondary: TujiPromptAction("取消", role: .cancel) {}
            )
            .tujiPrompt(
                isPresented: Binding(
                    get: { self.deleteError != nil },
                    set: { if !$0 { self.deleteError = nil } }
                ),
                style: .error,
                title: "刪除失敗",
                message: "\(self.deleteError?.localizedDescription ?? "")",
                primary: TujiPromptAction("知道了") {
                    self.deleteError = nil
                }
            )
            .tujiPrompt(
                isPresented: self.$showClearConfirm,
                style: .destructive,
                title: "清除所有學習進度？",
                message: "此操作無法復原。",
                detail: "將刪除掌握度、連續天數、SRS 排程與答題紀錄；收藏與設定不受影響。",
                primary: TujiPromptAction("確認清除", role: .destructive) {
                    Task {
                        await self.progressVM.clearProgress(
                            cache: self.cache,
                            progress: self.progress,
                            studyStats: self.studyStats
                        )
                        if self.progressVM.clearError == nil {
                            self.showClearSuccess = true
                        }
                    }
                },
                secondary: TujiPromptAction("取消", role: .cancel) {}
            )
            .tujiPrompt(
                isPresented: Binding(
                    get: { self.progressVM.clearError != nil },
                    set: { if !$0 { self.progressVM.clearError = nil } }
                ),
                style: .error,
                title: "清除失敗",
                message: "\(self.progressVM.clearError?.localizedDescription ?? tujiLocalized("請稍後再試一次。"))",
                primary: TujiPromptAction("再試一次") {
                    self.showClearConfirm = true
                },
                secondary: TujiPromptAction("稍後再說", role: .cancel) {}
            )
            .tujiPrompt(
                isPresented: self.$showClearSuccess,
                style: .success,
                title: "學習進度已清除",
                message: "可以重新開始建立你的圖鑑。",
                primary: TujiPromptAction("知道了") {}
            )
    }

    // MARK: - List

    private var list: some View {
        List {
            Section("學習") {
                NavigationLink {
                    LearningDirectionPickerView()
                } label: {
                    self.row(
                        label: "學習語言",
                        value: self.store.current.learningDirection.shortTitle,
                        subtitle: "英文與日文的學習進度會分開保留"
                    )
                }
                NavigationLink {
                    DailyGoalPickerView()
                } label: {
                    self.row(
                        label: "每日目標題數",
                        value: tujiLocalized("\(self.store.current.dailyGoal) 題"),
                        subtitle: "每天想新學的題數，複習多時會自動調降"
                    )
                }
                NavigationLink {
                    StudyCategoriesPickerView()
                } label: {
                    self.row(
                        label: "學習主題",
                        value: self.studyCategoriesLabel,
                        subtitle: "學新字與主題進度只涵蓋你選的主題"
                    )
                }
                Toggle("中文釋義", isOn: self.store.binding(\.showZh))
                    .tint(.tujiTeal)
            }
            Section("顯示") {
                NavigationLink {
                    LangPickerView()
                } label: {
                    self.row(label: "語言", value: self.langLabel)
                }
                if self.store.current.learningDirection == .zhEn {
                    NavigationLink {
                        AccentPickerView()
                    } label: {
                        self.row(label: "發音口音", value: self.accentLabel)
                    }
                }
            }
            if !self.isGuest {
                Section("帳號") {
                    NavigationLink {
                        EditProfileView()
                    } label: {
                        self.row(label: "編輯個人資料", value: nil)
                    }
                    Button(role: .destructive) {
                        self.showSignOutConfirm = true
                    } label: {
                        Text("登出")
                            .foregroundStyle(.tujiCoral)
                    }
                }
                Section {
                    Button(role: .destructive) {
                        self.showClearConfirm = true
                    } label: {
                        HStack {
                            if self.progressVM.clearing {
                                ProgressView().tint(.tujiCoral)
                            }
                            Text(self.progressVM.clearing ? LocalizedStringKey("清除中…") : LocalizedStringKey("清除學習進度"))
                                .foregroundStyle(.tujiCoral)
                        }
                    }
                    .disabled(self.progressVM.clearing)
                    Button(role: .destructive) {
                        self.showDeleteFirst = true
                    } label: {
                        HStack {
                            if self.deleting {
                                ProgressView().tint(.tujiCoral)
                            }
                            Text(self.deleting ? LocalizedStringKey("刪除中…") : LocalizedStringKey("刪除帳號"))
                                .foregroundStyle(.tujiCoral)
                        }
                    }
                    .disabled(self.deleting)
                } footer: {
                    Text("清除學習進度會刪除掌握度與答題紀錄，但保留收藏、設定與自制圖鑑。")
                }
            }
            Section {
                Text("Tuji v1.0.0 · 圖記")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk4)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.tujiBg)
    }

    private func row(label: LocalizedStringKey, value: String?, subtitle: LocalizedStringKey? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .foregroundStyle(.tujiInk)
                if let subtitle {
                    Text(subtitle)
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk4)
                }
            }
            Spacer()
            if let value {
                Text(value)
                    .foregroundStyle(.tujiInk3)
            }
        }
    }

    private var accentLabel: String {
        switch self.store.current.accent {
        case "uk": tujiLocalized("英式")
        case "us": tujiLocalized("美式")
        default: self.store.current.accent.uppercased()
        }
    }

    private var studyCategoriesLabel: String {
        let n = self.store.current.studyCategories.count
        return n == 0 ? tujiLocalized("全部") : tujiLocalized("\(n) 個主題")
    }

    /// The language's own name (never localized); unknown codes read as 繁中
    /// via UILanguage's fallback.
    private var langLabel: String {
        self.store.current.uiLanguage.nativeName
    }

    // MARK: - Account actions

    private func deleteAccount() async {
        self.deleting = true
        self.deleteError = nil
        defer { self.deleting = false }
        do {
            try await self.users.deleteAccount()
            await self.auth.signOut()
        } catch {
            self.deleteError = error
        }
    }
}

private struct LearningDirectionPickerView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(OnboardingState.self) private var onboarding
    @Environment(WordsStore.self) private var words
    @Environment(CategoriesStore.self) private var categories
    @Environment(ProgressStore.self) private var progress
    @Environment(MasteryStore.self) private var mastery
    @Environment(StudyStatsStore.self) private var studyStats
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(LearningDirection.allCases, id: \.rawValue) { direction in
                    Button {
                        self.select(direction)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(direction.title)
                                    .foregroundStyle(.tujiInk)
                                Text(direction == .zhJa ? "日文詞條、假名與日文發音" : "英文詞條與美式／英式發音")
                                    .font(.tujiCaption)
                                    .foregroundStyle(.tujiInk3)
                            }
                            Spacer()
                            if self.settings.current.learningDirection == direction {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tujiTeal)
                            }
                        }
                    }
                }
            } footer: {
                Text("切換後會重新載入詞庫與進度，不會刪除另一種語言的學習紀錄。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(.tujiBg)
        .navigationTitle("學習語言")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func select(_ direction: LearningDirection) {
        guard direction != self.settings.current.learningDirection else {
            self.dismiss()
            return
        }
        self.onboarding.learningDirection = direction
        let shouldPersist = if case .signedIn = self.auth.state {
            true
        } else {
            false
        }
        self.settings.setLearningDirection(direction, persist: shouldPersist)
        self.words.invalidate()
        self.categories.invalidate()
        self.progress.invalidate()
        self.mastery.invalidate()
        self.studyStats.invalidate()
        self.dismiss()
        Task {
            async let wordsLoad: Void = self.words.reload()
            async let categoriesLoad: Void = self.categories.reload()
            async let progressLoad: Void = self.progress.reload()
            async let masteryLoad: Void = self.mastery.reload()
            async let statsLoad: Void = self.studyStats.reload()
            _ = await (wordsLoad, categoriesLoad, progressLoad, masteryLoad, statsLoad)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(SettingsStore.shared)
            .environment(AuthService.shared)
    }
}
