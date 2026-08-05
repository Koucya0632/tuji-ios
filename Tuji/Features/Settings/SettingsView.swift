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
    @State private var showGoalPicker = false
    @State private var showLangPicker = false
    @State private var showAccentPicker = false
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
        VStack(spacing: 0) {
            TujiNavBar(leading: .back)
            self.list
        }
        .background(.tujiPaper)
        .tujiSheet(isPresented: self.$showGoalPicker, title: "每日目標題數") {
            TujiOptionSheet(
                options: SettingsOptions.dailyGoals.map {
                    .init($0, verbatim: tujiLocalized("\($0) 題"))
                },
                selection: self.store.current.dailyGoal,
                footer: "這個數字會用來算今日新字額度與目標達成度"
            ) { goal in
                self.store.update { $0.dailyGoal = goal }
            }
        }
        .tujiSheet(isPresented: self.$showLangPicker, title: "語言") {
            TujiOptionSheet(
                options: UILanguage.allCases.map { .init($0, verbatim: $0.nativeName) },
                selection: self.store.current.uiLanguage,
                footer: "變更立即生效。單字與例句維持中文內容，繁簡會跟隨此設定。"
            ) { lang in
                self.store.update { $0.uiLanguage = lang }
            }
        }
        .tujiSheet(isPresented: self.$showAccentPicker, title: "發音口音") {
            TujiOptionSheet(
                options: SettingsOptions.accents.map {
                    .init($0.code, title: $0.label, subtitle: $0.detail)
                },
                selection: self.store.current.accent,
                footer: "聽單字朗讀時用哪一種口音"
            ) { code in
                self.store.update { $0.accent = code }
            }
        }
        // Still set, still not drawn: VoiceOver reads it, the multitasking
        // window is named by it, and a pushed child's back button would use it.
        .navigationTitle("設定")
        .toolbar(.hidden, for: .navigationBar)
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
        ScrollView {
            VStack(spacing: 0) {
                TujiScreenTitle("設定")
                TujiSection(title: "學習") {
                    NavigationLink { LearningDirectionPickerView() } label: {
                        TujiRow(
                            "學習語言",
                            subtitle: "英文與日文的學習進度會分開保留",
                            value: self.store.current.learningDirection.shortTitle
                        )
                    }
                    .tujiRowStyle()
                    Button { self.showGoalPicker = true } label: {
                        TujiRow(
                            "每日目標題數",
                            subtitle: "每天想新學的題數，複習多時會自動調降",
                            value: tujiLocalized("\(self.store.current.dailyGoal) 題")
                        )
                    }
                    .tujiRowStyle()
                    NavigationLink { StudyCategoriesPickerView() } label: {
                        TujiRow(
                            "學習主題",
                            subtitle: "學新字與主題進度只涵蓋你選的主題",
                            value: self.studyCategoriesLabel
                        )
                    }
                    .tujiRowStyle()
                    TujiRow(
                        leading: { TujiRowLabel(label: "中文釋義") },
                        trailing: { TujiCheckbox(isOn: self.store.binding(\.showZh)) }
                    )
                }

                TujiSection(title: "顯示") {
                    Button { self.showLangPicker = true } label: {
                        TujiRow("語言", value: self.langLabel)
                    }
                    .tujiRowStyle()
                    if self.store.current.learningDirection == .zhEn {
                        Button { self.showAccentPicker = true } label: {
                            TujiRow("發音口音", value: self.accentLabel)
                        }
                        .tujiRowStyle()
                    }
                }

                if self.isGuest {
                    // Not an empty space where the account section would be: a
                    // guest is not a blocked user, they are an undecided one, so
                    // the gap becomes one statement and one way out.
                    TujiSection(
                        title: "帳號",
                        footer: "訪客的書籤只存在這台裝置上。建立帳號後會同步，並且可以開始學習。"
                    ) {
                        Button { self.auth.exitGuestMode() } label: {
                            TujiRow("建立帳號", showsArrow: false)
                        }
                        .tujiRowStyle()
                    }
                } else {
                    TujiSection(title: "帳號") {
                        NavigationLink { EditProfileView() } label: {
                            TujiRow("編輯個人資料")
                        }
                        .tujiRowStyle()
                        Button { self.showSignOutConfirm = true } label: {
                            TujiRow("登出", showsArrow: false, destructive: true)
                        }
                        .tujiRowStyle(destructive: true)
                    }

                    TujiSection(
                        footer: "清除學習進度會刪除掌握度與答題紀錄，但保留書籤、設定與自製圖鑑。"
                    ) {
                        Button { self.showClearConfirm = true } label: {
                            self.dangerRow(
                                title: self.progressVM.clearing ? "清除中…" : "清除學習進度",
                                busy: self.progressVM.clearing
                            )
                        }
                        .tujiRowStyle(destructive: true)
                        .disabled(self.progressVM.clearing)
                        Button { self.showDeleteFirst = true } label: {
                            self.dangerRow(
                                title: self.deleting ? "刪除中…" : "刪除帳號",
                                busy: self.deleting
                            )
                        }
                        .tujiRowStyle(destructive: true)
                        .disabled(self.deleting)
                    }
                }

                Text("Tuji v1.0.0 · 圖記")
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Space.s6)
                    .padding(.bottom, Space.s5)
            }
            .padding(.bottom, Space.s6)
        }
        .background(.tujiPaper)
    }

    /// A destructive row whose work is in flight. The inline bar replaces the
    /// spinner that used to sit beside the label.
    private func dangerRow(title: LocalizedStringKey, busy: Bool) -> some View {
        VStack(spacing: Space.s2) {
            TujiRow(title, showsArrow: false, destructive: true)
            if busy {
                TujiProgressBar(progress: nil, fill: .tujiAlert)
                    .padding(.horizontal, Space.s4)
                    .padding(.bottom, Space.s3)
            }
        }
    }

    private func row(label: LocalizedStringKey, value: String?, subtitle: LocalizedStringKey? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .foregroundStyle(.tujiInk)
                if let subtitle {
                    Text(subtitle)
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
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
        VStack(spacing: 0) {
            TujiNavBar(leading: .back)
            ScrollView {
                TujiScreenTitle("學習語言")
                TujiSection(
                    footer: "切換後會重新載入詞庫與進度，不會刪除另一種語言的學習紀錄。"
                ) {
                    ForEach(LearningDirection.allCases, id: \.rawValue) { direction in
                        Button {
                            self.select(direction)
                        } label: {
                            TujiRow(
                                leading: {
                                    TujiRowLabel(
                                        localized: direction.title,
                                        localizedSubtitle: direction == .zhJa
                                            ? tujiLocalized("日文詞條、假名與日文發音")
                                            : tujiLocalized("英文詞條與美式／英式發音")
                                    )
                                },
                                trailing: {
                                    TujiSelectionMark(
                                        selected: self.settings.current.learningDirection == direction
                                    )
                                }
                            )
                        }
                        .tujiRowStyle()
                    }
                }
            }
        }
        .background(.tujiPaper)
        .navigationTitle("學習語言")
        .toolbar(.hidden, for: .navigationBar)
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
