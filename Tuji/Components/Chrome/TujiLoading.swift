// Loading — replaces every system spinner in the app.
//
// 44 spinners all said the same thing: "wait". A skeleton says two things —
// it is loading, *and* this is the shape of what is coming. Nothing new is
// invented to do it: the skeleton is `tujiPaper2`, a colour the system already
// has, which is what makes this "replace a neutral decision with an opinionated
// one" rather than "add something".
//
// Split by whether the wait has a known shape:
//   • content arriving  → skeleton in the shape of the content
//   • work completing   → an inline 3pt bar
//
// No shimmer sweep. A sweep is a gradient, and gradients are the door to the
// skeuomorphic register this design rules out.

import SwiftUI

/// A solid block standing in for content that is on its way. Give it the size of
/// the thing it replaces.
struct TujiSkeleton: View {
    var width: CGFloat?
    var height: CGFloat
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Rectangle()
            .fill(.tujiPaper2)
            .frame(width: self.width, height: self.height)
            .opacity(self.dim ? 0.55 : 1)
            .onAppear {
                guard !self.reduceMotion else { return }
                withAnimation(.easeOut(duration: Motion.d3).repeatForever(autoreverses: true)) {
                    self.dim = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// Skeleton rows for a list that is still loading.
struct TujiSkeletonRows: View {
    var count: Int = 3
    var height: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<self.count, id: \.self) { index in
                if index > 0 {
                    Rectangle()
                        .fill(.tujiRule)
                        .frame(height: Border.bw1)
                        .padding(.horizontal, Space.s4)
                }
                TujiSkeleton(height: self.height - 24)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s3)
            }
        }
        .accessibilityLabel(Text("載入中"))
    }
}

/// A 3pt bar for work that will finish: AI recognition, upload, review
/// submission, audio download. `progress` nil = indeterminate.
struct TujiProgressBar: View {
    var progress: Double?
    var track: Color = .tujiPaper3
    var fill: Color = .tujiEye

    @State private var sweep: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(self.track)
                Rectangle()
                    .fill(self.fill)
                    .frame(width: self.fillWidth(in: geo.size.width))
                    .offset(x: self.progress == nil ? self.sweep * geo.size.width : 0)
            }
            .onAppear {
                guard self.progress == nil, !self.reduceMotion else { return }
                withAnimation(.easeOut(duration: Motion.d3 * 2).repeatForever(autoreverses: true)) {
                    self.sweep = 0.65
                }
            }
        }
        .frame(height: Border.bw3)
        .animation(Motion.ease(Motion.d3), value: self.progress)
        .accessibilityLabel(Text("進行中"))
    }

    private func fillWidth(in total: CGFloat) -> CGFloat {
        guard let progress else { return total * 0.35 }
        return total * CGFloat(max(0, min(1, progress)))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Space.s5) {
        TujiSkeletonRows()
        TujiProgressBar(progress: 0.4).padding(.horizontal, Space.s4)
        TujiProgressBar(progress: nil).padding(.horizontal, Space.s4)
    }
    .padding(.vertical, Space.s5)
    .background(.tujiPaper)
}
