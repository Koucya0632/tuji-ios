// The 複習 hero: the picture the question is about, and the card it turns into.
// Split from ReviewFlowView for file size, like ReviewRevealSheet; all state
// lives on the coordinator, so this file holds presentation only.
//
// 求救提示 (hint flip) — tapping the picture turns it over to the 釋義, or to
// the gloss for a word that has none (`HintFace`). The
// affordance is deliberately invisible: nothing is drawn on the card, and a
// stalled item offers one line after `nudgeDelay` instead. VoiceOver does not
// inherit that choice — it gets an explicit custom action, because a user who
// cannot see the picture also cannot poke at it to find out.
//
// The hint face carries one visible affordance of its own: 看完整詳情, which
// raises the full word detail in a sheet. It is drawn only there, and only a
// user who has already flipped can reach it — by which point the item is on the
// wrong-answer rating table anyway, so the look-up adds no further cost
// (ADR-0007).

import SwiftUI

struct ReviewHeroCard: View {
    let coord: ReviewFlowCoordinator
    let item: StudyQueueItem
    let height: CGFloat

    @Environment(OnboardingState.self) private var onboarding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Armed by the stall timer; only *shown* while the coordinator still has
    /// something to teach on this item.
    @State private var nudgeArmed = false

    /// The 看完整詳情 sheet. Per presentation, like every other piece of
    /// per-item state — reset where the nudge is re-armed.
    @State private var showDetail = false

    /// How long an item may sit unanswered before the card offers the hint.
    /// Deliberately past the 7s mark where `computeSuggestion` has already
    /// dropped the suggestion to 困難 — by the time the line appears, the only
    /// thing flipping still costs is the 穩定/熟練 option.
    private static let nudgeDelay: Duration = .seconds(8)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            self.card

            PronunciationButton(
                subject: SpokenWord(self.item.word),
                size: 48,
                ground: .tujiPaper
            )
            .padding(Space.s3)
        }
        // The whole picture is the tap target, with nothing drawn to say so —
        // the pronunciation button above is a Button and keeps its own taps.
        .contentShape(.rect)
        .onTapGesture { self.flip() }
        .overlay(alignment: .bottomLeading) {
            if self.showNudge {
                self.nudge.padding(Space.s3)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: self.showNudge)
        // Keyed on the position too: a retest presents the same word id again
        // and must re-arm.
        .task(id: "\(self.item.id)#\(self.coord.index)") {
            self.showDetail = false
            await self.armNudge()
        }
        // Back on the convenience: it hosts the 詞塊 card outside the shell
        // itself now, which is the only reason this was hand-rolled.
        .tujiSheet(isPresented: self.$showDetail, title: "單字詳情", height: 520) {
            WordDetailSheet(
                word: self.item.word,
                wordId: self.item.word.id,
                // Not gated on `showZh`: that switch governs the always-on
                // gloss 學新字 prints on a picture, and this sheet is two
                // deliberate taps in.
                gloss: self.item.word.chinese
            )
        }
    }

    /// Full-bleed, on `tujiPaper2`, with the picture multiplied into it. The
    /// image used to be a `tujiPaper` rectangle inset inside the page margins,
    /// which put a white square on warm paper and framed the one thing the whole
    /// screen is asking about.
    ///
    /// The height stays adaptive rather than the square the spec asks for: a
    /// full-width 1:1 image plus four 64pt options does not fit above the fold
    /// on any phone, and pushing the answers off-screen to square the picture
    /// would cost more than the shape is worth.
    ///
    /// The hint *replaces* the picture rather than sitting beside it: once the
    /// meaning is given the question is no longer 「這張圖是什麼字」 but 「這個
    /// 意思是哪個字」, and a card asks one question at a time.
    private var card: some View {
        let up = self.coord.hintFaceUp
        return Color.tujiPaper2
            .frame(height: self.height)
            .overlay {
                ZStack {
                    self.pictureFace
                        .opacity(up ? 0 : 1)
                        .rotation3DEffect(
                            .degrees(self.flipAngle(up ? 180 : 0)),
                            axis: (x: 0, y: 1, z: 0)
                        )
                    self.hintFace
                        .opacity(up ? 1 : 0)
                        .rotation3DEffect(
                            .degrees(self.flipAngle(up ? 0 : -180)),
                            axis: (x: 0, y: 1, z: 0)
                        )
                        // An opacity-0 Button still takes taps: without this the
                        // hint face's 看完整詳情 would sit invisibly over the
                        // picture and swallow the flip.
                        .allowsHitTesting(up)
                }
            }
            .clipped()
            .animation(
                self.reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45),
                value: up
            )
            .accessibilityElement()
            // The label follows the face, so triggering the actions below
            // actually says something.
            .accessibilityLabel(up ? Text(HintFace(self.item.word).text) : Text("這個是什麼？"))
            // `.accessibilityElement()` ignores its children, so the button drawn
            // on the hint face does not exist for VoiceOver unless it is offered
            // here as well.
            .accessibilityActions {
                Button(up ? "看圖片" : "看提示") { self.flip() }
                if up, self.canOpenDetail {
                    Button("看完整詳情") { self.showDetail = true }
                }
            }
    }

    private var pictureFace: some View {
        WordPicture(
            url: self.item.word.imageURL,
            kind: self.item.word.imageKind
        )
    }

    /// The 釋義 when the word has one, else the gloss — `HintFace` decides, and
    /// says why the client does not second-guess the server about it.
    ///
    /// `reading` and `pronunciation` are both on the payload and neither may
    /// come here: a kana headword's 振假名 is itself, and an IPA line is the word
    /// read aloud — either one turns the hint into a skip.
    ///
    /// That rule is about the *face*. `detailButton` is the way past it, and it
    /// is a separate, deliberate tap that lands in a sheet — the difference
    /// between reading the answer and choosing to look it up.
    private var hintFace: some View {
        VStack(spacing: Space.s4) {
            // A sentence and a word do not set the same way: the gloss keeps the
            // headline it has always had, while a 釋義 at that size would fill
            // the card and shrink itself illegible under `minimumScaleFactor`.
            switch HintFace(self.item.word) {
            case let .gloss(text): self.hintText(text, font: .tujiH2, lines: 4)
            case let .definition(text): self.hintText(text, font: .tujiBody, lines: 6)
            }
            if self.canOpenDetail {
                self.detailButton
            }
        }
        .padding(.horizontal, Space.s5)
    }

    private func hintText(_ text: String, font: Font, lines: Int) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(.tujiInk)
            .multilineTextAlignment(.center)
            .lineLimit(lines)
            .minimumScaleFactor(0.6)
    }

    /// Only while the item is unanswered — the same window `toggleHint()` allows
    /// the flip in, and for a sharper reason. The reveal sheet rests with
    /// `presentationBackgroundInteraction` enabled, so this face stays tappable
    /// underneath it: left up, the button would raise a second sheet on top of
    /// the one asking for a rating and bury both sets of buttons. There is
    /// nothing lost — that sheet pulls up to the very same detail.
    private var canOpenDetail: Bool {
        self.coord.phase == .answer
    }

    /// An underlined label, not a filled `BBtn`: the hint face is one line of
    /// text on paper, and a brand-yellow block here would outweigh the four
    /// options it sits above. Underlined because this system has no colour that
    /// means tappable — the same mark `TujiNavTextAction` uses.
    private var detailButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.showDetail = true
        } label: {
            HStack(spacing: Space.s1) {
                Text("看完整詳情")
                Image(systemName: "arrow.up.right")
                    .font(.tujiIcon(12, weight: .semibold))
            }
            .font(.tujiLabel)
            .tracking(0.5)
            .underline()
            .foregroundStyle(.tujiInk2)
            .frame(height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Reduce Motion keeps the opacity swap and drops the rotation, so the turn
    /// becomes a crossfade.
    private func flipAngle(_ degrees: Double) -> Double {
        self.reduceMotion ? 0 : degrees
    }

    private func flip() {
        self.coord.toggleHint()
        // Marked when the card actually turns, not when the line appears:
        // someone who ignored the nudge has not learned anything yet.
        if self.coord.hinted {
            self.onboarding.reviewHintTaught = true
        }
    }

    private var showNudge: Bool {
        self.nudgeArmed && self.coord.canNudge && !self.onboarding.reviewHintTaught
    }

    /// Same slot the gloss occupies during 學新字 (IdentifyView) — the place the
    /// user already associates with "the meaning lives here".
    private var nudge: some View {
        Text("想不起來？點一下圖片")
            .font(.tujiBodySm)
            .foregroundStyle(.tujiInk2)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, Space.s1)
            .background(.tujiPaper)
            .transition(.opacity)
            .allowsHitTesting(false)
    }

    private func armNudge() async {
        self.nudgeArmed = false
        guard !self.onboarding.reviewHintTaught else { return }
        try? await Task.sleep(for: Self.nudgeDelay)
        guard !Task.isCancelled else { return }
        self.nudgeArmed = true
    }
}
