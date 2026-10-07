// 今天已打卡 on the two study finish screens (學新字's NewDoneView and 複習's
// CompleteView). Studying is the check-in, so finishing a session is where it
// gets said — and where today's points can be collected without a detour
// through 首頁's chip. Which points line shows is
// `CheckInDecision.finishReward`.

import SwiftUI

/// 今天已打卡 with the streak, plus today's points when there are any to show.
///
/// Waits for the post-session refresh and for the server to count today: if
/// every answer is still parked offline, nothing here would be true yet.
struct SessionCheckInCard: View {
    let refreshed: Bool

    @Environment(ProgressStore.self) private var progress
    /// Optional so a flow presented outside the tab shell just goes without.
    @Environment(CheckInModel.self) private var model: CheckInModel?
    @State private var claimedTick = 0

    private var streak: Int? {
        guard self.refreshed, let streak = self.progress.streak, streak.todayCount > 0 else { return nil }
        return streak.current
    }

    private var reward: CheckInDecision.Reward {
        guard let model else { return .hidden }
        return CheckInDecision.finishReward(model.reward(fallbackStudiedToday: true))
    }

    var body: some View {
        Group {
            if let streak {
                self.card(streak: streak)
                    .transition(.opacity)
                    // On the card, which exists only once the refresh has
                    // landed and the server counts today — the same moment the
                    // wallet's studiedToday turns true.
                    .task { await self.model?.loadReward() }
            }
        }
        .animation(Motion.ease(Motion.d2), value: self.streak)
        .sensoryFeedback(.success, trigger: self.claimedTick)
    }

    private func card(streak: Int) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("今天已打卡")
                    .font(.tujiBody(.strong))
                    .foregroundStyle(.tujiInk)
                Text("連續 \(streak) 天")
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiAccumulation)
                    .contentTransition(.numericText())
                if let detail = self.reward.detail {
                    Text(detail)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk2)
                }
                if let message = self.model?.message {
                    Text(verbatim: message)
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiAlert)
                }
            }
            Spacer(minLength: Space.s2)
            if case let .claimable(points) = self.reward, let model {
                CheckInClaimButton(model: model, points: points) { self.claimedTick += 1 }
            } else {
                CheckInClaimedMark()
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(.tujiPaper2)
        .accessibilityElement(children: .combine)
    }
}
