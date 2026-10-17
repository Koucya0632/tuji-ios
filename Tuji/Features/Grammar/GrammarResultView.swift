import SwiftUI

/// One titled block of a grammar card, on the paper-2 ground the 查詞 cards use.
struct GrammarSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(self.title).font(.tujiH3).accessibilityAddTraits(.isHeader)
            self.content
        }
        // Sections are read in full: a squeezed one would cut the reasons to a line.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3).background(.tujiPaper2)
    }
}

/// An example sentence: the target language, its reading, the translation and what it shows.
struct GrammarLineView: View {
    let line: GrammarLine
    let target: TargetLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                Text(verbatim: self.line.text).font(.tujiBody)
                Spacer(minLength: Space.s2)
                PronunciationButton(subject: .sentence(self.line.text, language: self.target), ground: .tujiPaper)
            }
            if let reading = self.line.reading {
                Text(verbatim: reading).font(.tujiLabel).foregroundStyle(.tujiInk3)
            }
            if let translation = self.line.translation {
                Text(verbatim: translation).font(.tujiBodySm).foregroundStyle(.tujiInk2)
            }
            if let note = self.line.note { Text(verbatim: note).font(.tujiLabel).foregroundStyle(.tujiInk2) }
        }
    }
}

/// 語法解釋: 語法摘要, 結構拆解, 規則說明, 典型例句, 使用場景.
struct GrammarExplanationView: View {
    let value: GrammarExplanation
    let target: TargetLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            self.summary
            GrammarSection(title: "結構拆解") {
                Text(verbatim: self.value.structure.formula)
                    .font(.tujiBody(.strong))
                    .padding(Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.tujiPaper)
                ForEach(Array(self.value.structure.parts.enumerated()), id: \.offset) { _, part in
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(verbatim: part.part).font(.tujiBodySm(.strong))
                        Text(verbatim: part.role).font(.tujiBodySm)
                    }
                }
                if let breakdown = self.value.structure.breakdown {
                    self.labelled("套回原句", breakdown)
                }
                if let forms = self.value.structure.forms {
                    self.labelled("詞形變化", forms)
                }
            }
            GrammarSection(title: "規則說明") {
                ForEach(Array(self.value.rules.enumerated()), id: \.offset) { index, rule in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text(verbatim: "\(index + 1).").font(.tujiBody(.strong))
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text(verbatim: rule.title).font(.tujiBody(.strong))
                            Text(verbatim: rule.explanation).font(.tujiBodySm)
                        }
                    }
                }
            }
            GrammarSection(title: "典型例句") {
                ForEach(Array(self.value.examples.enumerated()), id: \.offset) { _, line in
                    GrammarLineView(line: line, target: self.target)
                }
            }
            GrammarSection(title: "使用場景") {
                ForEach(Array(self.value.scenes.enumerated()), id: \.offset) { _, scene in
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(verbatim: scene.situation).font(.tujiBody(.strong))
                        Label { Text(verbatim: scene.use) } icon: { Image(systemName: "checkmark") }
                            .font(.tujiBodySm)
                        if let avoid = scene.avoid {
                            Label { Text(verbatim: avoid) } icon: { Image(systemName: "xmark") }
                                .font(.tujiBodySm).foregroundStyle(.tujiInk2)
                        }
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(verbatim: self.value.summary.name).font(.tujiH2)
            Text(verbatim: self.value.summary.meaning).font(.tujiBody(.strong))
            Text(verbatim: self.value.summary.explanation).font(.tujiBody)
                .fixedSize(horizontal: false, vertical: true)
            if let highlight = self.value.summary.highlight {
                Text("本次分析：\(highlight)")
                    .font(.tujiLabel)
                    .padding(.horizontal, Space.s2).padding(.vertical, Space.s1)
                    .background(.tujiCurrent)
            }
        }
    }

    private func labelled(_ title: LocalizedStringKey, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title).font(.tujiLabel).foregroundStyle(.tujiInk3)
            Text(verbatim: text).font(.tujiBodySm)
        }
    }
}

/// 近似語法: 比較摘要, 近義對比, 異同辨析, 誤用預警, 替換建議. A over B, never a wide
/// table: a phone reads the two sides one under the other.
struct GrammarComparisonView: View {
    let value: GrammarComparison
    let target: TargetLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s2) {
                self.pair(self.value.a.name, self.value.b.name).font(.tujiH2)
                Text(verbatim: self.value.summary).font(.tujiBody)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = self.value.chosenBecause {
                    Text("為什麼比較 \(self.value.b.name)：\(reason)").font(.tujiLabel).foregroundStyle(.tujiInk2)
                }
            }
            GrammarSection(title: "近義對比") {
                Text(verbatim: self.value.similarity.shared).font(.tujiBody)
                self.side("A", self.value.a.name, self.value.similarity.aFocus)
                self.side("B", self.value.b.name, self.value.similarity.bFocus)
                self.verdict(self.value.similarity.interchangeable)
            }
            GrammarSection(title: "異同辨析") {
                ForEach(Array(self.value.dimensions.enumerated()), id: \.offset) { _, dimension in
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(verbatim: dimension.aspect).font(.tujiBody(.strong))
                        self.side("A", nil, dimension.a)
                        self.side("B", nil, dimension.b)
                    }
                }
            }
            GrammarSection(title: "誤用預警") {
                ForEach(Array(self.value.pitfalls.enumerated()), id: \.offset) { _, pitfall in
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(pitfall.kind.title).font(.tujiLabel)
                            .padding(.horizontal, Space.s1)
                            .overlay(Rectangle().stroke(Color.tujiInk3, lineWidth: 1))
                        Label { Text(verbatim: pitfall.wrong).strikethrough() } icon: { Image(systemName: "xmark") }
                            .font(.tujiBody).foregroundStyle(.tujiInk2)
                            .accessibilityLabel(Text("誤用：\(pitfall.wrong)"))
                        Label { Text(verbatim: pitfall.fixed) } icon: { Image(systemName: "checkmark") }
                            .font(.tujiBody(.strong))
                            .accessibilityLabel(Text("修正：\(pitfall.fixed)"))
                        Text(verbatim: pitfall.reason).font(.tujiBodySm)
                    }
                }
            }
            GrammarSection(title: "替換建議") {
                ForEach(Array(self.value.substitutions.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text(verbatim: item.situation).font(.tujiBody(.strong))
                        self.tagged("A", GrammarLineView(line: item.a, target: self.target))
                        self.tagged("B", GrammarLineView(line: item.b, target: self.target))
                        self.verdict(item.verdict)
                        Text(verbatim: item.explanation).font(.tujiBodySm)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    private func pair(_ a: String, _ b: String) -> some View {
        Text(verbatim: "\(a) ／ \(b)")
    }

    private func side(_ tag: String, _ name: String?, _ text: String) -> some View {
        self.tagged(tag, VStack(alignment: .leading, spacing: Space.s1) {
            if let name { Text(verbatim: name).font(.tujiBodySm(.strong)) }
            Text(verbatim: text).font(.tujiBodySm)
        })
    }

    private func tagged(_ tag: String, _ content: some View) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Text(verbatim: tag).font(.tujiLabel)
                .frame(width: 22, height: 22)
                .background(.tujiPaper)
                .accessibilityHidden(true)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func verdict(_ verdict: GrammarVerdict) -> some View {
        Label { Text(verdict.title) } icon: { Image(systemName: verdict.symbol) }
            .font(.tujiBodySm(.strong))
            .padding(.horizontal, Space.s2).padding(.vertical, Space.s1)
            .background(verdict == .interchangeable ? Color.tujiCurrent : .tujiPaper)
    }
}
