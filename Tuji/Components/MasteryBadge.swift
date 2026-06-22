// Mastery display widgets driven by MasteryLevel.
//
// - `MasteryBadge`: compact dot + tier-name pill on a white capsule, legible
//   over arbitrary tile artwork. Used in the 圖鑑 grid corner.
// - `MasteryBar`: tier pill + score% + thin progress bar. Used on the word
//   detail page, mirroring the web word page's mastery row.

import SwiftUI

/// Small pill (colored dot + tier name) for overlaying on word tiles.
struct MasteryBadge: View {
    let level: MasteryLevel

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(self.level.color)
                .frame(width: 6, height: 6)
            Text(self.level.name)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(self.level.color)
        }
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 3)
        .background(.tujiCard.opacity(0.95), in: .capsule)
        .overlay(Capsule().stroke(self.level.color.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }
}

/// Tier pill + score + progress bar for the word detail page. A nil score
/// (no user_words row) renders as 未學 with a "尚無紀錄" note and empty bar.
struct MasteryBar: View {
    let score: Int?

    private var level: MasteryLevel {
        MasteryLevel.from(score: self.score)
    }

    private var ratio: CGFloat {
        guard let s = self.score else { return 0 }
        return CGFloat(max(0, min(100, s))) / 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text(self.level.name)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(self.level.color)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, 4)
                    .background(self.level.color.opacity(0.14), in: .capsule)
                Spacer()
                if let s = self.score {
                    Text("\(s)%")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(self.level.color)
                        .contentTransition(.numericText())
                } else {
                    Text("尚無紀錄")
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk3)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.tujiInk4.opacity(0.2))
                    Capsule()
                        .fill(self.level.color)
                        .frame(width: geo.size.width * self.ratio)
                        .animation(.spring(duration: 0.5), value: self.ratio)
                }
            }
            .frame(height: 8)
        }
    }
}

#Preview {
    VStack(spacing: Space.s5) {
        HStack(spacing: Space.s3) {
            ForEach(MasteryLevel.allCases, id: \.self) { MasteryBadge(level: $0) }
        }
        MasteryBar(score: nil)
        MasteryBar(score: 24)
        MasteryBar(score: 52)
        MasteryBar(score: 73)
        MasteryBar(score: 91)
    }
    .padding()
    .background(.tujiBg)
}
