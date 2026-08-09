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

import SwiftUI

struct AtlasCaptureQueueTile: View {
    let job: AtlasCaptureQueue.Job
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.placeholder
            Text(self.job.lemma)
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
                .lineLimit(1)
                .padding(.top, Space.s2)
            TujiStatusEdgeLabel(text: Text(self.status), edge: self.edge)
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
                if self.job.stage == .failed {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.tujiInk2)
                } else {
                    // A known-duration wait, so the bar shows the real fraction
                    // rather than sweeping (C.5).
                    TujiProgressBar(progress: self.job.progress, track: .tujiPaper, fill: .tujiCurrent)
                        .padding(.horizontal, Space.s4)
                }
            }
            .clipped()
    }

    private var status: LocalizedStringKey {
        switch self.job.stage {
        case .confirming, .creating: "生成中"
        case .enriching: "補充詳情中"
        case .done: "已加入圖鑑"
        case .failed: "生成失敗，點一下重試"
        }
    }

    private var edge: Color {
        switch self.job.stage {
        case .failed: .tujiAlert
        case .done: .tujiAccumulation
        case .confirming, .creating, .enriching: .tujiCurrent
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
            switch job.stage {
            case .done:
                NavigationLink(value: NavRoute.atlasManage) {
                    AtlasCaptureQueueTile(job: job) {}
                }
                .buttonStyle(.plain)
            case .failed:
                Button { self.queue.retry(job.id) } label: {
                    AtlasCaptureQueueTile(job: job) { self.queue.retry(job.id) }
                }
                .buttonStyle(.plain)
            case .confirming, .creating, .enriching:
                AtlasCaptureQueueTile(job: job) {}
            }
        }
    }
}
