// Streak-milestone celebration (§III.R Milestone). Triggered when the
// server attaches `milestone: { streak: N }` to a /api/study/answer
// response — currently no-op on the server but wired client-side so
// W5 server work can switch it on without a client release.
//
// Dark ink background, Mascot cheer, big streak number, and Share + 繼續.

import SwiftUI

struct MilestoneView: View {
    let milestone: Milestone
    let onFinish: () -> Void

    private var shareText: String {
        tujiLocalized(
            "我在 Tuji 連勝 \(self.milestone.streak) 天了！\nhttps://tuji.app/share/milestone?n=\(self.milestone.streak)"
        )
    }

    var body: some View {
        ZStack {
            Color.tujiBgInk.ignoresSafeArea()
            VStack(spacing: Space.s5) {
                Spacer()
                MascotCelebrationCard(
                    title: "連勝 \(self.milestone.streak) 天！",
                    accent: .tujiYellow,
                    dark: true
                ) {
                    VStack(spacing: Space.s3) {
                        Text(self.subtitle)
                            .font(.tujiBody)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Space.s6)
                        self.streakCapsule
                    }
                }
                Spacer()
                self.actions
            }
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.s8)
        }
    }

    private var subtitle: LocalizedStringKey {
        switch self.milestone.streak {
        case 30: "這個月你沒有缺席"
        case 100: "百日連勝，已經是習慣了"
        case 365: "整整一年，沒缺席一天"
        default: "保持下去，下一個里程碑在前面"
        }
    }

    private var streakCapsule: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "flame.fill")
                .foregroundStyle(.tujiYellow)
            Text("\(self.milestone.streak) 天")
                .font(.tujiH3)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, Space.s5)
        .padding(.vertical, Space.s3)
        .background(.white.opacity(0.08), in: .capsule)
        .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
    }

    private var actions: some View {
        VStack(spacing: Space.s3) {
            ShareLink(item: self.shareText) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "square.and.arrow.up")
                    Text("分享")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tujiInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s4)
                .background(.tujiYellow, in: .rect(cornerRadius: Radius.lg))
            }
            Button(action: self.onFinish) {
                Text("繼續")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.vertical, Space.s3)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    MilestoneView(milestone: Milestone(streak: 30), onFinish: {})
}
