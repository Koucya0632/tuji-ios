// 詞塊卡片 — what a tapped 詞塊 in an example sentence raises.
//
// An overlay, not a `.sheet`, and that is the whole reason it has this shape:
// one of the three screens that show example sentences *is* a sheet
// (`WordPeekSheet`'s inline detail, reached by dragging up after a wrong
// answer), so a sheet here would be a sheet over a sheet — burying the sentence
// the user was reading behind two layers of chrome. An overlay behaves the same
// wherever it is hosted, so all three screens get one implementation and one
// behaviour.
//
// The cost is everything `.sheet` gives away for free. The scrim,
// tap-outside-to-dismiss, drag-to-dismiss and the modal accessibility contract
// are all hand-built below; none of them is optional.
//
// The card is bottom-anchored and fixed. It cannot point at the word, because
// `InteractiveSentenceText` hands its layout to SwiftUI's own text engine and
// so never learns where a run landed — the trade that buys correct wrapping,
// Dynamic Type and Japanese line breaking.

import SwiftUI

/// Which 詞塊 one screen is currently showing, and the language to speak it in.
///
/// Screen-scoped rather than app-scoped: two screens are never showing a card
/// at once, and a card outliving the screen that raised it is a bug, not a
/// feature. `GlossCardHost` owns the instance; nothing else constructs one.
@MainActor
@Observable
final class GlossSelection {
    private(set) var span: GlossSpan?
    /// The sentence's language, for `PronunciationButton`'s voice. Carried
    /// here rather than re-derived in the card, because the card sees a 詞塊
    /// and a 詞塊 is a fragment — `look forward to` has no `taggedLanguage` of
    /// its own to resolve against.
    private(set) var language: TargetLanguage = .en

    func select(_ span: GlossSpan, language: TargetLanguage) {
        guard span.isTappable else { return }
        self.span = span
        self.language = language
    }

    func clear() {
        self.span = nil
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
    /// the scroll view's bounds.
    ///
    /// Same shape as `.imageIntake(_:title:)` and
    /// `.refreshesFinishedSession(draining:)`: a screen-level modifier that
    /// owns a whole interaction, so a screen opts in with one line and states
    /// nothing about how it works.
    func glossCard() -> some View {
        modifier(GlossCardHost())
    }
}

private struct GlossCardHost: ViewModifier {
    @State private var selection = GlossSelection()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.glossSelection, self.selection)
            .overlay {
                if let span = self.selection.span {
                    ZStack(alignment: .bottom) {
                        // Swallows the tap that would otherwise reach the
                        // sentence underneath and immediately raise another
                        // card.
                        Color.tujiScrim
                            .ignoresSafeArea()
                            .onTapGesture { self.selection.clear() }
                            .accessibilityHidden(true)
                        GlossCard(
                            span: span,
                            language: self.selection.language,
                            onDismiss: { self.selection.clear() }
                        )
                    }
                    // Without this VoiceOver keeps reading the page behind the
                    // card, which for a modal reads as "nothing happened".
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape) { self.selection.clear() }
                    .transition(.opacity)
                }
            }
            .animation(Motion.ease(Motion.d2, reduceMotion: self.reduceMotion), value: self.selection.span)
    }
}

struct GlossCard: View {
    let span: GlossSpan
    let language: TargetLanguage
    let onDismiss: () -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(TabNavigator.self) private var navigator

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            self.grabber
            self.headerRow
            if let gloss = self.span.gloss, !gloss.isEmpty {
                Text(gloss)
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !self.metaItems.isEmpty {
                self.metaRow
            }
            if let wordId = self.span.wordId {
                BBtn(
                    title: "看完整詳情",
                    bg: .tujiBrandPrimary,
                    fg: .tujiInk,
                    fullWidth: true,
                    icon: "arrow.right"
                ) {
                    // The card is going away either way; push first so the
                    // dismissal animation runs behind the navigation rather
                    // than racing it.
                    self.navigator.push(.wordDetail(id: wordId))
                    self.onDismiss()
                }
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.bottom, Space.s4)
        .padding(.top, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiPaper)
        .overlay(alignment: .top) {
            Rectangle().fill(.tujiRule).frame(height: 1)
        }
        .offset(y: max(0, self.dragOffset))
        .gesture(
            DragGesture()
                .onChanged { self.dragOffset = $0.translation.height }
                .onEnded { value in
                    if value.translation.height > 60 {
                        self.onDismiss()
                    }
                    self.dragOffset = 0
                }
        )
    }

    // MARK: - Bits

    private var grabber: some View {
        Rectangle()
            .fill(.tujiRule)
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(self.span.text)
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
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
                size: 40
            )
        }
    }

    /// 原形 and 詞性, as label/value pairs. Assembled rather than rendered
    /// inline so the row can be skipped entirely when a span has neither —
    /// an empty rule-bounded strip reads as a rendering fault.
    private var metaItems: [(label: LocalizedStringKey, value: String)] {
        var items: [(LocalizedStringKey, String)] = []
        // A base form identical to the span teaches nothing; the whole point of
        // showing it is the `running` → `run` step.
        if let baseForm = self.span.baseForm, !baseForm.isEmpty, baseForm != self.span.text {
            items.append(("原形", baseForm))
        }
        if let pos = self.span.partOfSpeech, !pos.isEmpty {
            items.append(("詞性", localizedPartOfSpeech(pos, language: self.settings.current.uiLanguage)))
        }
        return items
    }

    private var metaRow: some View {
        HStack(spacing: Space.s4) {
            ForEach(Array(self.metaItems.enumerated()), id: \.offset) { _, item in
                HStack(spacing: Space.s2) {
                    Text(item.label)
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                    Text(item.value)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk2)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    VStack {
        Spacer()
        GlossCard(
            span: GlossSpan(
                text: "looking forward to",
                gloss: "期待、盼望（後面接名詞或動名詞）",
                baseForm: "look forward to",
                partOfSpeech: "phrasal verb",
                reading: nil,
                wordId: nil
            ),
            language: .en,
            onDismiss: {}
        )
    }
    .background(.tujiPaper2)
    .environment(SettingsStore.shared)
    .environment(TabNavigator())
}
