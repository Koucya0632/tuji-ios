// An example sentence whose 實詞 and 片語 can be tapped.
//
// The sentence is handed to SwiftUI's own text engine as one `AttributedString`
// with a link per tappable 詞塊, rather than laid out as a row of per-token
// views. That choice buys correct line breaking, Dynamic Type, Japanese 禁則
// and text selection for free, and it keeps this a `Text` — which matters at
// the call site, because the examples card sets the sentence beside a
// `Spacer(minLength:)` and a custom `Layout` in that position negotiates for
// half the available width (a bug this project has shipped once, invisible to
// every solver test and visible only in a screenshot).
//
// It used to cost the card its aim. A link never reports where it landed, so
// the card a tap raised could only sit at the bottom of the screen, and the
// sentence kept no record of which word the user had just asked about.
// `Text.Layout` buys that back **without giving up any of the above**: the
// selected 詞塊 carries a custom attribute, and a `TextRenderer` reads that
// run's typographic bounds out of the layout SwiftUI has already computed.
// Nothing here lays out text; it only asks where the text went.
//
// The renderer is attached **only while this sentence holds the selection**.
// At that moment the card's scrim already covers the sentence, so whatever a
// custom renderer does to link hit-testing cannot matter; every other render
// in the app is the same plain `Text` it has always been.

import OSLog
import SwiftUI

struct InteractiveSentenceText: View {
    let sentence: String
    /// Straight off the payload. Unusable spans are the normal case, not an
    /// error — see `SentenceAnnotation`.
    let spans: [GlossSpan]?
    /// The sentence's language, for the voice the card will speak in.
    let language: TargetLanguage

    @Environment(\.glossSelection) private var selection

    /// Where this sentence sits inside the card host. Tracked from the moment
    /// it appears rather than at tap time, because the renderer reports a rect
    /// in the text's *own* space and something has to put it on the screen.
    @State private var origin: CGPoint = .zero

    /// Deliberately **not** `tuji://`, which is a registered deep-link scheme
    /// this app already routes in `TujiApp.onOpenURL`. A scheme nothing claims
    /// cannot escape this view: if the handler below ever fails to run, the tap
    /// does nothing instead of navigating somewhere.
    private static let scheme = "tuji-gloss"

    var body: some View {
        // No host means no card, and a live link with nowhere to deliver its
        // tap reads as a broken feature rather than an absent one.
        if let selection, let usable = SentenceAnnotation.spans(self.spans, for: self.sentence) {
            let selected = selection.selectedIndex(in: self.sentence)
            Self.text(usable, highlighting: selected)
                // SwiftUI tints links with the accent colour on top of whatever
                // the run says. 紙與墨 has no accent-coloured text.
                .tint(.tujiInk)
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == Self.scheme else { return .systemAction }
                    if let index = Self.spanIndex(in: url), usable.indices.contains(index) {
                        // Same weight as every other tap in this app.
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selection.select(
                            usable[index],
                            at: index,
                            in: self.sentence,
                            language: self.language
                        )
                    }
                    // Handled either way: a URL wearing our scheme must never
                    // reach the system, even when we cannot read it.
                    return .handled
                })
                .onGeometryChange(for: CGPoint.self) {
                    $0.frame(in: .named(GlossSelection.coordinateSpace)).origin
                } action: { self.origin = $0 }
                .modifier(GlossRunMeasure(
                    target: selected.map { GlossSelection.Target(sentence: self.sentence, index: $0) },
                    origin: self.origin,
                    selection: selection
                ))
        } else {
            Text(self.sentence)
                .modifier(UnhostedGlossWarning(
                    isUnhosted: self.selection == nil
                        && SentenceAnnotation.spans(self.spans, for: self.sentence) != nil
                ))
        }
    }

    /// One 詞塊's run. `index` is its position in the whole sentence and must
    /// stay that way through any splitting below — a link renumbered by the
    /// split would open the wrong word.
    private static func run(_ span: GlossSpan, at index: Int, highlighted: Bool) -> AttributedString {
        var run = AttributedString(span.text)
        if span.isTappable {
            run.link = URL(string: "\(Self.scheme)://span/\(index)")
            run.foregroundColor = .tujiInk
            // A dotted rule under a word is the dictionary's own gesture for
            // "there is more here", and unlike a colour change it survives
            // being read by someone who cannot distinguish the two inks.
            run.underlineStyle = Text.LineStyle(pattern: .dot, color: .tujiInk3)
        }
        if highlighted {
            // 螢光筆, not a fill: the ink underneath has to stay readable
            // through it, and it sits under the card's own scrim as well.
            run.backgroundColor = .tujiBrandPrimary.opacity(0.45)
        }
        return run
    }

    /// Not private, and not a method: which runs become links is the rule worth
    /// pinning, and a rule reachable only by rendering a view is a rule with no
    /// test. `InteractiveSentenceTextTests` reads the runs back out of this.
    static func attributed(_ spans: [GlossSpan], highlighting selected: Int? = nil) -> AttributedString {
        let parts = Self.split(spans, highlighting: selected)
        guard let marked = parts.selected else { return parts.before }
        return parts.before + marked + parts.after
    }

    /// The sentence split around the selected 詞塊.
    ///
    /// The split exists because the marked run has to be findable again in
    /// `Text.Layout`, and only a `Text` of its own can carry a mark that
    /// survives the trip — see `text(_:highlighting:)`.
    static func split(_ spans: [GlossSpan], highlighting selected: Int?) -> Split {
        var before = AttributedString()
        var marked: AttributedString?
        var after = AttributedString()
        for (index, span) in spans.enumerated() {
            let run = Self.run(span, at: index, highlighted: index == selected)
            if index == selected {
                marked = run
            } else if marked == nil {
                before.append(run)
            } else {
                after.append(run)
            }
        }
        return Split(before: before, selected: marked, after: after)
    }

    struct Split {
        let before: AttributedString
        /// nil when nothing is selected, and then `before` is the whole
        /// sentence — which is why it is the one piece that is never optional.
        let selected: AttributedString?
        let after: AttributedString
    }

    /// The sentence as SwiftUI will lay it out.
    ///
    /// Splicing the selected 詞塊 in as its own `Text` is not a style choice —
    /// it is the only way to find the run again. A custom `AttributedStringKey`
    /// set on the string **does not survive into `Text.Layout`** (the run comes
    /// back unmarked; checked on device, not assumed), while `Text`'s own
    /// `customAttribute` does. With nothing selected this is the same single
    /// `Text` the sentence has always been, so the splice only ever exists
    /// while the card is up and the scrim has already taken the taps.
    static func text(_ spans: [GlossSpan], highlighting selected: Int?) -> Text {
        let parts = Self.split(spans, highlighting: selected)
        guard let marked = parts.selected else { return Text(parts.before) }
        return Text(parts.before)
            + Text(marked).customAttribute(GlossRunMark())
            + Text(parts.after)
    }

    static func spanIndex(in url: URL) -> Int? {
        guard url.scheme == scheme else { return nil }
        return url.pathComponents.last.flatMap(Int.init)
    }
}

// MARK: - Measuring the selected 詞塊

/// Marks the one run a `GlossRunLocator` is looking for.
///
/// It carries nothing: the marked run's identity is already settled by the fact
/// that exactly one 詞塊 is ever spliced out, so being *findable* is the whole
/// job. `nonisolated` because text layout runs off the main actor — the same
/// rule `TourAnchorKey` records, and the one a Debug build will not enforce.
nonisolated struct GlossRunMark: TextAttribute {}

/// Reports where the marked run landed, in the text's own coordinate space.
///
/// It draws the layout exactly as SwiftUI would. Measuring is the whole job:
/// any drawing change made here would be a second, undeclared feature riding
/// on a type whose name promises only to look.
nonisolated struct GlossRunLocator: TextRenderer {
    let report: @Sendable (CGRect) -> Void

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var bounds: CGRect?
        for line in layout {
            for run in line where run[GlossRunMark.self] != nil {
                // A 詞塊 broken across a line end is two runs. The union is the
                // rect whose middle the caret should aim at — pointing at the
                // first half would put it under a word the reader did not tap.
                let rect = run.typographicBounds.rect
                bounds = bounds.map { $0.union(rect) } ?? rect
            }
            context.draw(line)
        }
        if let bounds { self.report(bounds) }
    }
}

/// Attaches the locator only while this sentence holds the selection.
private struct GlossRunMeasure: ViewModifier {
    let target: GlossSelection.Target?
    let origin: CGPoint
    let selection: GlossSelection

    func body(content: Content) -> some View {
        if let target {
            content.textRenderer(GlossRunLocator(report: { [selection, origin] rect in
                // `draw` runs inside a render pass, so this cannot touch state
                // directly. `report` drops anything that would not change the
                // anchor, which is what stops the hop from becoming a loop.
                Task { @MainActor in
                    selection.report(
                        anchor: rect.offsetBy(dx: origin.x, dy: origin.y),
                        for: target
                    )
                }
            }))
        } else {
            content
        }
    }
}

#Preview {
    let spans = [
        GlossSpan(text: "I ", gloss: nil, baseForm: nil, partOfSpeech: nil, reading: nil, wordId: nil),
        GlossSpan(
            text: "look forward to",
            gloss: "期待、盼望",
            baseForm: "look forward to",
            partOfSpeech: "phrasal verb",
            reading: nil,
            wordId: nil
        ),
        GlossSpan(text: " the ", gloss: nil, baseForm: nil, partOfSpeech: nil, reading: nil, wordId: nil),
        GlossSpan(
            text: "weekend",
            gloss: "週末",
            baseForm: nil,
            partOfSpeech: "noun",
            reading: nil,
            wordId: "weekend"
        ),
        GlossSpan(text: ".", gloss: nil, baseForm: nil, partOfSpeech: nil, reading: nil, wordId: nil)
    ]
    return VStack {
        InteractiveSentenceText(
            sentence: "I look forward to the weekend.",
            spans: spans,
            language: .en
        )
        .font(.tujiBody)
        .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.tujiPaper)
    .glossCard()
    .environment(SettingsStore.shared)
    .environment(TabNavigator())
    .environment(LocalCache.shared)
    .environment(AuthService.shared)
}

/// Says so, loudly, when a sentence with usable 詞塊 renders with nobody to
/// deliver a tap to.
///
/// The plain-text fallback is correct — it is what the feature looked like
/// before it existed — but it is *silent*: a screen that forgot `.glossCard()`
/// looks exactly like a screen the feature was never meant to reach, so nobody
/// reports it. It has been missed three times, and the second one had live
/// annotated data sitting under dead text for weeks.
///
/// `scripts/check-gloss-host.py` catches it in CI without anyone opening the
/// screen, which is why it stays. What it cannot do is see a *render*: it
/// matches text at file level, so a host applied to the wrong subview passes,
/// and its `HOSTED_BY_CALLER` list is three files it never checks at all. This
/// half answers the question where it is actually asked.
///
/// DEBUG only, and deliberately **not** an `assertionFailure`: a trap here would
/// take the simulator down over a rendering fault, and — because a crashed test
/// process still prints ✔ and only shrinks the total — it would be the one kind
/// of failure this repo has learned to distrust. A red rule under the sentence
/// is unmissable and costs nothing. In a shipping build an unhosted sentence
/// stays exactly what it is today: plain text, the failure mode this feature
/// chose.
private struct UnhostedGlossWarning: ViewModifier {
    let isUnhosted: Bool

    func body(content: Content) -> some View {
        #if DEBUG
        content
            .overlay(alignment: .bottomLeading) {
                if self.isUnhosted {
                    Rectangle()
                        .fill(.tujiAlert)
                        .frame(height: Border.bw2)
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard self.isUnhosted else { return }
                Logger(subsystem: "app.tuji.ios", category: "gloss")
                    .error("""
                    an example sentence with usable 詞塊 rendered with no \
                    .glossCard() host — the taps have nowhere to go. Add one to \
                    this screen's root, outside whatever shell draws its title bar.
                    """)
            }
        #else
        content
        #endif
    }
}
