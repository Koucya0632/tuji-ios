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
            VStack(alignment: .leading, spacing: Space.s3) {
                self.summary
                ExpandableWordDetail(wordId: self.item.word.id, expanded: self.detent == .large)
                    .padding(.top, self.detent == .large ? 0 : Space.s3)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s3)
        }
        .safeAreaInset(edge: .bottom) {
            self.ratingSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiPaper)
        .presentationDetents([Self.restDetent, .large], selection: self.$detent)
        // The grabber stays, unlike every other sheet in the app: this one has
        // two detents and pulling it up is how the full word detail is reached.
        // There it is an affordance, not the system's signature.
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Radius.r0)
        .presentationBackground(.tujiPaper)
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
            Rectangle().fill(.tujiRule).frame(height: Border.bw1)
            if self.coord.revealMode == .continueOnly {
                Text("再看一眼，等等再遇到它")
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk3)
                BBtn(
                    title: "下一題",
                    bg: .tujiBrandPrimary,
                    fg: .tujiInk,
                    fullWidth: true,
                    icon: "arrow.right"
                ) {
                    self.coord.continueFromReveal()
                }
            } else {
                Text(self.coord.wasCorrect ? LocalizedStringKey("記得多牢？") : LocalizedStringKey("沒關係，標記一下"))
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk3)
                self.ratingRow
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
        .padding(.bottom, Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiPaper)
    }

    /// Header laid out like the new-word peek sheet: no image (it's already on
    /// screen in the question above), word + pronunciation + 中文 on the left,
    /// favourite + audio buttons stacked on the right.
    private var summary: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                TujiHeadword(
                    display: self.item.word.headwordDisplay,
                    word: self.item.word.word,
                    language: self.item.word.wordLanguage
                )
                if case let .line(text) = self.item.word.headwordDisplay {
                    Text(text)
                        .font(self.item.word.wordLanguage == .ja ? .tujiBodySm : .tujiMono)
                        .foregroundStyle(.tujiInk3)
                }
                if self.settings.current.showZh {
                    Text(self.item.word.chinese)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk2)
                        .padding(.top, 2)
                }
            }
            // See WordDetailView.titleRow: beside a `Spacer` the headword is
            // offered half the row unless it is prioritised.
            .layoutPriority(1)
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

    /// Stacked full width, not four boxes side by side.
    ///
    /// §6.4 asks whether anyone will honestly pick 困難. Laid out as a row, the
    /// levels are read as a scale and the hand drifts rightward — the labels are
    /// all you can fit, and "困難" beside "熟練" is just the worse-sounding one.
    /// Stacked, each level gets a line explaining what it *means*, and picking
    /// becomes a decision about yourself rather than a position on a slider.
    ///
    /// How many rows is the answer's business: 困難/穩定/熟練 when the answer was
    /// right, 重來/困難 when it was wrong. Adding 重來 to a correct answer would
    /// send a different rating and reschedule the card — which is exactly the
    /// scoring behaviour this redesign is not allowed to touch.
    private var ratingRow: some View {
        VStack(spacing: Space.s2) {
            ForEach(self.coord.availableRatings, id: \.self) { r in
                self.rateButton(r)
            }
        }
    }

    private func rateButton(_ r: SRSRating) -> some View {
        // The suggestion is pre-inverted rather than badged: the ink block is
        // already this app's "this is the one", so a 建議 caption over the label
        // was a second, weaker way of saying it.
        let filled = self.coord.rated == r || (self.coord.rated == nil && r == self.coord.suggested)
        return Button {
            self.coord.rate(r)
        } label: {
            HStack(spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.label)
                        .font(.tujiH3)
                        .foregroundStyle(filled ? .tujiPaper : .tujiInk)
                    Text(r.explanation)
                        .font(.tujiBodySm)
                        .foregroundStyle(filled ? Color.tujiPaper.opacity(0.7) : .tujiInk3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s3)
            .frame(minHeight: 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) {
                HStack(spacing: 0) {
                    Rectangle().fill(r.edge).frame(width: Border.bw3)
                    Rectangle().fill(filled ? Color.tujiInk : .tujiPaper2)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(self.coord.rated != nil)
    }
}
