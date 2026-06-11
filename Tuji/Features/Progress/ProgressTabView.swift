// Progress tab — full §III.L design lands in W4. v1 just shows the
// streak number + a sleep-mascot placeholder so the tab slot isn't dead.

import SwiftUI

struct ProgressTabView: View {
    @Environment(LocalCache.self) private var cache
    @Environment(AuthService.self) private var auth

    @State private var streak: StudyStreak?

    private var isGuest: Bool {
        if case .guest = auth.state { return true }
        if case .signedOut = auth.state { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                Text("進度")
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)
                self.summary
                self.placeholder
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s24)
        }
        .background(.tujiBg)
        .task {
            if !self.isGuest {
                let resp: ProgressResponse? = try? await APIClient.shared.get(.usersProgress)
                self.streak = resp?.streak
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s4) {
                self.tile(
                    label: "連續天數",
                    value: "\(self.streak?.current ?? 0)",
                    icon: "flame.fill",
                    tint: .tujiCoral
                )
                self.tile(
                    label: "已學過",
                    value: "\(self.totalLearned)",
                    icon: "checkmark.seal.fill",
                    tint: .tujiTeal
                )
            }
            self.tile(
                label: "最長紀錄",
                value: "\(self.streak?.longest ?? 0) 天",
                icon: "trophy.fill",
                tint: .tujiYellow
            )
        }
    }

    private func tile(label: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(label)
                    .font(.tujiOverline)
                    .tracking(2)
                    .foregroundStyle(.tujiInk3)
            }
            Text(value)
                .font(.system(size: 32, weight: .heavy))
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

    private var totalLearned: Int {
        self.cache.learnedIds.count
    }

    private var placeholder: some View {
        VStack(spacing: Space.s3) {
            Mascot(pose: .sleep, size: 80)
            Text("熱力圖 / 主題掌握度")
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
            Text("更詳細的學習進度視覺化會在 W4 推出")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s12)
    }
}

#Preview {
    NavigationStack {
        ProgressTabView()
            .environment(LocalCache.shared)
            .environment(AuthService.shared)
    }
}
