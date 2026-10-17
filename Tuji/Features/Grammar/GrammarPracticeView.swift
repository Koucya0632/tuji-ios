import SwiftUI

/// 語法練習 inside its card: one question at a time, the answer and reasons hidden
/// until 確認答案, and a review at the end. Nothing here spends points.
struct GrammarPracticeView: View {
    @State private var session: GrammarPracticeSession

    init(session: GrammarPracticeSession) {
        _session = State(initialValue: session)
    }

    private var practice: GrammarPractice {
        self.session.practice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(verbatim: self.practice.focus).font(.tujiH2)
                HStack(spacing: Space.s1) {
                    Text(self.practice.difficulty.title)
                    Text(verbatim: "·")
                    Text("\(self.practice.questions.count) 題")
                }
                .font(.tujiLabel).foregroundStyle(.tujiInk2)
            }
            switch self.session.screen {
            case .overview: self.overview
            case .question: self.questionScreen
            case .summary: self.summary
            case .review: self.review
            }
        }
        .accessibilityIdentifier("grammar-practice")
    }

    // MARK: - 開始

    private var overview: some View {
        GrammarSection(title: "語法練習") {
            if let attempt = self.session.unfinished {
                Text("已作答 \(attempt.answers.count)／\(attempt.questionIds.count) 題").font(.tujiBodySm)
            } else {
                Text("一次一題，確認答案後才會看到解析。").font(.tujiBodySm)
            }
            self.primary(self.session.unfinished == nil ? "開始練習" : "繼續練習") { self.session.start() }
                .accessibilityIdentifier("grammar-practice-start")
            self.secondary("查看題目與解析") { self.session.review() }
            if self.session.unfinished == nil, self.session.firstScore == nil {
                Text("先看解析的話，之後的作答會記為重做。").font(.tujiLabel).foregroundStyle(.tujiInk3)
            }
        }
    }

    // MARK: - 作答

    @ViewBuilder
    private var questionScreen: some View {
        if let question = self.session.question {
            let confirmed = self.session.confirmed
            GrammarSection(title: "\(self.positionTitle)") {
                Text(question.kind.title).font(.tujiLabel).foregroundStyle(.tujiInk3)
                if let context = question.context {
                    Text(verbatim: context).font(.tujiBodySm)
                        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.tujiPaper)
                }
                Text(verbatim: question.prompt).font(.tujiBody(.strong))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(question.options) { option in
                    self.option(option, question: question, confirmed: confirmed)
                }
                if let confirmed {
                    self.feedback(question, chosen: confirmed)
                    self.primary(self.isLast ? "看結果" : "下一題") { self.session.next() }
                        .accessibilityIdentifier("grammar-practice-next")
                } else {
                    self.primary("確認答案") { self.session.confirm() }
                        .disabled(self.session.selection == nil)
                        .opacity(self.session.selection == nil ? 0.5 : 1)
                        .accessibilityIdentifier("grammar-practice-confirm")
                }
            }
        }
    }

    private var positionTitle: String {
        guard let position = self.session.position else { return "" }
        let redo = self.session.attempt?.isFirst == false
        return redo ? tujiLocalized("重做 第 \(position.index)／\(position.total) 題") :
            tujiLocalized("第 \(position.index)／\(position.total) 題")
    }

    private var isLast: Bool {
        guard let attempt = self.session.attempt else { return true }
        return attempt.questionIds.allSatisfy { attempt.answers[$0] != nil }
    }

    private func option(
        _ option: GrammarPractice.Question.Option,
        question: GrammarPractice.Question,
        confirmed: String?
    )
        -> some View
    {
        let selected = (confirmed ?? self.session.selection) == option.id
        let isAnswer = option.id == question.answer
        // After checking, the right answer and a wrong pick each say so in words and a symbol, not colour alone.
        let mark: (symbol: String, label: LocalizedStringKey)? = confirmed == nil ? nil :
            isAnswer ? ("checkmark.circle.fill", "正確答案") : selected ? ("xmark.circle.fill", "你的答案") : nil
        return Button { self.session.select(option.id) } label: {
            HStack(alignment: .top, spacing: Space.s2) {
                Text(verbatim: option.id.uppercased()).font(.tujiBodySm(.strong)).frame(width: 20)
                Text(verbatim: option.text).font(.tujiBody)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let mark {
                    VStack(alignment: .trailing, spacing: 2) {
                        Image(systemName: mark.symbol)
                        Text(mark.label).font(.tujiLabel)
                    }
                }
            }
            .padding(Space.s3)
            .frame(minHeight: 44)
            .background(confirmed != nil && isAnswer ? Color.tujiCurrent : .tujiPaper)
            .overlay(Rectangle().stroke(selected ? Color.tujiInk : .tujiRule, lineWidth: selected ? 2 : 1))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Not .disabled: that greys out the very answer being explained.
        .allowsHitTesting(confirmed == nil)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("grammar-option-\(option.id)")
    }

    private func feedback(_ question: GrammarPractice.Question, chosen: String) -> some View {
        let right = chosen == question.answer
        return VStack(alignment: .leading, spacing: Space.s2) {
            let symbol = right ? "checkmark.circle" : "xmark.circle"
            Label(right ? "答對了" : "答錯了", systemImage: symbol)
                .font(.tujiBody(.strong))
                .accessibilityIdentifier("grammar-practice-verdict")
            Text(verbatim: question.solution).font(.tujiBody)
            ForEach(question.options) { option in
                if let reason = question.reason(for: option.id) {
                    HStack(alignment: .top, spacing: Space.s2) {
                        Text(verbatim: option.id.uppercased()).font(.tujiLabel.weight(.semibold)).frame(width: 20)
                        Text(verbatim: reason).font(.tujiBodySm)
                            .foregroundStyle(option.id == question.answer || option.id == chosen ? Color
                                .tujiInk : .tujiInk2)
                    }
                }
            }
            Text("學習重點：\(question.point)").font(.tujiBodySm(.strong))
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiPaper)
    }

    // MARK: - 結果

    private var summary: some View {
        GrammarSection(title: "練習結果") {
            if let score = self.session.firstScore {
                if score.answered < score.total {
                    Text("首次作答已答 \(score.answered)／\(score.total) 題").font(.tujiH3)
                } else {
                    Text("首次作答答對 \(score.correct)／\(score.total) 題").font(.tujiH3)
                        .accessibilityIdentifier("grammar-practice-score")
                }
            }
            if let attempt = self.session.attempt, !attempt.isFirst {
                Text("這次重做答對 \(self.session.correct(in: attempt))／\(attempt.questionIds.count) 題")
                    .font(.tujiBodySm)
            }
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("本組重點").font(.tujiLabel).foregroundStyle(.tujiInk3)
                ForEach(Array(self.practice.takeaways.enumerated()), id: \.offset) { _, line in
                    Label { Text(verbatim: line) } icon: { Image(systemName: "circle.fill").font(.tujiIcon(5)) }
                        .font(.tujiBodySm)
                }
            }
            if let attempt = self.session.attempt, !self.session.wrong(in: attempt).isEmpty {
                self.primary("重做錯題（\(self.session.wrong(in: attempt).count) 題）") { self.session.redoWrong() }
                    .accessibilityIdentifier("grammar-practice-redo-wrong")
            }
            self.secondary("重做這組") { self.session.redoAll() }
            self.secondary("查看題目與解析") { self.session.review() }
            Text("重做與查看解析都不會扣點。").font(.tujiLabel).foregroundStyle(.tujiInk3)
        }
    }

    // MARK: - 查看

    private var review: some View {
        GrammarSection(title: "題目與解析") {
            ForEach(Array(self.practice.questions.enumerated()), id: \.offset) { index, question in
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("第 \(index + 1) 題").font(.tujiLabel).foregroundStyle(.tujiInk3)
                    if let context = question.context { Text(verbatim: context).font(.tujiBodySm) }
                    Text(verbatim: question.prompt).font(.tujiBody(.strong))
                    ForEach(question.options) { option in
                        HStack(alignment: .top, spacing: Space.s2) {
                            Image(systemName: option.id == question.answer ? "checkmark.circle.fill" : "circle")
                                .accessibilityLabel(Text(option.id == question.answer ? "正確答案" : ""))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: option.text).font(.tujiBodySm(.strong))
                                if let reason = question.reason(for: option.id) {
                                    Text(verbatim: reason).font(.tujiLabel).foregroundStyle(.tujiInk2)
                                }
                            }
                        }
                    }
                    Text("學習重點：\(question.point)").font(.tujiBodySm)
                }
                .padding(.bottom, Space.s2)
            }
            self.primary(self.session.attempt?.finished == true ? "回到結果" : "回到練習") {
                self.session.showOverview()
            }
        }
    }

    // MARK: -

    private func primary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.tujiBody(.strong))
                .padding(.horizontal, Space.s4).frame(minHeight: 48)
                .background(.tujiCurrent)
        }
        .buttonStyle(.plain)
    }

    private func secondary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.tujiBodySm(.strong)).underline().frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}
