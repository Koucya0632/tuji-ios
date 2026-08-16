// The 複習 hero: the picture the question is about, and the card it turns into.
// Split from ReviewFlowView for file size, like ReviewRevealSheet; all state
// lives on the coordinator, so this file holds presentation only.
//
// 求救提示 (hint flip) — tapping the picture turns it over to the gloss. The
// affordance is deliberately invisible: nothing is drawn on the card, and a
// stalled item offers one line after `nudgeDelay` instead. VoiceOver does not
// inherit that choice — it gets an explicit custom action, because a user who
// cannot see the picture also cannot poke at it to find out.

import SwiftUI

struct ReviewHeroCard: View {
    let coord: ReviewFlowCoordinator
    let item: StudyQueueItem
    let height: CGFloat

    @Environment(WordsStore.self) private var words
    @Environment(OnboardingState.self) private var onboarding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Armed by the stall timer; only *shown* while the coordinator still has
    /// something to teach on this item.
    @State private var nudgeArmed = false

    /// How long an item may sit unanswered before the card offers the hint.
    /// Deliberately past the 7s mark where `computeSuggestion` has already
    /// dropped the suggestion to 困難 — by the time the line appears, the only
    /// thing flipping still costs is the 穩定/熟練 option.
    private static let nudgeDelay: Duration = .seconds(8)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            self.card

            PronunciationButton(
                text: self.item.word.word,
                language: self.item.word.taggedLanguage,
                audioUrls: self.words.find(id: self.item.word.id)?.audioUrls,
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
        .task(id: "\(self.item.id)#\(self.coord.index)") { await self.armNudge() }
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
                }
            }
            .clipped()
            .animation(
                self.reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45),
                value: up
            )
            .accessibilityElement()
            // The label follows the face, so triggering the action below
            // actually says something.
            .accessibilityLabel(up ? Text(self.item.word.chinese) : Text("這個是什麼？"))
            .accessibilityAction(named: up ? Text("看圖片") : Text("看提示")) {
                self.flip()
            }
    }

    private var pictureFace: some View {
        WordPicture(
            url: self.item.word.imageURL,
            kind: self.item.word.imageKind,
            framing: .whole
        )
    }

    /// Gloss only. `reading` and `pronunciation` are both on the payload and
    /// neither may come here: a kana headword's 振假名 is itself, and an IPA
    /// line is the word read aloud — either one turns the hint into a skip.
    private var hintFace: some View {
        Text(self.item.word.chinese)
            .font(.tujiH2)
            .foregroundStyle(.tujiInk)
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, Space.s5)
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
