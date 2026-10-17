// AI 語法 — a conversation with Moira about grammar. What was asked is the block
// on the right; her reply is the whole card: an explanation, a comparison, or a
// practice set worked through in place. The composer at the bottom holds the
// draft and the three templates. Only 送出 (or 換一組題目／重新生成 under the
// newest card) spends points; a candidate or a next step only fills the draft.

import SwiftUI

struct GrammarView: View {
    @Environment(StudyFocus.self) private var studyFocus
    @Environment(\.presentPaywall) private var presentPaywall
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: GrammarModel
    @State private var showingHistory = false
    @State private var showingContext = false
    @FocusState private var fieldFocused: Bool

    init(query: String = "") {
        _model = State(initialValue: GrammarModel(query: query))
    }

    init(model: GrammarModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back, showsRule: true) {
                HStack {
                    Text("AI 語法").font(.tujiBody(.strong))
                    Spacer()
                    Button { self.showingHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("語法紀錄"))
                    .accessibilityIdentifier("grammar-history")
                    NavigationLink(value: NavRoute.creditStatement) {
                        Image(systemName: "creditcard").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("點數明細"))
                }
            }
            self.conversation
            self.composer
        }
        .background(Color.tujiPaper.ignoresSafeArea())
        .foregroundStyle(.tujiInk)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { self.studyFocus.enter() }
        .onDisappear { self.studyFocus.exit() }
        .task(id: "\(self.model.scopeID)|\(self.model.offerRevision)") { await self.model.load() }
        .onChange(of: self.model.draftTick) {
            if !self.model.context.isEmpty { self.showingContext = true }
            self.fieldFocused = true
        }
        .sheet(isPresented: self.$showingHistory) { GrammarHistoryView(model: self.model) }
        .accessibilityIdentifier("grammar-screen")
    }

    // MARK: - 對話

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    MoiraReplyRow {
                        Text("貼上句子或告訴我想學的語法，我可以幫你解釋、比較，也能出題練習。")
                            .font(.tujiBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(self.model.turns) { turn in
                        VStack(alignment: .leading, spacing: Space.s3) {
                            GrammarAskRow(input: turn.input)
                            MoiraReplyRow { self.reply(turn) }
                        }
                        .id(turn.id)
                    }
                }
                .padding(Space.s4)
            }
            .scrollDismissesKeyboard(.interactively)
            // To the top of the turn, not the bottom of the list: a card is long,
            // and landing on its last section hides what it is about.
            .onChange(of: self.model.spotlight) { _, spotlight in
                guard let spotlight else { return }
                withAnimation(self.reduceMotion ? nil : Motion.ease(Motion.d2)) {
                    proxy.scrollTo(spotlight.id, anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private func reply(_ turn: GrammarTurn) -> some View {
        let newest = turn.id == self.model.turns.last?.id
        if let note = turn.failureNote {
            Text(verbatim: note).font(.tujiBody)
            Button("改一下") { self.model.edit(turn) }
                .font(.tujiBodySm(.strong)).frame(minHeight: 44)
        } else if let record = turn.record {
            switch record.status {
            case .completed:
                if let content = record.result?.content { self.card(record, content: content, turn: turn) }
            case .clarification:
                if let reply = record.result { self.clarification(reply, turn: turn, newest: newest) }
            case .pending, .failed, .deleted:
                EmptyView()
            }
        } else if self.model.pending?.requestId == turn.id {
            if self.model.busy {
                HStack(spacing: Space.s2) {
                    TujiProgressBar(progress: nil).frame(width: 40)
                    Text(turn.input.mode == .practice ? "正在出題，約需半分鐘；離開後可到紀錄查看。" : "正在生成，離開後可到紀錄查看。")
                        .font(.tujiBodySm).foregroundStyle(.tujiInk2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 36)
            } else {
                Button("確認生成結果") { Task { await self.model.reconcile() } }
                    .font(.tujiBody(.strong)).padding(Space.s3).background(.tujiCurrent)
                    .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func card(_ record: GrammarRecord, content: GrammarContent, turn: GrammarTurn) -> some View {
        let target: TargetLanguage = turn.input.learningDirection == "zh-ja" ? .ja : .en
        switch content {
        case let .explain(value):
            GrammarExplanationView(value: value, target: target)
            self.nextSteps {
                Button("比較近似語法") { self.model.next(.compare, from: record) }
                Button("練習這個語法") { self.model.next(.practice, from: record) }
            }
        case let .compare(value):
            GrammarComparisonView(value: value, target: target)
            self.nextSteps {
                Button("解釋 \(value.a.name)") { self.model.follow(.explainA, from: record) }
                Button("解釋 \(value.b.name)") { self.model.follow(.explainB, from: record) }
                Button("練習分辨") { self.model.follow(.practice, from: record) }
            }
        case let .practice(value):
            if let owner = self.model.owner {
                GrammarPracticeView(session: GrammarPracticeSession(
                    practice: value,
                    setId: record.id,
                    owner: owner,
                    learning: turn.input.learningDirection,
                    store: self.model.progress
                ))
                .id("\(record.id)-practice")
            }
        }
        HStack {
            Label("已保存到語法紀錄", systemImage: "checkmark.circle").font(.tujiLabel).foregroundStyle(.tujiInk2)
            Spacer()
            Button { Task { await self.model.toggleFavorite(record) } } label: {
                Image(systemName: record.favorite ? "bookmark.fill" : "bookmark").frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text(record.favorite ? "移除書籤" : "加入書籤"))
        }
        switch self.model.regeneration(for: turn) {
        case let .main(points):
            Button { Task { await self.model.regenerate(turn) } } label: {
                Text("換一組題目（最多 \(points) 點）")
                    .font(.tujiBody(.strong))
                    .padding(.horizontal, Space.s3).frame(minHeight: 48)
                    .background(.tujiCurrent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("grammar-regenerate")
        case let .secondary(points):
            Button { Task { await self.model.regenerate(turn) } } label: {
                Text("內容不理想？重新生成（最多 \(points) 點）")
                    .font(.tujiBodySm).underline()
                    .foregroundStyle(.tujiInk2)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("grammar-regenerate")
        case nil:
            EmptyView()
        }
    }

    /// A next step only fills the draft; the price is said beside 送出.
    private func nextSteps(@ViewBuilder _ buttons: () -> some View) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s3) { buttons() }
            VStack(alignment: .leading, spacing: Space.s1) { buttons() }
        }
        .font(.tujiBodySm(.strong))
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private func clarification(_ reply: GrammarReply, turn: GrammarTurn, newest: Bool) -> some View {
        Text(verbatim: reply.message).font(.tujiBody).fixedSize(horizontal: false, vertical: true)
        ForEach(Array(reply.candidates.enumerated()), id: \.offset) { _, candidate in
            Button { self.model.choose(candidate, for: turn) } label: {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(verbatim: candidate.focus).font(.tujiBody(.strong))
                    Text(verbatim: candidate.description).font(.tujiBodySm)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s3).background(.tujiPaper2)
            }
            .buttonStyle(.plain)
            // An older question's choices stay readable, but answering it now
            // would put a stale sentence into the draft.
            .disabled(!newest)
        }
        Text("先選一個語法重點，再按送出。這次沒有扣點。").font(.tujiLabel).foregroundStyle(.tujiInk2)
    }

    // MARK: - 輸入

    private var composer: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let message = self.model.message {
                Text(message).font(.tujiBodySm).foregroundStyle(.tujiInk2)
                    .accessibilityIdentifier("grammar-message")
            }
            self.modes
            if !self.model.focus.isEmpty {
                HStack(alignment: .top) {
                    Text("重點：\(self.model.focus)").font(.tujiBodySm)
                    Spacer()
                    Button("清除重點") { self.model.focus = "" }.font(.tujiLabel).frame(minHeight: 44)
                }
            }
            if self.model.mode == .compare {
                self.extraField("比較對象（選填，留空由 Moira 挑選）", text: self.$model.compareWith)
                    .accessibilityIdentifier("grammar-compare-with")
            }
            if self.model.mode == .practice { self.practiceOptions }
            if self.showingContext || !self.model.context.isEmpty {
                self.extraField("原句或使用情境（選填）", text: self.$model.context)
            }
            self.sendArea
            if self.model.tooLong {
                Text("語法或問題限 800 字，原句限 800 字，比較對象限 120 字。").font(.tujiLabel)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .background(alignment: .top) {
            Rectangle().fill(.tujiRule).frame(height: Border.bw1)
        }
    }

    private func extraField(_ prompt: LocalizedStringKey, text: Binding<String>) -> some View {
        TextField(prompt, text: text, axis: .vertical)
            .lineLimit(1...4).font(.tujiBodySm)
            .padding(Space.s3).background(.tujiPaper2)
    }

    private var practiceOptions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(GrammarDifficulty.allCases) { level in
                    self.chip(level.title, selected: self.model.difficulty == level) { self.model.difficulty = level }
                }
                Rectangle().fill(.tujiRule).frame(width: Border.bw1, height: 24)
                ForEach(GrammarPracticeType.allCases) { type in
                    self.chip(type.title, selected: self.model.practiceType == type) { self.model.practiceType = type }
                }
            }
        }
        .accessibilityIdentifier("grammar-practice-options")
    }

    private func chip(_ title: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.tujiLabel)
                .padding(.horizontal, Space.s3).frame(minHeight: 44)
                .overlay(Rectangle().stroke(selected ? Color.tujiInk : .tujiInk3, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var sendArea: some View {
        switch self.model.blocker {
        case .membership:
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("AI 語法是會員功能").font(.tujiBody(.strong))
                Text("成為永久會員就能用罐頭點數學語法；既有紀錄仍可閱讀。")
                    .font(.tujiBodySm).foregroundStyle(.tujiInk2)
                BBtn(title: "了解會員", fullWidth: false) { self.presentPaywall() }
            }
            .accessibilityIdentifier("grammar-membership")
        case .disabled:
            Text("目前無法使用 AI 生成，既有紀錄仍可閱讀。")
                .font(.tujiLabel).foregroundStyle(.tujiInk2)
        case .insufficientPoints, nil:
            self.field
            if self.model.blocker == .insufficientPoints {
                HStack(spacing: Space.s3) {
                    Text("罐頭點數不足，請先補充點數。").font(.tujiLabel)
                    Spacer(minLength: 0)
                    BBtn(title: "補充點數", fullWidth: false) { self.presentPaywall() }
                }
                .accessibilityIdentifier("grammar-insufficient")
            } else if let price = self.model.price {
                Text("每次 \(price.minPoints)–\(price.maxPoints) 點，最多扣 \(price.maxPoints) 點。")
                    .font(.tujiLabel).foregroundStyle(.tujiInk3)
            }
            // Not in the chain above: a kept offer still shows its prices offline.
            if !self.model.offerCurrent, self.model.message != nil {
                Button("重新整理價格") { Task { await self.model.load() } }.font(.tujiBodySm)
            }
        }
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: Space.s2) {
            TextField(self.model.mode.placeholder, text: Binding(
                get: { self.model.query }, set: { self.model.query = $0
                    self.model.editQuery()
                }
            ), axis: .vertical)
                .lineLimit(1...4)
                .focused(self.$fieldFocused)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.tujiBody)
                .tint(.tujiInk)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s3)
                .frame(minHeight: 52)
                .background(.tujiPaper2)
                .overlay {
                    if self.fieldFocused { Rectangle().stroke(.tujiCurrent, lineWidth: Border.bw2) }
                }
                .accessibilityIdentifier("grammar-query")

            Button { self.showingContext.toggle() } label: {
                Image(systemName: "text.quote")
                    .font(.tujiIcon(17, weight: .semibold))
                    .foregroundStyle(self.showingContext || !self.model.context.isEmpty ? Color.tujiInk : .tujiInk3)
                    .frame(width: 44, height: 52)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("原句或使用情境（選填）"))

            Button {
                self.fieldFocused = false
                Task { await self.model.generate() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.tujiIcon(17, weight: .bold))
                    .foregroundStyle(self.model.canGenerate ? Color.tujiPaper : .tujiInk3)
                    .frame(width: 52, height: 52)
                    .background(self.model.canGenerate ? Color.tujiInk : .tujiPaper2)
            }
            .buttonStyle(.plain)
            .disabled(!self.model.canGenerate)
            .accessibilityLabel(Text("送出，最多 \(self.model.price?.maxPoints ?? 0) 點"))
            .accessibilityIdentifier("grammar-generate")
        }
    }

    private var modes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(GrammarMode.allCases) { mode in
                    Button { self.model.mode = mode } label: {
                        Text(mode.title).font(.tujiBodySm(.strong))
                            .padding(.horizontal, Space.s3).frame(minHeight: 44)
                            .background(self.model.mode == mode ? Color.tujiCurrent : .tujiPaper2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(self.model.mode == mode ? .isSelected : [])
                    .accessibilityHint(Text(mode.summary))
                    .accessibilityIdentifier("grammar-mode-\(mode.rawValue)")
                }
            }
        }
    }
}

/// What was asked: the grammar or sentence, the template, and what narrowed it.
private struct GrammarAskRow: View {
    let input: GrammarInput

    var body: some View {
        VStack(alignment: .trailing, spacing: Space.s1) {
            Text(verbatim: self.input.query).font(.tujiBody(.strong)).lineLimit(6)
            HStack(spacing: Space.s1) {
                Text(self.input.mode.title)
                if !self.input.compareWith.isEmpty {
                    Text(verbatim: "· \(self.input.compareWith)").lineLimit(1)
                }
                if !self.input.focus.isEmpty {
                    Text(verbatim: "· \(self.input.focus)").lineLimit(1)
                }
                if self.input.mode == .practice {
                    Text(verbatim: "·")
                    Text(self.input.difficulty.title)
                    Text(verbatim: "·")
                    Text(self.input.practiceType.title)
                }
            }
            .font(.tujiLabel).foregroundStyle(.tujiInk2)
            if !self.input.context.isEmpty {
                Text(verbatim: self.input.context).font(.tujiLabel).foregroundStyle(.tujiInk3).lineLimit(2)
            }
        }
        .multilineTextAlignment(.trailing)
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(.tujiPaper2)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, Space.s5)
        .accessibilityElement(children: .combine)
    }
}
