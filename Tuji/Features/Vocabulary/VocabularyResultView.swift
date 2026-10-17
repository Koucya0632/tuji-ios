import SwiftUI

struct VocabularyResultView: View {
    let content: VocabularyContent
    let target: TargetLanguage
    var choose: (VocabularyCandidate, VocabularyMode) -> Void
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            switch self.content {
            case let .lookup(value): self.lookup(value)
            case let .analysis(value):
                self.headword(value.headword)
                self.analysis(value)
            case let .mnemonic(value):
                self.headword(value.headword)
                self.mnemonic(value)
            }
        }
        .textSelection(.enabled)
    }

    private func headword(_ value: VocabularyHeadword) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                Text(verbatim: value.text).font(.tujiH2)
                Spacer()
                PronunciationButton(subject: .headword(value.text, language: self.target))
            }
            if let reading = value.reading { Text(verbatim: reading).font(.tujiBodySm).foregroundStyle(.tujiInk2) }
            Text(verbatim: value.partOfSpeech).font(.tujiLabel).foregroundStyle(.tujiInk3)
            Text(verbatim: value.meaning).font(.tujiBody)
        }
    }

    private func section(_ title: String, index: Int, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title).font(.tujiH3).accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3).background(.tujiPaper2)
        .id("vocabulary-section-\(index)")
    }

    private func line(_ value: VocabularyLine) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                Text(verbatim: value.text).font(.tujiBody)
                Spacer(minLength: Space.s2)
                PronunciationButton(subject: .sentence(value.text, language: self.target), ground: .tujiPaper)
            }
            if let reading = value.reading { Text(verbatim: reading).font(.tujiLabel).foregroundStyle(.tujiInk3) }
            if let translation = value
                .translation { Text(verbatim: translation).font(.tujiBodySm).foregroundStyle(.tujiInk2) }
            if let note = value.note { Text(verbatim: note).font(.tujiLabel).foregroundStyle(.tujiInk2) }
        }
    }

    private func nextSteps(_ candidate: VocabularyCandidate) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s3) { self.nextButtons(candidate) }
            VStack(alignment: .leading, spacing: Space.s3) { self.nextButtons(candidate) }
        }
        .font(.tujiBodySm(.strong))
    }

    @ViewBuilder
    private func nextButtons(_ candidate: VocabularyCandidate) -> some View {
        Button("深入解析") { self.choose(candidate, .analysis) }.frame(minHeight: 44)
        Button("幫我記住") { self.choose(candidate, .mnemonic) }.frame(minHeight: 44)
    }

    @ViewBuilder
    private func lookup(_ value: VocabularyLookup) -> some View {
        self.section(tujiLocalized("詞義速查"), index: 0) { self.headword(value.headword) }
        self.section(tujiLocalized("釋義詳解"), index: 1) {
            ForEach(Array(value.senses.enumerated()), id: \.offset) { _, sense in
                VStack(alignment: .leading, spacing: Space.s2) {
                    if sense.relevant { Text("目前相關詞義").font(.tujiLabel).foregroundStyle(.tujiInk3) }
                    Text(verbatim: sense.term).font(.tujiBody(.strong))
                    Text(verbatim: sense.meaning).font(.tujiBody)
                    Text(verbatim: sense.explanation).font(.tujiBodySm)
                    self.nextSteps(VocabularyCandidate(term: sense.term, meaning: sense.meaning))
                }
            }
        }
        self.section(tujiLocalized("常見表達"), index: 2) {
            ForEach(Array(value.expressions.enumerated()), id: \.offset) { _, example in self.line(example) }
        }
        self.section(tujiLocalized("相關詞彙"), index: 3) {
            if value.related.isEmpty { Text("沒有需要補充的內容。").font(.tujiBodySm) }
            ForEach(Array(value.related.enumerated()), id: \.offset) { _, item in
                Text(verbatim: item.term).font(.tujiBody(.strong))
                Text(verbatim: item.relation).font(.tujiBodySm)
            }
        }
    }

    @ViewBuilder
    private func analysis(_ value: VocabularyAnalysis) -> some View {
        self.section(tujiLocalized("近義詞辨析"), index: 0) {
            if value.comparisons.isEmpty { Text("沒有需要補充的內容。").font(.tujiBodySm) }
            ForEach(Array(value.comparisons.enumerated()), id: \.offset) { _, item in
                Text(verbatim: item.term).font(.tujiBody(.strong))
                Text(verbatim: item.difference).font(.tujiBody)
                Text(verbatim: item.whenToUse).font(.tujiBodySm)
                ForEach(Array(item.examples.enumerated()), id: \.offset) { _, example in self.line(example) }
            }
        }
        self.section(tujiLocalized("用法解析"), index: 1) {
            ForEach(Array(value.usage.enumerated()), id: \.offset) { _, item in
                Text(verbatim: item.title).font(.tujiBody(.strong))
                Text(verbatim: item.explanation).font(.tujiBodySm)
            }
        }
        self.section(tujiLocalized("自然例句"), index: 2) {
            ForEach(Array(value.examples.enumerated()), id: \.offset) { _, example in self.line(example) }
        }
        self.section(tujiLocalized("搭配拓展"), index: 3) {
            ForEach(Array(value.collocations.enumerated()), id: \.offset) { _, item in
                Text(verbatim: item.phrase).font(.tujiBody(.strong))
                Text(verbatim: item.meaning).font(.tujiBodySm)
                Text(verbatim: item.pattern).font(.tujiLabel).foregroundStyle(.tujiInk2)
            }
        }
        self.nextSteps(VocabularyCandidate(term: value.headword.text, meaning: value.headword.meaning))
    }

    @ViewBuilder
    private func mnemonic(_ value: VocabularyMnemonic) -> some View {
        self.section(tujiLocalized("聯想記憶"), index: 0) { Text(verbatim: value.association).font(.tujiBody) }
        self.section(tujiLocalized("小技巧"), index: 1) { Text(verbatim: value.technique).font(.tujiBody) }
        self.section(tujiLocalized("易複述"), index: 2) {
            Text(verbatim: value.retelling).font(.tujiBody(.strong))
            self.line(value.example)
        }
        self.section(tujiLocalized("背詞輔助"), index: 3) {
            Text(verbatim: value.quiz.question).font(.tujiBody)
            DisclosureGroup("給我提示") { Text(verbatim: value.quiz.hint).font(.tujiBodySm) }
            Button(self.revealed ? "隱藏答案" : "揭示答案") { self.revealed.toggle() }
                .font(.tujiBody(.strong)).frame(minHeight: 44)
            if self
                .revealed
            {
                Text(verbatim: value.quiz.answer).font(.tujiBody).accessibilityIdentifier("vocabulary-quiz-answer")
            }
        }
    }
}
