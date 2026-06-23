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
                        masteryByWord: self.coord.masteryByWord,
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
        .tujiPrompt(
            isPresented: self.$showExitConfirm,
            style: .confirmation,
            title: "要離開這次複習嗎？",
            message: "已答的進度會保留，未完成的字下次還會出現。",
            primary: TujiPromptAction("先離開") { self.dismiss() },
            secondary: TujiPromptAction("繼續複習", role: .cancel) {}
        )
        .onAppear { self.studyFocus.enter() }
        .onDisappear { self.studyFocus.exit() }
    }

    private var flowSurface: some View {
        GeometryReader { geo in
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Keep the MCQ option recolour on pick smooth (previously carried
            // by the footer's ZStack animation).
            .animation(.spring(duration: 0.35), value: self.coord.phase)
            .background(.tujiBg)
            // MainTabsView normally reserves 78pt for the custom TujiTabBar;
            // that ancestor inset doesn't propagate into pushed views, so we
            // mirror it. In study mode (StudyFocus.active) both the bar and
            // its reservation go away — drop the local mirror too.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: self.studyFocus.active ? 0 : 78)
            }
            // The reveal (summary + full-detail pull-up + SRS rating) rides up
            // as a detent sheet, mirroring the new-word peek sheet. Driven by
            // phase: rating advances the queue → phase flips to .answer → the
            // sheet dismisses on its own. Not swipe-dismissable — you must rate.
            //
            // Hide it while the exit-confirm prompt is up: the rest detent
            // leaves the toolbar ✕ tappable (presentationBackgroundInteraction),
            // so tapping it during reveal would otherwise stack the confirm
            // behind this sheet and bury both sets of buttons. The sheet
            // returns if the user taps 繼續複習.
            .sheet(isPresented: Binding(
                get: {
                    self.coord.phase == .review && !self.coord.finished
                        && !self.showExitConfirm
                },
                set: { _ in }
            )) {
                if let item = self.coord.current {
                    ReviewRevealSheet(coord: self.coord, item: item)
                }
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
                Text("\(self.coord.passedCount) / \(self.coord.originalCount)")
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
        MascotSpeechBubble(pose: .think, text: "這個是什麼？")
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

// MARK: - Reveal sheet (summary + pull-up details + rating)

private struct ReviewRevealSheet: View {
    let coord: ReviewFlowCoordinator
    let item: StudyQueueItem

    @Environment(SettingsStore.self) private var settings

    /// Resting detent — just tall enough for the header + hint + pinned rating
    /// row, so there's little dead space. Drag up to `.large` to reveal the
    /// full word details inline.
    private static let restDetent: PresentationDetent = .fraction(0.4)

    @State private var detent: PresentationDetent = ReviewRevealSheet.restDetent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                self.summary
                ExpandableWordDetail(wordId: self.item.word.id, expanded: self.detent == .large)
                    .padding(.top, self.detent == .large ? 0 : Space.s4)
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s5)
            .padding(.bottom, Space.s4)
        }
        .safeAreaInset(edge: .bottom) {
            self.ratingSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiBg)
        .presentationDetents([Self.restDetent, .large], selection: self.$detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .presentationBackground(.tujiBg)
        .presentationBackgroundInteraction(.enabled(upThrough: Self.restDetent))
        // Must rate to proceed — never swipe the sheet away (dragging between
        // detents to peek at details is still allowed).
        .interactiveDismissDisabled(true)
    }

    /// Pinned "CTA" for review: the SRS rating buttons (plus the prompt and
    /// the sync-failed retry hint), always reachable at either detent.
    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
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
        .padding(.top, Space.s3)
        .padding(.bottom, Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiBg)
    }

    /// Header laid out like the new-word peek sheet: no image (it's already on
    /// screen in the question above), word + pronunciation + 中文 on the left,
    /// favourite + audio buttons stacked on the right.
    private var summary: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(self.item.word.word)
                    .font(.tujiH1)
                    .foregroundStyle(.tujiInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if !self.item.word.pronunciation.isEmpty {
                    Text(self.item.word.pronunciation)
                        .font(.tujiMono)
                        .foregroundStyle(.tujiInk3)
                }
                if self.settings.current.showZh {
                    Text(self.item.word.chinese)
                        .font(.tujiBody)
                        .foregroundStyle(.tujiInk2)
                        .padding(.top, 2)
                }
            }
            Spacer()
            VStack(spacing: Space.s2) {
                FavoriteButton(wordId: self.item.word.id, size: 44)
                PronunciationButton(text: self.item.word.word, size: 44)
            }
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
