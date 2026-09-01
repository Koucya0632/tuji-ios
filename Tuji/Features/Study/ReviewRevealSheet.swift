// Reveal sheet for ReviewFlow (§III.Q): answer summary + pull-up full word
// detail (with tappable 詞塊 — see `.glossCard()` below), with the pinned action row — SRS rating buttons normally, or a
// single 下一題 for a retest-wrong (study material only, no second write).
// Split from ReviewFlowView for file size; state all lives on the
// coordinator.

import SwiftUI

/// How tall the reveal sheet rests. Everything the user must be able to read
/// without dragging — the word they just answered, and the rating row they are
/// being asked to use — is *measured*, not assumed.
///
/// It replaces a fixed `.fraction(0.4)`, which the rating section had quietly
/// outgrown: three 56pt rows plus the label, rule and padding come to ~275pt,
/// against ~350pt of sheet on a 874pt screen, leaving the summary a viewport
/// shorter than one line of a 26pt headword. The word was clipped in half at
/// the exact moment the sheet asked how well it was remembered. A fraction also
/// cannot grow with Dynamic Type, so every larger text size made it worse.
enum ReviewRevealLayout {
    /// Used only until the first layout pass reports real heights.
    static let fallbackFraction: CGFloat = 0.4

    /// `summary` and `rating` are measured; the two constants are the sheet's
    /// own top margin and the gap the scroll content leaves under the summary.
    /// The result is never smaller than the sum of its parts — that is the
    /// whole invariant, and the thing the old constant could not promise.
    static func restHeight(summary: CGFloat, rating: CGFloat) -> CGFloat {
        Space.s4 + summary + Space.s3 + rating
    }
}

struct ReviewRevealSheet: View {
    let coord: ReviewFlowCoordinator
    let item: StudyQueueItem

    @Environment(SettingsStore.self) private var settings
    @Environment(WordsStore.self) private var words

    @State private var summaryHeight: CGFloat?
    @State private var ratingHeight: CGFloat?
    @State private var detent: PresentationDetent = .fraction(ReviewRevealLayout.fallbackFraction)

    /// Resting detent — exactly tall enough for the summary + pinned rating
    /// row. Drag up to `.large` to reveal the full word details inline.
    private var restDetent: PresentationDetent {
        guard let s = self.summaryHeight, let r = self.ratingHeight else {
            return .fraction(ReviewRevealLayout.fallbackFraction)
        }
        return .height(ReviewRevealLayout.restHeight(summary: s, rating: r))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                self.summary
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        self.summaryHeight = $0
                    }
                ExpandableWordDetail(wordId: self.item.word.id, expanded: self.detent == .large)
                    .padding(.top, self.detent == .large ? 0 : Space.s3)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s3)
        }
        .safeAreaInset(edge: .bottom) {
            self.ratingSection
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    self.ratingHeight = $0
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiPaper)
        // 複習 was the one surface showing example sentences without a 詞塊 host,
        // so the same sentence that is tappable on 認識, 圖鑑詳情 and 學新字's
        // peek sheet went flat here — the feature looked absent in exactly the
        // place a user has just got the word wrong. An overlay, so hosting it
        // inside a sheet is fine; on the root, so it does not scroll away.
        .glossCard()
        .presentationDetents([self.restDetent, .large], selection: self.$detent)
        // The measured detent replaces the fallback one pass after the sheet
        // appears, and a selection that is no longer in the set is undefined —
        // so follow it, unless the user has already pulled the sheet up.
        .onChange(of: self.restDetent) { _, new in
            if self.detent != .large { self.detent = new }
        }
        // The grabber stays, unlike every other sheet in the app: this one has
        // two detents and pulling it up is how the full word detail is reached.
        // There it is an affordance, not the system's signature.
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Radius.r0)
        .presentationBackground(.tujiPaper)
        .presentationBackgroundInteraction(.enabled(upThrough: self.restDetent))
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
        WordSummaryRow(
            word: self.item.word,
            wordId: self.item.word.id,
            gloss: self.settings.current.showZh ? self.item.word.chinese : nil,
            audioUrls: self.words.find(id: self.item.word.id)?.audioUrls
        )
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
