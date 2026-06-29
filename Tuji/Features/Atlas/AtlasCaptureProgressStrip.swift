// 圖鑑頁置頂的「製作中」橫條：每個背景拍照工作（AtlasCaptureQueue）一張占位卡
// ——縮圖 + 階段文字 + 進度條。完成顯示打勾、可點進 自制圖鑑；失敗點一下重試。
// 空佇列時不渲染（零版面成本）。卡片本體在 自制圖鑑 / atlas 複習，不在主字典格狀清單。

import SwiftUI

struct AtlasCaptureProgressStrip: View {
    @State private var queue = AtlasCaptureQueue.shared

    var body: some View {
        if !self.queue.jobs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s3) {
                    ForEach(self.queue.jobs) { job in
                        switch job.stage {
                        case .done:
                            NavigationLink(value: NavRoute.atlasManage) {
                                AtlasCaptureJobCard(job: job)
                            }
                            .buttonStyle(.plain)
                        case .failed:
                            Button {
                                self.queue.retry(job.id)
                            } label: {
                                AtlasCaptureJobCard(job: job)
                            }
                            .buttonStyle(.plain)
                        default:
                            AtlasCaptureJobCard(job: job)
                        }
                    }
                }
                .padding(.horizontal, Space.s6)
                .padding(.vertical, Space.s3)
            }
            .background(.tujiBg)
        }
    }
}

private struct AtlasCaptureJobCard: View {
    let job: AtlasCaptureQueue.Job

    private var statusText: LocalizedStringKey {
        switch self.job.stage {
        case .confirming: "製作中…"
        case .creating: "生成卡片…"
        case .enriching: "補充詳情中…"
        case .done: "已加入圖鑑"
        case .failed: "製作失敗，點一下重試"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ZStack {
                if let thumb = job.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.tujiCard)
                }
                Rectangle().fill(.black.opacity(self.job.stage == .done ? 0.12 : 0.32))
                self.overlayIcon
            }
            .frame(width: 116, height: 116)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

            Text(self.job.lemma)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.tujiInk)
                .lineLimit(1)
            Text(self.statusText)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(self.job.stage == .failed ? .tujiCoral : .tujiInk3)
                .lineLimit(1)
            if self.job.stage != .failed {
                ProgressView(value: self.job.progress)
                    .tint(self.job.stage == .done ? .tujiGreen : .tujiTeal)
            }
        }
        .frame(width: 116)
    }

    @ViewBuilder
    private var overlayIcon: some View {
        switch self.job.stage {
        case .confirming, .creating, .enriching:
            ProgressView().tint(.white)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(.white)
        case .failed:
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.white)
        }
    }
}
