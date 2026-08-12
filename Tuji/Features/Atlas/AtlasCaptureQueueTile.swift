// A card being made, drawn in the 圖鑑 grid alongside the finished ones (D.10
// step 5).
//
// It used to be a horizontal strip pinned above the grid — a row of 116pt cards
// that scrolled sideways while everything under it scrolled down. That shape
// said "notification about a card", and the thing it was announcing was a card.
// A tile in the grid says the same thing with no new component: this is where
// your word will be, and it is not ready yet.
//
// The strip also cost a permanent band of vertical space at the top of the tab
// for as long as any job was alive, pushing the filter chips and the count down.
//
// The tile renders `CaptureProgress` and owns none of its copy: 圖鑑管理 says the
// same words about the same photo, and two screens deriving them separately is
// what let one call a capture 生成中 while the other called it 已上傳.

import SwiftUI

struct AtlasCaptureQueueTile: View {
    let job: AtlasCaptureQueue.Job

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.placeholder
            Text(self.job.lemma)
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
                .lineLimit(1)
                .padding(.top, Space.s2)
            TujiStatusEdgeLabel(text: Text(self.job.progress.label), edge: self.edge)
                .padding(.top, Space.s1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// `tujiPaper3`, a step deeper than the finished tiles' `tujiPaper2`: the
    /// slot is occupied but not yet filled, and the depth says that without a
    /// spinner or a shimmer.
    private var placeholder: some View {
        Color.tujiPaper3
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumb = job.thumbnail {
                    // The frame the user just took, held back so the row reads
                    // as "your photo, being worked on" rather than as an empty
                    // box with their word under it.
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(0.35)
                }
            }
            .overlay {
                if let fraction = job.progress.fraction {
                    // A known-duration wait, so the bar shows the real fraction
                    // rather than sweeping (C.5).
                    TujiProgressBar(progress: fraction, track: .tujiPaper, fill: .tujiCurrent)
                        .padding(.horizontal, Space.s4)
                } else if self.job.progress.canRetry {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.tujiInk2)
                } else {
                    // A capacity dead end. An arrow here would be an invitation
                    // to do the one thing that cannot work.
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.tujiInk2)
                }
            }
            .clipped()
    }

    private var edge: Color {
        switch self.job.progress {
        case .failed: .tujiAlert
        case .ready: .tujiAccumulation
        case .generating, .enriching: .tujiCurrent
        }
    }
}

/// The queue's tiles, ready to be dropped at the head of the 圖鑑 grid.
///
/// A `ForEach` rather than a container, so the tiles land in the caller's own
/// `LazyVGrid` and share its columns — a nested grid would have its own column
/// maths and drift from the real one on the next layout change.
struct AtlasCaptureQueueTiles: View {
    @State private var queue = AtlasCaptureQueue.shared

    var body: some View {
        ForEach(self.queue.jobs) { job in
            switch job.progress {
            case .ready:
                NavigationLink(value: NavRoute.atlasManage) {
                    AtlasCaptureQueueTile(job: job)
                }
                .buttonStyle(.plain)
            case .failed where job.progress.canRetry:
                Button { self.queue.retry(job.id) } label: {
                    AtlasCaptureQueueTile(job: job)
                }
                .buttonStyle(.plain)
            case .failed:
                // 已達上限: the only way out is 圖鑑管理 (delete something) or the
                // paywall, and both are a tap away from there.
                NavigationLink(value: NavRoute.atlasManage) {
                    AtlasCaptureQueueTile(job: job)
                }
                .buttonStyle(.plain)
            case .generating, .enriching:
                AtlasCaptureQueueTile(job: job)
            }
        }
    }
}
