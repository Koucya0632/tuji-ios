// 記憶曲線 — why 首頁 asks for 複習 before 學新字.
//
// Opened from the ⓘ beside the "要複習的字有點多" hint. A greyed 學新字 with a
// one-line reason reads as a rule the app is imposing; this is the reason
// behind the reason, so the pause reads as the method working rather than a
// wall. The thresholds quoted here are `StudyQuotas.computeNewLimit`'s — if
// those move, this copy moves with them.

import SwiftUI

struct ReviewCurveSheet: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                ForgettingCurveChart()

                self.point(
                    "剛學的字，忘得最快",
                    "沒有複習的話，新學的字幾天內就會忘掉一大半——這就是遺忘曲線。"
                )
                self.point(
                    "在快忘的時候複習",
                    "每次在快要忘記時複習一次，記憶就更牢，下次複習的間隔也會拉長：幾小時、幾天、幾週，到幾個月。花的時間越來越少，記得越來越久。"
                )
                self.point(
                    "所以先複習，再學新字",
                    "待複習超過 20 個字時，今天的新字會開始減量；超過 100 個就先暫停新字，等你清掉一些。這樣學過的字不會白學。"
                )
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s5)
        }
    }

    private func point(_ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title)
                .font(.tujiBody(.strong))
                .foregroundStyle(.tujiInk)
            Text(detail)
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Two curves on one axis: retention with no review, and the sawtooth that
/// spaced review draws — each review resets to full and each decay after it is
/// slower. Illustrative, not data: the shape is the point.
private struct ForgettingCurveChart: View {
    /// When each review happens, as a fraction of the x-axis.
    private static let reviews: [Double] = [0, 0.14, 0.34, 0.64]
    /// How slowly each segment decays — longer after every review.
    private static let stability: [Double] = [0.07, 0.17, 0.4, 1.2]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Canvas { context, size in
                // Inset so the review dots on the top edge are not clipped.
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 5, dy: 5)
                func point(_ t: Double, _ retention: Double) -> CGPoint {
                    CGPoint(x: rect.minX + t * rect.width, y: rect.minY + (1 - retention) * rect.height)
                }

                var baseline = Path()
                baseline.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                baseline.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                context.stroke(baseline, with: .color(.tujiRule), lineWidth: 1)

                var forgetting = Path()
                forgetting.move(to: point(0, 1))
                for step in stride(from: 0.0, through: 1.0, by: 0.01) {
                    forgetting.addLine(to: point(step, exp(-step / Self.stability[0])))
                }
                context.stroke(
                    forgetting,
                    with: .color(.tujiInk.opacity(0.35)),
                    style: StrokeStyle(lineWidth: 2, dash: [4, 4])
                )

                var spaced = Path()
                for (index, start) in Self.reviews.enumerated() {
                    let end = index + 1 < Self.reviews.count ? Self.reviews[index + 1] : 1
                    let s = Self.stability[index]
                    if index == 0 {
                        spaced.move(to: point(start, 1))
                    } else {
                        spaced.addLine(to: point(start, 1))
                    }
                    for step in stride(from: start, through: end, by: 0.01) {
                        spaced.addLine(to: point(step, exp(-(step - start) / s)))
                    }
                }
                context.stroke(spaced, with: .color(.tujiAccumulation), lineWidth: 2.5)

                for start in Self.reviews.dropFirst() {
                    let dot = Path(ellipseIn: CGRect(origin: point(start, 1), size: .zero).insetBy(dx: -4, dy: -4))
                    context.fill(dot, with: .color(.tujiCurrent))
                    context.stroke(dot, with: .color(.tujiInk), lineWidth: 1)
                }
            }
            .frame(height: 120)
            .accessibilityHidden(true)

            HStack(spacing: Space.s4) {
                self.legend("按時複習", color: .tujiAccumulation, dashed: false)
                self.legend("不複習", color: .tujiInk.opacity(0.35), dashed: true)
                Spacer()
                Text("時間 →")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk.opacity(0.5))
            }
        }
        .padding(Space.s3)
        .overlay(Rectangle().stroke(.tujiRule, lineWidth: 1))
    }

    private func legend(_ label: LocalizedStringKey, color: Color, dashed: Bool) -> some View {
        HStack(spacing: Space.s1) {
            Path { path in
                path.move(to: .init(x: 0, y: 5))
                path.addLine(to: .init(x: 16, y: 5))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 3] : []))
            .frame(width: 16, height: 10)
            Text(label)
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk.opacity(0.7))
        }
    }
}
