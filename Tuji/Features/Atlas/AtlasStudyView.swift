import NukeUI
import SwiftUI

struct AtlasStudyView: View {
    @State private var store = AtlasStore.shared
    @State private var queue: [AtlasStudyQueueItem] = []
    @State private var index = 0
    @State private var loading = false
    @State private var showAnswer = false
    @State private var startedAt = Date()
    @State private var ratingInFlight: SRSRating?
    @State private var errorMessage: String?
    @State private var lastDelta: MasteryDelta?

    @Environment(StudyFocus.self) private var studyFocus

    private let sessionId = UUID().uuidString

    private var current: AtlasStudyQueueItem? {
        guard self.index < self.queue.count else { return nil }
        return self.queue[self.index]
    }

    var body: some View {
        Group {
            if self.loading, self.queue.isEmpty {
                self.loadingView
            } else if let current {
                self.studySurface(current)
            } else {
                self.emptyView
            }
        }
        .background(.tujiBg)
        .navigationTitle("自制圖鑑複習")
        .navigationBarTitleDisplayMode(.inline)
        .task { await self.loadQueue() }
        .onAppear { self.studyFocus.enter() }
        .onDisappear { self.studyFocus.exit() }
    }

    private var loadingView: some View {
        VStack(spacing: Space.s3) {
            ProgressView().tint(.tujiTeal)
            Text("載入自制圖鑑卡片…")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        MascotEmptyState(
            pose: .sleep,
            title: "目前沒有待複習卡片",
            message: "先回自制圖鑑建立卡片，或晚點再來。"
        ) {
            BBtn(title: "重新整理", fullWidth: false, icon: "arrow.clockwise") {
                Task { await self.loadQueue(force: true) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Space.s6)
    }

    private func studySurface(_ item: AtlasStudyQueueItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                self.progressHeader
                self.imageCard(item)
                self.promptCard(item)
                self.answerPanel(item)
                self.errorBanner
            }
            .padding(.horizontal, Space.s6)
            .padding(.vertical, Space.s4)
        }
    }

    private var progressHeader: some View {
        VStack(spacing: Space.s3) {
            HStack {
                Text("ATLAS REVIEW")
                    .font(.tujiOverline)
                    .tracking(2)
                    .foregroundStyle(.tujiTeal)
                Spacer()
                Text("\(min(self.index + 1, self.queue.count)) / \(self.queue.count)")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.tujiInk3)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.tujiInk4.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.tujiTeal)
                        .frame(width: geo.size.width * self.progress)
                }
            }
            .frame(height: 6)
        }
    }

    private var progress: Double {
        guard !self.queue.isEmpty else { return 0 }
        return Double(self.index) / Double(self.queue.count)
    }

    private func imageCard(_ item: AtlasStudyQueueItem) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ZStack {
                Rectangle().fill(.tujiCard)
                LazyImage(url: item.item.imageURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(Space.s2)
                    } else if state.error != nil {
                        Image(systemName: "photo")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.tujiInk4)
                    } else {
                        ProgressView().tint(.tujiTeal)
                    }
                }
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl)
                    .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
            )
            HStack {
                Text(item.card.cardType)
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
                Spacer()
                Text("熟練度 \(item.mastery)")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
            }
        }
    }

    private func promptCard(_ item: AtlasStudyQueueItem) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("這張圖片是什麼？")
                .font(.tujiH2)
                .foregroundStyle(.tujiInk)
            if !item.card.front.isEmpty {
                Text(item.card.front)
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func answerPanel(_ item: AtlasStudyQueueItem) -> some View {
        if self.showAnswer {
            VStack(alignment: .leading, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(item.card.back)
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(.tujiInk)
                    Text(item.item.displayZhHant)
                        .font(.tujiBody)
                        .foregroundStyle(.tujiInk3)
                    if let explanation = item.card.explanation, !explanation.isEmpty {
                        Text(explanation)
                            .font(.tujiCaption)
                            .foregroundStyle(.tujiInk3)
                    }
                    if let lastDelta {
                        Text("熟練度 \(lastDelta.before) → \(lastDelta.after)")
                            .font(.tujiCaption)
                            .foregroundStyle(lastDelta.delta >= 0 ? .tujiTeal : .tujiCoral)
                    }
                }
                self.ratingRow(item)
            }
            .padding(Space.s4)
            .background(.tujiCard, in: .rect(cornerRadius: Radius.xl))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl)
                    .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
            )
        } else {
            BBtn(title: "顯示答案", bg: .tujiYellow, fullWidth: true, icon: "eye") {
                self.showAnswer = true
            }
        }
    }

    private func ratingRow(_ item: AtlasStudyQueueItem) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("這張卡片的熟悉度")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
            HStack(spacing: Space.s2) {
                self.ratingButton(.again, item: item, color: .tujiCoral)
                self.ratingButton(.hard, item: item, color: .tujiYellow)
                self.ratingButton(.good, item: item, color: .tujiTeal)
                self.ratingButton(.easy, item: item, color: .tujiGreen)
            }
        }
    }

    private func ratingButton(_ rating: SRSRating, item: AtlasStudyQueueItem, color: Color) -> some View {
        Button {
            Task { await self.rate(rating, item: item) }
        } label: {
            VStack(spacing: 2) {
                if self.ratingInFlight == rating {
                    ProgressView().tint(.white)
                } else {
                    Text(rating.label)
                        .font(.system(size: 13, weight: .heavy))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(color, in: .rect(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .disabled(self.ratingInFlight != nil)
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.tujiCaption)
                .foregroundStyle(.tujiCoral)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s3)
                .background(Color.tujiCoral.opacity(0.12), in: .rect(cornerRadius: Radius.md))
        }
    }

    private func loadQueue(force: Bool = false) async {
        if self.loading, !force { return }
        self.loading = true
        self.errorMessage = nil
        defer { self.loading = false }
        do {
            self.queue = try await self.store.loadStudyQueue(mode: "both", limit: 20)
            self.index = 0
            self.showAnswer = false
            self.startedAt = .now
            self.lastDelta = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func rate(_ rating: SRSRating, item: AtlasStudyQueueItem) async {
        guard self.ratingInFlight == nil else { return }
        self.ratingInFlight = rating
        self.errorMessage = nil
        defer { self.ratingInFlight = nil }
        do {
            let elapsedMs = Int(Date.now.timeIntervalSince(self.startedAt) * 1000)
            let response = try await self.store.answerStudyCard(
                cardId: item.card.id,
                rating: rating,
                responseMs: elapsedMs,
                sessionId: self.sessionId,
                activity: item.card.cardType
            )
            self.lastDelta = response.mastery
            try? await Task.sleep(for: .milliseconds(350))
            self.advance()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func advance() {
        if self.index + 1 >= self.queue.count {
            self.queue = []
            self.index = 0
        } else {
            self.index += 1
        }
        self.showAnswer = false
        self.startedAt = .now
        self.lastDelta = nil
    }
}

#Preview {
    NavigationStack {
        AtlasStudyView()
            .environment(StudyFocus.shared)
    }
}
