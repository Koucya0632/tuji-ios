// Per-user Setup picker shown once after the user's first sign-in.
//
// Saves to /api/users/settings via APIClient and marks the per-user
// setupDone flag in OnboardingState; RootView then advances to
// PushPermissionView (or MainTabs if push has already been prompted).

import SwiftUI

struct SetupView: View {
    let userId: UUID
    let onDone: () -> Void

    @Environment(OnboardingState.self) private var onboarding

    @State private var level: Level = .basic
    @State private var topics: Set<String> = ["廚房", "生活"]
    @State private var dailyGoal: Int = 10
    @State private var saving = false
    @State private var error: String?

    enum Level: String, CaseIterable, Identifiable {
        case beginner = "初學"
        case basic = "基礎"
        case advanced = "進階"
        var id: String {
            rawValue
        }
    }

    private let allTopics = ["廚房", "生活", "辦公", "旅行", "學校"]
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

                    section(title: "你的英文程度") {
                        HStack(spacing: Space.s2) {
                            ForEach(Level.allCases) { l in
                                tile(label: l.rawValue, selected: level == l) {
                                    level = l
                                }
                            }
                        }
                    }

                    section(title: "想先學哪些主題？") {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 3),
                            spacing: Space.s2
                        ) {
                            ForEach(allTopics, id: \.self) { t in
                                tile(label: t, selected: topics.contains(t)) {
                                    if topics.contains(t) {
                                        topics.remove(t)
                                    } else {
                                        topics.insert(t)
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
                        Text(error)
                            .font(.tujiCaption)
                            .foregroundStyle(.tujiCoral)
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
            .disabled(saving)
            .padding(.horizontal, Space.s6)
            .padding(.vertical, Space.s5)
        }
        .background(.tujiBg)
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

    private func save() {
        Task {
            saving = true
            error = nil
            defer { saving = false }

            let settings = UserSettings(
                dailyGoal: dailyGoal,
                accent: "us",
                showZh: true,
                studyCategory: "all",
                studyCategories: topics.sorted().joined(separator: ","),
                studyDecks: "",
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
            } catch let APIError.server(status: status, body: body) {
                error = "儲存失敗（\(status)）：\(body ?? "")"
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

#Preview {
    SetupView(userId: UUID(), onDone: {})
        .environment(OnboardingState.shared)
}
