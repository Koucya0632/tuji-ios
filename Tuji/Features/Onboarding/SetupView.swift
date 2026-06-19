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
    let onDone: () -> Void

    @Environment(OnboardingState.self) private var onboarding
    @Environment(CategoriesStore.self) private var categories
    @Environment(AuthService.self) private var auth

    @State private var topicIds: Set<String> = []
    @State private var dailyGoal: Int = 10
    @State private var saving = false
    @State private var error: String?
    @State private var showReSignIn: Bool = false
    @State private var initializedDefaults = false

    private static let defaultTopicIds: [String] = ["kitchen", "bathroom", "living-room"]
    private let goals = [5, 10, 20]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s6) {
                    Text("先幫你排一份\n學習節奏")
                        .font(.tujiH2)
                        .foregroundStyle(.tujiInk)
                        .padding(.top, Space.s5)
                        .padding(.horizontal, Space.s6)

                    section(title: "你對學習什麼主題有興趣？") {
                        if categories.categories.isEmpty {
                            HStack {
                                ProgressView().tint(.tujiTeal)
                                Text("載入主題中…")
                                    .font(.tujiCaption)
                                    .foregroundStyle(.tujiInk3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Space.s5)
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
                                .font(.tujiCaption)
                                .foregroundStyle(.tujiCoral)
                            if showReSignIn {
                                Button {
                                    Task { await auth.signOut() }
                                } label: {
                                    Text("重新登入")
                                        .font(.system(size: 14, weight: .heavy))
                                        .foregroundStyle(.tujiTeal)
                                        .padding(.vertical, Space.s2)
                                        .padding(.horizontal, Space.s4)
                                        .background(.tujiTealSoft, in: .capsule)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Space.s6)
                    }
                }
                .padding(.bottom, Space.s5)
            }

            Divider().background(.tujiInk4.opacity(0.2))

            BBtn(
                title: saving ? "儲存中..." : "開始今天的 \(dailyGoal) 題",
                bg: .tujiTeal,
                fg: .white,
                fullWidth: true,
                action: save
            )
            .disabled(saving || topicIds.isEmpty)
            .padding(.horizontal, Space.s6)
            .padding(.vertical, Space.s5)
        }
        .background(.tujiBg)
        .task {
            await categories.loadIfNeeded()
            seedDefaults()
        }
        .onChange(of: categories.categories) { _, _ in
            seedDefaults()
        }
    }

    // MARK: - Bits

    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title)
                .font(.tujiOverline)
                .foregroundStyle(.tujiInk3)
                .padding(.horizontal, Space.s6)
            content()
                .padding(.horizontal, Space.s6)
        }
    }

    private func tile(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(selected ? .tujiTeal : .tujiInk2)
                .padding(.vertical, Space.s4)
                .frame(maxWidth: .infinity)
                .background(
                    selected ? Color.tujiTealSoft : .tujiCard,
                    in: .rect(cornerRadius: Radius.md)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(
                            selected ? Color.tujiTeal : .tujiInk4.opacity(0.25),
                            lineWidth: selected ? 1.5 : 1
                        )
                )
        }
    }

    private func categoryTile(category: TujiCategory, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(category.emoji)
                    .font(.system(size: 22))
                Text(category.nameZh)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(selected ? .tujiTeal : .tujiInk2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity)
            .background(
                selected ? Color.tujiTealSoft : .tujiCard,
                in: .rect(cornerRadius: Radius.md)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(
                        selected ? Color.tujiTeal : .tujiInk4.opacity(0.25),
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
        if preferred.count == Self.defaultTopicIds.count {
            topicIds = Set(preferred)
        } else {
            topicIds = Set(categories.categories.prefix(3).map(\.id))
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
                uiLang: "zh-Hant",
                fontSize: "md"
            )

            do {
                _ = try await APIClient.shared.post(
                    .usersSettings,
                    body: settings,
                    as: SaveSettingsResponse.self
                )
                onboarding.markSetupDone(for: userId)
                onDone()
            } catch APIError.unauthorized {
                error = "後端不認這次登入。可能要重新登入一次。"
                showReSignIn = true
            } catch let APIError.server(status: status, body: body) {
                error = "儲存失敗（\(status)）：\(body ?? "")"
                showReSignIn = false
            } catch {
                self.error = error.localizedDescription
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
