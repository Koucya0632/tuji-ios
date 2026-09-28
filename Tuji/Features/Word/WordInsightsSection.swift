// 容易混淆・常見誤用・用法補充 under a word's details. Draws nothing until the
// server has something to say — under membership v1, for 自製 and 物見 words,
// and for the many words with no insight at all.
//
// A linked word opens the way this screen opens word details: pushed normally,
// as a sheet inside a study session. Pushing there pops the session — see
// `WordDetailPresentation`.

import SwiftUI

struct WordInsightsSection: View {
    let wordId: String

    @Environment(WordInsightsStore.self) private var store
    @Environment(WordsStore.self) private var words
    @Environment(TabNavigator.self) private var navigator
    @Environment(\.wordDetailPresentation) private var presentation
    @State private var sheetWordId: String?
    @State private var showPaywall = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Always drawn, so the `.task` below runs — see `TaskAnchor`.
            TaskAnchor()
            // Double optional: not asked yet, or asked and the word has none.
            if let answer = self.store.cached(for: self.wordId), let insights = answer, !insights.isEmpty {
                self.content(insights)
            }
        }
        .task(id: self.store.key(for: self.wordId)) { await self.store.load(self.wordId) }
        .sheet(isPresented: self.$showPaywall) { PaywallView() }
        .tujiSheet(
            isPresented: Binding(get: { self.sheetWordId != nil }, set: { if !$0 { self.sheetWordId = nil } }),
            title: "單字詳情",
            height: 520
        ) {
            if let id = self.sheetWordId, let word = self.words.find(id: id) {
                WordDetailSheet(word: word, wordId: id, gloss: word.chinese)
            }
        }
    }

    private func content(_ insights: WordInsights) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if !insights.confusables.isEmpty {
                self.title("容易混淆")
                ForEach(insights.confusables, id: \.self) { item in
                    VStack(alignment: .leading, spacing: Space.s2) {
                        self.term(item)
                        Text(verbatim: item.distinction)
                            .font(.tujiBodySm)
                            .foregroundStyle(.tujiInk2)
                    }
                    .insightCard()
                }
            }
            if !insights.mistakes.isEmpty || insights.lockedMistakesCount > 0 {
                self.title("常見誤用")
                ForEach(insights.mistakes, id: \.self) { item in
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text(verbatim: item.wrong).strikethrough().foregroundStyle(.tujiInk3)
                        Text(verbatim: item.right).foregroundStyle(.tujiInk)
                        Text(verbatim: item.why).foregroundStyle(.tujiInk2)
                    }
                    .font(.tujiBodySm)
                    .insightCard()
                }
                if insights.lockedMistakesCount > 0 {
                    self.locked(count: insights.lockedMistakesCount)
                }
            }
            if let usage = insights.usage {
                self.title("用法補充")
                Text(verbatim: usage)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk2)
                    .insightCard()
            } else if insights.usageLocked {
                self.title("用法補充")
                self.locked(count: 1)
            }
        }
    }

    @ViewBuilder
    private func term(_ item: WordInsightConfusable) -> some View {
        if let id = item.catalogId, self.words.find(id: id) != nil {
            Button { self.open(id) } label: {
                HStack(spacing: Space.s1) {
                    Text(verbatim: item.term).font(.tujiBody(.strong))
                    Image(systemName: "arrow.up.right").font(.tujiLabel)
                }
                .foregroundStyle(.tujiBrandSecondary)
            }
            .buttonStyle(.plain)
        } else {
            Text(verbatim: item.term)
                .font(.tujiBody(.strong))
                .foregroundStyle(.tujiInk)
        }
    }

    private func open(_ id: String) {
        switch self.presentation {
        case .push: self.navigator.push(.wordDetail(id: id))
        case .sheet: self.sheetWordId = id
        }
    }

    private func title(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.tujiLabel)
            .tracking(2)
            .foregroundStyle(.tujiInk3)
            .padding(.top, Space.s2)
    }

    private func locked(count: Int) -> some View {
        Button { self.showPaywall = true } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: "lock.fill")
                Text("會員可看更多（\(count) 則）")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.tujiLabel)
            .foregroundStyle(.tujiBrandSecondary)
            .insightCard()
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    func insightCard() -> some View {
        self.padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.r0)
                    .stroke(.tujiRule.opacity(0.25), lineWidth: 1)
            )
    }
}
