// Streak-milestone celebration (§III.R Milestone). Triggered when the
// server attaches `milestone: { streak: N }` to a /api/study/answer
// response — currently no-op on the server but wired client-side so
// W5 server work can switch it on without a client release.
//
// Ink face, cheer pose, the streak number at display size, Share + 繼續.
//
// The number is teal, not 瞳黃. A streak is accumulated days — the same family
// as mastery and completion — and 瞳黃 means "now". The pale step rather than the
// deep one because deep teal only reaches 3.04:1 against ink while the pale
// reaches 13.58:1.
//
// Nothing here bounces, sparkles or plays a sound. This screen appears three
// times a year at most; its weight comes from that rarity, and the moment it
// starts performing it becomes the reward-animation register the design rules out.

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
            Color.tujiInk.ignoresSafeArea()
            VStack(spacing: Space.s4) {
                Spacer()
                MascotCelebrationCard(title: "連勝 \(self.milestone.streak) 天！") {
                    VStack(spacing: Space.s4) {
                        Text("\(self.milestone.streak)")
                            .font(.tujiDisplay)
                            .foregroundStyle(.tujiTealSoft)
                            .contentTransition(.numericText())
                        Text("連續學習天數")
                            .font(.tujiLabel)
                            .tracking(0.5)
                            .foregroundStyle(.tujiPaper.opacity(0.6))
                        Text(self.subtitle)
                            .font(.tujiBody)
                            .foregroundStyle(.tujiPaper)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Space.s4)
                    }
                }
                Spacer()
                self.actions
            }
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s5)
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
                .padding(.vertical, Space.s3)
                .background(.tujiEye, in: .rect(cornerRadius: Radius.r0))
            }
            Button(action: self.onFinish) {
                Text("繼續")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tujiPaper.opacity(0.85))
                    .padding(.vertical, Space.s3)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    MilestoneView(milestone: Milestone(streak: 30), onFinish: {})
}
