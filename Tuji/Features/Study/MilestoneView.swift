// Streak-milestone celebration (§III.R Milestone). Triggered when the
// server attaches `milestone: { streak: N }` to a /api/study/answer
// response — currently no-op on the server but wired client-side so
// W5 server work can switch it on without a client release.
//
// Ink face, cheer pose, the streak number at display size, and 繼續.
//
// It used to offer Share as the primary action, and the text it shared carried
// `https://tuji.app/share/milestone?n=N` — a URL that 404s, because that page
// was never built and Universal Links are not configured either. So the reward
// for a 100-day streak was posting a dead link. Removed rather than repaired:
// the landing page is a product decision, not a client fix, and shipping the
// broken version while it gets made is worse than not offering it.
//
// 繼續 inherits the primary slot the way CompleteView's footer does it — one
// full-width BBtn when there is only one thing to do, no faint text link left
// alone as the only way off the screen.
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

    var body: some View {
        ZStack {
            Color.tujiInk.ignoresSafeArea()
            VStack(spacing: Space.s4) {
                Spacer()
                MascotCelebrationCard(title: "連勝 \(self.milestone.streak) 天！") {
                    VStack(spacing: Space.s4) {
                        Text("\(self.milestone.streak)")
                            .font(.tujiDisplay)
                            .foregroundStyle(.tujiAccumulationSoft)
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

    /// 瞳黃 rather than 品牌黃: this screen's ground is ink, and 瞳黃 is what
    /// marks "the thing to do now" against it — the slot Share used to hold.
    private var actions: some View {
        BBtn(
            title: "繼續",
            bg: .tujiCurrent,
            fg: .tujiInk,
            fullWidth: true,
            action: self.onFinish
        )
    }
}

#Preview {
    MilestoneView(milestone: Milestone(streak: 30), onFinish: {})
}
