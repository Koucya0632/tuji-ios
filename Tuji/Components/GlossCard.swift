// 詞塊卡片 — what a tapped 詞塊 in an example sentence raises.
//
// An overlay, not a `.sheet`, and that is the whole reason it has this shape:
// one of the screens that show example sentences *is* a sheet
// (`WordPeekSheet`'s inline detail, reached by dragging up after a wrong
// answer), so a sheet here would be a sheet over a sheet — burying the sentence
// the user was reading behind two layers of chrome. An overlay behaves the same
// wherever it is hosted, so all of them get one implementation and one
// behaviour.
//
// The cost is everything `.sheet` gives away for free. The scrim,
// tap-outside-to-dismiss and the modal accessibility contract are all
// hand-built below; none of them is optional.
//
// **The card points at the word.** It used to be pinned to the bottom of the
// screen, because `InteractiveSentenceText` hands its layout to SwiftUI's own
// text engine and a link never reports where it landed. `Text.Layout` reports
// it without taking that layout back, so the card now floats beside the 詞塊
// with a caret aimed at it and the word itself carries a 螢光筆.
//
// One invariant holds the whole thing up: **no anchor, no caret.** When the
// selected run cannot be measured, or the card fits neither above nor below the
// word, the card falls back to sitting at the bottom with no caret at all —
// which is exactly what this feature looked like before. Same shape of rule as
// `SentenceAnnotation`: the failure mode is the previous version, never a
// caret pointing at the wrong word.

import SwiftUI

/// Which 詞塊 one screen is currently showing, where it is, and the language to
/// speak it in.
///
/// Screen-scoped rather than app-scoped: two screens are never showing a card
/// at once, and a card outliving the screen that raised it is a bug, not a
/// feature. `GlossCardHost` owns the instance; nothing else constructs one.
@MainActor
@Observable
final class GlossSelection {
    /// Which 詞塊 of which sentence.
    ///
    /// The sentence's own text is the identity. A screen shows a 譯義 and up to
    /// three examples and those are never the same string, so an id threaded
    /// through every call site would buy nothing; two genuinely identical
    /// sentences would simply both light up, which looks odd rather than wrong.
    nonisolated struct Target: Equatable, Hashable {
        let sentence: String
        let index: Int
    }

    /// The space every anchor is expressed in. `.glossCard()` names it; the
    /// sentences inside report into it.
    nonisolated static let coordinateSpace = "tuji.glossCard"

    private(set) var span: GlossSpan?
    private(set) var target: Target?
    /// The sentence's language, for `PronunciationButton`'s voice. Carried
    /// here rather than re-derived in the card, because the card sees a 詞塊
    /// and a 詞塊 is a fragment — `look forward to` has no `taggedLanguage` of
    /// its own to resolve against.
    private(set) var language: TargetLanguage = .en
    /// Where the selected 詞塊 landed, in `coordinateSpace`. nil until the
    /// renderer reports — and **stays** nil when nothing can report, which is
    /// what keeps the bottom-anchored fallback a live path rather than dead code.
    private(set) var anchor: CGRect?

    func select(_ span: GlossSpan, at index: Int, in sentence: String, language: TargetLanguage) {
        guard span.isTappable else { return }
        self.span = span
        self.target = Target(sentence: sentence, index: index)
        self.language = language
        // The previous word's anchor would otherwise aim this card at it for
        // the one frame before the new measurement lands.
        self.anchor = nil
    }

    /// Which 詞塊 of `sentence` is selected, if any — the sentence asks this to
    /// decide what to highlight and what to measure.
    func selectedIndex(in sentence: String) -> Int? {
        guard let target = self.target, target.sentence == sentence else { return nil }
        return target.index
    }

    /// Records where the selected 詞塊 landed.
    ///
    /// Refusing a report for anything but the live target is not defensive
    /// tidiness: a sentence that draws one frame late would otherwise point the
    /// caret at the word the user tapped *before* this one. Refusing an
    /// unchanged rect is what stops the render → report → render loop, since
    /// the renderer runs on every draw.
    func report(anchor: CGRect, for target: Target) {
        guard self.target == target, self.anchor != anchor else { return }
        self.anchor = anchor
    }

    func clear() {
        self.span = nil
        self.target = nil
        self.anchor = nil
    }
}

extension EnvironmentValues {
    /// nil until a screen hosts a card. `InteractiveSentenceText` reads it to
    /// decide whether to make anything tappable at all: a live link with
    /// nowhere to deliver its tap is worse than plain text, because it looks
    /// like the feature is broken rather than absent.
    @Entry var glossSelection: GlossSelection?
}

extension View {
    /// Hosts the 詞塊 card for one screen.
    ///
    /// Belongs on the **screen root**, not on the sentence and not inside the
    /// `ScrollView` — the card is an overlay on whatever it is attached to, so
    /// hosted deeper it would scroll away with the content and be clipped by
    /// the scroll view's bounds. It also names the coordinate space every
    /// anchor is measured in, which is a second reason the same rule holds:
    /// hosted deeper, the space would move under the card.
    ///
    /// Same shape as `.imageIntake(_:title:)` and
    /// `.refreshesFinishedSession(draining:)`: a screen-level modifier that
    /// owns a whole interaction, so a screen opts in with one line and states
    /// nothing about how it works.
    func glossCard() -> some View {
        modifier(GlossCardHost())
    }
}

// MARK: - Host

private struct GlossCardHost: ViewModifier {
    @State private var selection = GlossSelection()
    /// Last measured card. Kept across selections on purpose: a stale size is a
    /// better first guess than none, and the card is invisible until it has one.
    @State private var cardSize: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.glossSelection, self.selection)
            .coordinateSpace(.named(GlossSelection.coordinateSpace))
            // The half of the modal contract the scrim cannot cover: it
            // swallows taps, but VoiceOver reads straight past one. Deliberately
            // not `.allowsHitTesting(false)` beside it — that would sit *above*
            // the overlay in this chain, where whether it also disables the
            // card's own buttons is not a question the scrim leaves worth
            // risking.
            .accessibilityHidden(self.selection.span != nil)
            .overlay {
                if let span = self.selection.span {
                    self.card(for: span)
                        // Without this VoiceOver keeps reading the page behind
                        // the card, which for a modal reads as "nothing happened".
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape) { self.selection.clear() }
                        .transition(.opacity)
                }
            }
            .animation(Motion.ease(Motion.d2, reduceMotion: self.reduceMotion), value: self.selection.span)
    }

    private func card(for span: GlossSpan) -> some View {
        ZStack {
            // Swallows the tap that would otherwise reach the sentence
            // underneath and immediately raise another card. Outside the reader
            // because it needs no geometry — the reader's only job is placing
            // the card, and a scrim that ignores the safe area inside a reader
            // that must not is two rules fighting over one view.
            Color.tujiScrim
                .ignoresSafeArea()
                .onTapGesture { self.selection.clear() }
                .accessibilityHidden(true)
            // Not `.ignoresSafeArea()` on the reader: its local space has to
            // stay the named space the anchors were measured in.
            GeometryReader { proxy in
                let placement = self.selection.anchor.flatMap {
                    GlossCalloutPlacement.place(anchor: $0, cardSize: self.cardSize, container: proxy.size)
                }
                GlossCard(
                    span: span,
                    language: self.selection.language,
                    callout: placement,
                    onDismiss: { self.selection.clear() }
                )
                .frame(width: GlossCalloutPlacement.cardWidth(in: proxy.size))
                .onGeometryChange(for: CGSize.self) { $0.size } action: { self.cardSize = $0 }
                // One unmeasured frame exists between raising the card and
                // knowing where it goes. Showing it there would be a visible
                // jump; the fade-in covers it entirely.
                .opacity(self.cardSize == .zero ? 0 : 1)
                .offset(
                    x: GlossCalloutPlacement.sideMargin,
                    y: placement?.top
                        ?? (proxy.size.height - self.cardSize.height - GlossCalloutPlacement.edgeMargin)
                )
            }
        }
    }
}

// MARK: - Card

struct GlossCard: View {
    let span: GlossSpan
    let language: TargetLanguage
    /// nil ⇒ no caret and no aim; the host is parking the card at the bottom.
    let callout: GlossCalloutPlacement.Result?
    let onDismiss: () -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(TabNavigator.self) private var navigator

    /// Reserved on the bottom when there is no caret, so the measured height
    /// never depends on which way the caret points.
    private var caretEdge: Edge.Set {
        (self.callout?.pointsDown ?? true) ? .bottom : .top
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            self.headerRow
            self.definitionLine
                .fixedSize(horizontal: false, vertical: true)
            if let baseForm = self.baseForm {
                self.baseFormRow(baseForm)
            }
            if let wordId = self.span.wordId {
                self.detailAction(wordId)
            }
        }
        .padding(Space.s3)
        .padding(self.caretEdge, GlossCalloutPlacement.caretSize.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = GlossCalloutShape(caret: self.callout.map {
                GlossCalloutShape.Caret(x: $0.caretX, pointsDown: $0.pointsDown)
            })
            shape.fill(.tujiPaper)
            shape.stroke(.tujiRule, lineWidth: Border.bw1)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Bits

    private var headerRow: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(self.span.text)
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)
                    .fixedSize(horizontal: false, vertical: true)
                // Same rule the headwords use: a kana span is its own reading,
                // and printing it under itself says nothing.
                if let reading = ReadingLine.shown(self.span.reading, for: self.span.text) {
                    Text(reading)
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: Space.s2)
            PronunciationButton(
                text: self.span.text,
                language: self.language,
                size: Self.buttonSize
            )
            // 書籤 needs a catalogue word to hang on, and most 詞塊 will never be
            // one. `unlinkSelfReference` also strips the id from a span that
            // points at the page you are already reading, so this key keeps the
            // same company as 看完整詳情: both or neither.
            if let wordId = self.span.wordId {
                FavoriteButton(wordId: wordId, size: Self.buttonSize)
            }
        }
    }

    private static let buttonSize: CGFloat = 32

    /// 詞性 and 釋義 as one paragraph rather than a labelled row and a body
    /// block. They are read as one sentence — "名詞, meaning …" — and setting
    /// them as one `Text` also lets them wrap as one.
    private var definitionLine: Text {
        let gloss = Text(self.span.gloss ?? "")
            .font(.tujiBody)
            .foregroundStyle(.tujiInk)
        guard let pos = self.span.partOfSpeech, !pos.isEmpty else { return gloss }
        return Text(localizedPartOfSpeech(pos, language: self.settings.current.uiLanguage))
            .font(.tujiLabel)
            .italic()
            .foregroundStyle(.tujiInk3)
            + Text(verbatim: "  ")
            + gloss
    }

    /// A base form identical to the span teaches nothing; the whole point of
    /// showing it is the `running` → `run` step.
    private var baseForm: String? {
        guard let baseForm = self.span.baseForm, !baseForm.isEmpty, baseForm != self.span.text else {
            return nil
        }
        return baseForm
    }

    private func baseFormRow(_ baseForm: String) -> some View {
        HStack(spacing: Space.s2) {
            Text("原形")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
            Text(baseForm)
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk2)
            Spacer(minLength: 0)
        }
    }

    /// A row rather than the full-width button it used to be. The card now has
    /// to fit in the gap above a word, and a button that tall would push it
    /// back to the bottom of the screen on most sentences — which is the one
    /// thing this change exists to stop.
    private func detailAction(_ wordId: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Rectangle()
                .fill(.tujiRule)
                .frame(height: Border.bw1)
            Button {
                // The card is going away either way; push first so the
                // dismissal animation runs behind the navigation rather
                // than racing it.
                self.navigator.push(.wordDetail(id: wordId))
                self.onDismiss()
            } label: {
                HStack(spacing: Space.s2) {
                    Text("看完整詳情")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk)
                    Image(systemName: "arrow.right")
                        .font(.tujiIcon(12, weight: .semibold))
                        .foregroundStyle(.tujiInk2)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Space.s1)
    }
}

#Preview {
    VStack {
        GlossCard(
            span: GlossSpan(
                text: "looking forward to",
                gloss: "期待、盼望（後面接名詞或動名詞）",
                baseForm: "look forward to",
                partOfSpeech: "phrasal verb",
                reading: nil,
                wordId: "weekend"
            ),
            language: .en,
            callout: GlossCalloutPlacement.Result(top: 0, caretX: 80, pointsDown: true),
            onDismiss: {}
        )
        .padding(.horizontal, GlossCalloutPlacement.sideMargin)
        GlossCard(
            span: GlossSpan(
                text: "weekend",
                gloss: "週末",
                baseForm: nil,
                partOfSpeech: "noun",
                reading: nil,
                wordId: nil
            ),
            language: .en,
            callout: nil,
            onDismiss: {}
        )
        .padding(.horizontal, GlossCalloutPlacement.sideMargin)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.tujiPaper2)
    .environment(SettingsStore.shared)
    .environment(TabNavigator())
    .environment(LocalCache.shared)
    .environment(AuthService.shared)
}
