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
// What it costs: a link never reports where it landed, so the card it raises
// cannot point at the word. See `GlossCard`.

import SwiftUI

struct InteractiveSentenceText: View {
    let sentence: String
    /// Straight off the payload. Unusable spans are the normal case, not an
    /// error — see `SentenceAnnotation`.
    let spans: [GlossSpan]?
    /// The sentence's language, for the voice the card will speak in.
    let language: TargetLanguage

    @Environment(\.glossSelection) private var selection

    /// Deliberately **not** `tuji://`, which is a registered deep-link scheme
    /// this app already routes in `TujiApp.onOpenURL`. A scheme nothing claims
    /// cannot escape this view: if the handler below ever fails to run, the tap
    /// does nothing instead of navigating somewhere.
    private static let scheme = "tuji-gloss"

    var body: some View {
        // No host means no card, and a live link with nowhere to deliver its
        // tap reads as a broken feature rather than an absent one.
        if let selection, let usable = SentenceAnnotation.spans(self.spans, for: self.sentence) {
            Text(Self.attributed(usable))
                // SwiftUI tints links with the accent colour on top of whatever
                // the run says. 紙與墨 has no accent-coloured text.
                .tint(.tujiInk)
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == Self.scheme else { return .systemAction }
                    if let index = Self.spanIndex(in: url), usable.indices.contains(index) {
                        // Same weight as every other tap in this app.
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selection.select(usable[index], language: self.language)
                    }
                    // Handled either way: a URL wearing our scheme must never
                    // reach the system, even when we cannot read it.
                    return .handled
                })
        } else {
            Text(self.sentence)
        }
    }

    /// Not private, and not a method: which runs become links is the rule worth
    /// pinning, and a rule reachable only by rendering a view is a rule with no
    /// test. `InteractiveSentenceTextTests` reads the runs back out of this.
    static func attributed(_ spans: [GlossSpan]) -> AttributedString {
        var result = AttributedString()
        for (index, span) in spans.enumerated() {
            var run = AttributedString(span.text)
            if span.isTappable {
                run.link = URL(string: "\(Self.scheme)://span/\(index)")
                run.foregroundColor = .tujiInk
                // A dotted rule under a word is the dictionary's own gesture for
                // "there is more here", and unlike a colour change it survives
                // being read by someone who cannot distinguish the two inks.
                run.underlineStyle = Text.LineStyle(pattern: .dot, color: .tujiInk3)
            }
            result.append(run)
        }
        return result
    }

    static func spanIndex(in url: URL) -> Int? {
        guard url.scheme == Self.scheme else { return nil }
        return url.pathComponents.last.flatMap(Int.init)
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
}
