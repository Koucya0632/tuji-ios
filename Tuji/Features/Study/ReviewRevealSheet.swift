// Reveal sheet for ReviewFlow (§III.Q): answer summary + pull-up full word
// detail, with the pinned action row — SRS rating buttons normally, or a
// single 下一題 for a retest-wrong (study material only, no second write).
// Split from ReviewFlowView for file size; state all lives on the
// coordinator.

import SwiftUI

struct ReviewRevealSheet: View {
    let coord: ReviewFlowCoordinator
    let item: StudyQueueItem

    @Environment(SettingsStore.self) private var settings
    @Environment(WordsStore.self) private var words

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

    /// Pinned "CTA" for review, always reachable at either detent. Manual
    /// rating buttons normally; a retest-wrong sheet is study material only
    /// (no second SRS write), so it pins a single 下一題 instead.
    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Divider().background(.tujiInk4.opacity(0.15))
            if self.coord.revealMode == .continueOnly {
                Text("再看一眼，等等再遇到它")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tujiInk2)
                BBtn(
                    title: "下一題",
                    bg: .tujiTeal,
                    fg: .white,
                    fullWidth: true,
                    icon: "arrow.right"
                ) {
                    self.coord.continueFromReveal()
                }
            } else {
                Text(self.coord.wasCorrect ? "記得多牢？" : "沒關係，標記一下")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tujiInk2)
                self.ratingRow
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
                PronunciationButton(
                    text: self.item.word.word,
                    language: self.item.word.wordLanguage,
                    audioUrls: self.words.find(id: self.item.word.id)?.audioUrls,
                    size: 44
                )
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
            self.coord.rate(r)
        } label: {
            VStack(spacing: 4) {
                if isSuggested {
                    Text("建議")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tujiTeal)
                } else {
                    Color.clear.frame(height: 11)
                }
                Text(r.label)
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
