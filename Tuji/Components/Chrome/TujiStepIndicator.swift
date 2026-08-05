// Where you are in a multi-step flow (D.10).
//
// A 3pt bar cut into one segment per step: done is ink, the current one is 瞳黃,
// the rest are paper2. Same three marks the rest of the app uses for
// "finished / now / not yet", so the bar needs no legend.
//
// Not a system `ProgressView`, and not numbered dots: the capture flow's steps
// are named things the user is walking through, and a bar that fills says "how
// far" while these say "which one".

import SwiftUI

struct TujiStepIndicator: View {
    let total: Int
    /// 0-based. Anything below 0 renders as "not started".
    let current: Int

    var body: some View {
        HStack(spacing: Border.bw1) {
            ForEach(0..<max(1, self.total), id: \.self) { index in
                Rectangle()
                    .fill(self.fill(index))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Border.bw3)
        .animation(Motion.ease(Motion.d2), value: self.current)
        .accessibilityElement()
        .accessibilityLabel(Text("步驟 \(self.current + 1) / \(self.total)"))
    }

    private func fill(_ index: Int) -> Color {
        if index < self.current { return .tujiInk }
        if index == self.current { return .tujiEye }
        return .tujiPaper2
    }
}

#Preview {
    VStack(spacing: Space.s5) {
        TujiStepIndicator(total: 5, current: 0)
        TujiStepIndicator(total: 5, current: 2)
        TujiStepIndicator(total: 5, current: 4)
    }
    .padding()
    .background(.tujiPaper)
}
