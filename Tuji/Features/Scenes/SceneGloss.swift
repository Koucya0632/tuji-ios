// 點詞翻譯: a Japanese line whose words can be tapped for their reading and
// meaning. It is offered only once the answer is out (after answering, and
// on 進店前看一眼) — before that it would give the answer away.

import SwiftUI

/// The line as one wrapping `Text`; each word with a meaning is a link that
/// sets `picked` instead of opening anything.
struct GlossedLine: View {
    let text: String
    let tokens: [GlossToken]?
    @Binding var picked: GlossToken?

    var body: some View {
        Text(self.attributed)
            .tint(.tujiInk)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "gloss", let index = Int(url.host() ?? ""),
                      let tokens = self.tokens, tokens.indices.contains(index)
                else { return .discarded }
                self.picked = tokens[index]
                return .handled
            })
    }

    private var attributed: AttributedString {
        guard let tokens = self.tokens else { return AttributedString(self.text) }
        var line = AttributedString()
        for (index, token) in tokens.enumerated() {
            var piece = AttributedString(token.t)
            if token.m != nil {
                piece.link = URL(string: "gloss://\(index)")
                piece.underlineStyle = Text.LineStyle(pattern: .dot, color: .tujiInk3)
            }
            line += piece
        }
        return line
    }
}

/// What a tapped word means.
private struct SceneGlossCard: View {
    let token: GlossToken
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(verbatim: self.token.t)
                .font(.scene(24))
                .foregroundStyle(.tujiInk)
            if let reading = self.token.r {
                Text(verbatim: reading)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk2)
            }
            if let meaning = self.token.m {
                Text(verbatim: meaning.resolved(self.settings.current.uiLanguage))
                    .font(.tujiBody(.strong))
                    .foregroundStyle(.tujiInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.s1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s4)
        .environment(\.locale, Locale(identifier: "ja"))
    }
}

extension View {
    /// Shows the word a `GlossedLine` picked.
    func glossSheet(_ picked: Binding<GlossToken?>) -> some View {
        self.tujiSheet(
            isPresented: Binding(get: { picked.wrappedValue != nil }, set: { if !$0 { picked.wrappedValue = nil } }),
            title: "這個詞",
            height: 240
        ) {
            if let token = picked.wrappedValue {
                SceneGlossCard(token: token)
            }
        }
    }
}
