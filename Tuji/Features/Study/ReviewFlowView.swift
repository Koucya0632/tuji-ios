// ReviewFlow root (§III.Q). MCQ surface on top, slide-in footer with
// SRS rating buttons on the bottom once the user picks. Each item runs
// answer → reveal → rate → next.

import Nuke
import NukeUI
import OSLog
import Observation
import SwiftUI

struct ReviewFlowView: View {
    let queue: [StudyQueueItem]
    @State private var coord: ReviewFlowCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(StudyFocus.self) private var studyFocus
    @State private var showExitConfirm = false
    // ReviewFlowView is pushed via .navigationDestination(item:) from
    // StudyLauncherView, which doesn't carry the ancestor's
    // .tujiNavDestinations(for: NavRoute) registry into this scope —
    // so NavigationLink(value: NavRoute.wordDetail) in the footer
    // resolved to nothing. Drive the push from a local item-based
    // destination instead, mirroring StudyLauncherView's pattern.
    @State private var pushWordId: String?

    init(queue: [StudyQueueItem]) {
        self.queue = queue
        self._coord = State(initialValue: ReviewFlowCoordinator(queue: queue))
    }

    var body: some View {
        Group {
            if self.coord.finished {
                if let m = coord.milestone {
                    MilestoneView(milestone: m, onFinish: { self.dismiss() })
                } else {
                    CompleteView(
                        answered: self.coord.answered,
                        dailyGoal: self.coord.dailyGoal,
                        onFinish: { self.dismiss() }
                    )
                }
            } else {
                self.flowSurface
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
        .toolbar(self.coord.finished ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            if !self.coord.finished {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        self.showExitConfirm = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(.tujiInk2)
                    }
                }
            }
        }
        .alert("離開練習？", isPresented: self.$showExitConfirm) {
            Button("繼續練習", role: .cancel) {}
            Button("離開", role: .destructive) { self.dismiss() }
        } message: {
            Text("已答的進度已存，未完成的字下次還會出現")
        }
        .navigationDestination(item: self.$pushWordId) { id in
            WordDetailView(id: id)
        }
        .onAppear { self.studyFocus.enter() }
        .onDisappear { self.studyFocus.exit() }
    }

    private var flowSurface: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    self.header
                    if let item = coord.current {
                        ReviewQuestionView(
                            coord: self.coord,
                            item: item,
                            heroHeight: self.heroHeight(in: geo)
                        )
                    } else {
                        Spacer()
                    }
                }
                if self.coord.phase == .review, let item = coord.current {
                    ReviewFooter(
                        coord: self.coord,
                        item: item,
                        onSeeDetail: { self.pushWordId = item.word.id }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: self.coord.phase)
            .background(.tujiBg)
            // MainTabsView normally reserves 78pt for the custom TujiTabBar;
            // that ancestor inset doesn't propagate into pushed views, so we
            // mirror it. In study mode (StudyFocus.active) both the bar and
            // its reservation go away — drop the local mirror too.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: self.studyFocus.active ? 0 : 78)
            }
        }
    }

    /// Hero height adapts to the device. In study mode the tab bar is
    /// hidden (PR #46) so we have ~78pt more headroom and the cap pushes
    /// up to 360pt — image details (rice grains, bottle profiles) become
    /// legible. Normal mode keeps PR #45's 280 cap.
    private func heroHeight(in geo: GeometryProxy) -> CGFloat {
        // Fixed costs other than the hero, sized to the smaller of
        //   - study mode: tab inset 0, scroll-bottom s4 (16)
        //   - normal mode: tab inset 78, scroll-bottom s24 (96)
        let active = self.studyFocus.active
        let tabInset: CGFloat = active ? 0 : 78
        let scrollBottom: CGFloat = active ? 16 : 96
        // toolbar 44 + header 50 + bubble 56 + 2× s4 spacing 32
        // + 4 choices 216 + slack 20
        let baseReserved: CGFloat = 418
        let reserved = baseReserved + tabInset + scrollBottom
        let available = geo.size.height - reserved
        return min(active ? 360 : 280, max(200, available))
    }

    private var header: some View {
        VStack(spacing: Space.s3) {
            HStack {
                Text("複習")
                    .font(.tujiOverline)
                    .tracking(2)
                    .foregroundStyle(.tujiTeal)
                Spacer()
                Text("\(self.coord.index + 1) / \(self.coord.queue.count)")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.tujiInk3)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.tujiInk4.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.tujiTeal)
                        .frame(width: geo.size.width * self.coord.progress)
                        .animation(.spring(duration: 0.5), value: self.coord.progress)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s1)
        .padding(.bottom, Space.s3)
    }
}

// MARK: - Question (image + bubble + 4 options)

private struct ReviewQuestionView: View {
    let coord: ReviewFlowCoordinator
    let item: StudyQueueItem
    let heroHeight: CGFloat

    @Environment(StudyFocus.self) private var studyFocus

    private static let abc = ["A", "B", "C", "D", "E"]

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s4) {
                self.bubble
                self.hero
                self.choicesList
            }
            .padding(.horizontal, Space.s6)
            // PR #46: in study mode the tab bar is gone so we can trim the
            // big s24 scroll buffer that previously kept the footer clear.
            .padding(.bottom, self.studyFocus.active ? Space.s4 : Space.s24)
        }
    }

    private var bubble: some View {
        HStack(spacing: Space.s2) {
            Mascot(pose: .think, size: 40)
            Text("這個是什麼？")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.tujiInk)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s2)
                .background(.tujiTealSoft, in: .rect(cornerRadius: Radius.md))
            Spacer()
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomTrailing) {
            GeometryReader { proxy in
                ZStack {
                    Rectangle().fill(.tujiCard)
                    LazyImage(url: self.item.word.imageURL) { state in
                        if let image = state.image {
                            image.resizable()
                                .scaledToFit()
                                .frame(
                                    width: max(0, proxy.size.width - Space.s4),
                                    height: max(0, proxy.size.height - Space.s4)
                                )
                        } else if state.error != nil {
                            Image(systemName: "photo")
                                .foregroundStyle(.tujiInk4)
                        } else {
                            ProgressView().tint(.tujiTeal)
                        }
                    }
                    .pipeline(.shared)
                }
            }
            .frame(height: self.heroHeight)
            .clipped()
            .clipShape(.rect(cornerRadius: Radius.lg))

            PronunciationButton(text: self.item.word.word, size: 36)
                .padding(Space.s3)
        }
    }

    private var choicesList: some View {
        VStack(spacing: Space.s2) {
            let choices = self.computedChoices
            ForEach(Array(choices.enumerated()), id: \.element) { idx, choice in
                self.optionRow(label: choice, letter: Self.abc[idx])
            }
        }
    }

    private var computedChoices: [String] {
        if let c = item.choices, !c.isEmpty { return c }
        return [self.item.word.word]
    }

    private func optionRow(label: String, letter: String) -> some View {
        let style = self.optionStyle(for: label)
        return Button {
            self.coord.pick(label)
        } label: {
            HStack(spacing: Space.s3) {
                Text(letter)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(style.letterFg)
                    .frame(width: 24, height: 24)
                    .background(style.letterBg, in: .circle)
                Text(label)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(style.fg)
                Spacer()
                if let icon = style.icon {
                    Image(systemName: icon).foregroundStyle(style.iconColor)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .background(style.bg, in: .rect(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(style.border, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(self.coord.phase == .review)
        .opacity(style.opacity)
    }

    private func optionStyle(for label: String) -> OptionStyle {
        guard self.coord.phase == .review, let picked = coord.picked else {
            return OptionStyle.idle
        }
        let isAnswer = label == self.item.word.word
        let isPicked = label == picked
        if isPicked, isAnswer { return .right }
        if isPicked, !isAnswer { return .wrong }
        if isAnswer { return .answer }
        return .dim
    }

    private struct OptionStyle {
        let bg: Color
        let border: Color
        let fg: Color
        let letterFg: Color
        let letterBg: Color
        let icon: String?
        let iconColor: Color
        let opacity: Double

        static let idle = OptionStyle(
            bg: .tujiCard, border: .tujiInk4.opacity(0.25),
            fg: .tujiInk, letterFg: .tujiInk3, letterBg: .tujiTealSoft,
            icon: nil, iconColor: .clear, opacity: 1
        )
        static let right = OptionStyle(
            bg: .tujiGreen.opacity(0.12), border: .tujiGreen,
            fg: .tujiInk, letterFg: .white, letterBg: .tujiGreen,
            icon: "checkmark.circle.fill", iconColor: .tujiGreen, opacity: 1
        )
        static let wrong = OptionStyle(
            bg: .tujiCoral.opacity(0.12), border: .tujiCoral,
            fg: .tujiInk, letterFg: .white, letterBg: .tujiCoral,
            icon: "xmark.circle.fill", iconColor: .tujiCoral, opacity: 1
        )
        static let answer = OptionStyle(
            bg: .tujiGreen.opacity(0.08), border: .tujiGreen.opacity(0.7),
            fg: .tujiInk, letterFg: .white, letterBg: .tujiGreen,
            icon: "arrow.left.circle.fill", iconColor: .tujiGreen, opacity: 1
        )
        static let dim = OptionStyle(
            bg: .tujiCard, border: .tujiInk4.opacity(0.15),
            fg: .tujiInk3, letterFg: .tujiInk4, letterBg: .tujiInk4.opacity(0.15),
            icon: nil, iconColor: .clear, opacity: 0.5
        )
    }
}

// MARK: - Footer (reveal + rating)

private struct ReviewFooter: View {
    let coord: ReviewFlowCoordinator
    let item: StudyQueueItem
    let onSeeDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            self.summary
            Button(action: self.onSeeDetail) {
                HStack(spacing: 4) {
                    Text("字卡詳情")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.tujiTeal)
            }
            .buttonStyle(.plain)
            Divider().background(.tujiInk4.opacity(0.15))
            Text(self.coord.wasCorrect ? "記得多牢？" : "沒關係，標記一下")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.tujiInk2)
            self.ratingRow
            if self.coord.rateError != nil {
                Text("同步失敗，請再點一次評分")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiCoral)
            }
        }
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiCard)
        .clipShape(.rect(topLeadingRadius: Radius.xl, topTrailingRadius: Radius.xl))
        .shadow(color: .black.opacity(0.08), radius: 12, y: -2)
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Rectangle().fill(.tujiTealSoft)
                LazyImage(url: self.item.word.imageURL) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "photo").foregroundStyle(.tujiInk4)
                    }
                }
                .pipeline(.shared)
            }
            .frame(width: 46, height: 46)
            .clipShape(.rect(cornerRadius: Radius.md))

            VStack(alignment: .leading, spacing: 2) {
                Text(self.item.word.word)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.tujiInk)
                if !self.item.word.pronunciation.isEmpty {
                    Text(self.item.word.pronunciation)
                        .font(.tujiMono)
                        .foregroundStyle(.tujiInk3)
                }
                Text(self.item.word.chinese)
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk2)
                    .lineLimit(2)
            }
            Spacer()
            PronunciationButton(text: self.item.word.word, size: 36)
        }
    }

    private var ratingRow: some View {
        HStack(spacing: Space.s2) {
            ForEach(self.coord.availableRatings, id: \.self) { r in
                self.rateButton(r)
            }
        }
    }

    private func rateButton(_ r: SRSRating) -> some View {
        let isSuggested = r == self.coord.suggested
        let isRated = self.coord.rated == r
        return Button {
            Task { await self.coord.rate(r) }
        } label: {
            VStack(spacing: 4) {
                if isSuggested {
                    Text("建議")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.tujiTeal)
                } else {
                    Color.clear.frame(height: 11)
                }
                Text(r.rawValue)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(self.fg(for: r, rated: isRated))
                    .padding(.vertical, Space.s3)
                    .frame(maxWidth: .infinity)
                    .background(self.bg(for: r, rated: isRated), in: .rect(cornerRadius: Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .stroke(self.border(for: r, suggested: isSuggested), lineWidth: isSuggested ? 2 : 1)
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(self.coord.rated != nil)
    }

    private func fg(for r: SRSRating, rated: Bool) -> Color {
        if rated { return .white }
        return self.tint(for: r)
    }

    private func bg(for r: SRSRating, rated: Bool) -> Color {
        if rated { return self.tint(for: r) }
        return self.tint(for: r).opacity(0.08)
    }

    private func border(for r: SRSRating, suggested: Bool) -> Color {
        if suggested { return .tujiTeal }
        return self.tint(for: r).opacity(0.3)
    }

    private func tint(for r: SRSRating) -> Color {
        switch r {
        case .again: .tujiCoral
        case .hard: .tujiYellow
        case .good: .tujiTeal
        case .easy: .tujiGreen
        }
    }
}
