// AI 查詞 — a conversation with Moira. What was asked is the block on the right;
// her reply is the whole card. The composer at the bottom holds the draft and
// the three modes. Only 送出 (or 換個助記／重新生成 under the newest card)
// spends points; a candidate or a next step only fills the draft.

import SwiftUI

struct VocabularyView: View {
    @Environment(StudyFocus.self) private var studyFocus
    @Environment(\.presentPaywall) private var presentPaywall
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: VocabularyModel
    @State private var showingHistory = false
    @State private var showingContext = false
    @FocusState private var fieldFocused: Bool

    init(query: String = "") {
        _model = State(initialValue: VocabularyModel(query: query))
    }

    init(model: VocabularyModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back, showsRule: true) {
                HStack {
                    Text("AI 查詞").font(.tujiBody(.strong))
                    Spacer()
                    Button { self.showingHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("查詞紀錄"))
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
        .task(id: self.model.scopeID) { await self.model.load() }
        .sheet(isPresented: self.$showingHistory) { VocabularyHistoryView(model: self.model) }
        .accessibilityIdentifier("vocabulary-screen")
    }

    // MARK: - 對話

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    VocabularyMoiraRow {
                        Text("打一個單字、短語或中文意思給我，選好查詞、深度解析或助記再送出。")
                            .font(.tujiBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(self.model.turns) { turn in
                        VStack(alignment: .leading, spacing: Space.s3) {
                            VocabularyAskRow(input: turn.input)
                            VocabularyMoiraRow { self.reply(turn) }
                        }
                        .id(turn.id)
                    }
                }
                .padding(Space.s4)
            }
            .scrollDismissesKeyboard(.interactively)
            // To the top of the turn, not the bottom of the list: a card is long,
            // and landing on its last section hides the word it is about.
            .onChange(of: self.model.spotlight) { _, spotlight in
                guard let spotlight else { return }
                withAnimation(self.reduceMotion ? nil : Motion.ease(Motion.d2)) {
                    proxy.scrollTo(spotlight.id, anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private func reply(_ turn: VocabularyTurn) -> some View {
        let newest = turn.id == self.model.turns.last?.id
        if let note = turn.failureNote {
            Text(verbatim: note).font(.tujiBody)
            Button("改一下") {
                self.model.edit(turn)
                self.fieldFocused = true
            }
            .font(.tujiBodySm(.strong)).frame(minHeight: 44)
        } else if let record = turn.record {
            switch record.status {
            case .completed:
                if let content = record.result?.content { self.card(record, content: content, turn: turn) }
            case .clarification:
                if let reply = record.result { self.clarification(reply, mode: turn.input.mode, newest: newest) }
            case .pending, .failed, .deleted:
                EmptyView()
            }
        } else if self.model.pending?.requestId == turn.id {
            if self.model.busy {
                HStack(spacing: Space.s2) {
                    TujiProgressBar(progress: nil).frame(width: 40)
                    Text("正在生成，離開後可到紀錄查看。").font(.tujiBodySm).foregroundStyle(.tujiInk2)
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
    private func card(_ record: VocabularyRecord, content: VocabularyContent, turn: VocabularyTurn) -> some View {
        let target: TargetLanguage = turn.input.learningDirection == "zh-ja" ? .ja : .en
        VocabularyResultView(content: content, target: target) { candidate, mode in
            self.model.choose(candidate, mode: mode)
            self.fieldFocused = true
        }
        .id(record.id)
        HStack {
            Label("已保存到查詞紀錄", systemImage: "checkmark.circle").font(.tujiLabel).foregroundStyle(.tujiInk2)
            Spacer()
            Button { Task { await self.model.toggleFavorite(record) } } label: {
                Image(systemName: record.favorite ? "bookmark.fill" : "bookmark").frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text(record.favorite ? "移除書籤" : "加入書籤"))
        }
        switch self.model.regeneration(for: turn) {
        case let .main(points):
            Button { Task { await self.model.regenerate(turn) } } label: {
                Text("換個助記（最多 \(points) 點）")
                    .font(.tujiBody(.strong))
                    .padding(.horizontal, Space.s3).frame(minHeight: 48)
                    .background(.tujiCurrent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("vocabulary-regenerate")
        case let .secondary(points):
            Button { Task { await self.model.regenerate(turn) } } label: {
                Text("內容不理想？重新生成（最多 \(points) 點）")
                    .font(.tujiBodySm).underline()
                    .foregroundStyle(.tujiInk2)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("vocabulary-regenerate")
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func clarification(_ reply: VocabularyReply, mode: VocabularyMode, newest: Bool) -> some View {
        Text(verbatim: reply.message).font(.tujiBody).fixedSize(horizontal: false, vertical: true)
        ForEach(Array(reply.candidates.enumerated()), id: \.offset) { _, candidate in
            Button {
                self.model.choose(candidate, mode: mode)
                self.fieldFocused = true
            } label: {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(verbatim: candidate.term).font(.tujiBody(.strong))
                    Text(verbatim: candidate.meaning).font(.tujiBodySm)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s3).background(.tujiPaper2)
            }
            .buttonStyle(.plain)
            // An older question's choices stay readable, but answering it now
            // would put a stale word into the draft.
            .disabled(!newest)
        }
        Text("先選擇詞義，再按送出。這次沒有扣點。").font(.tujiLabel).foregroundStyle(.tujiInk2)
    }

    // MARK: - 輸入

    private var composer: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let message = self.model.message {
                Text(message).font(.tujiBodySm).foregroundStyle(.tujiInk2)
                    .accessibilityIdentifier("vocabulary-message")
            }
            self.catalogHint
            self.modes
            if !self.model.selectedSense.isEmpty {
                HStack(alignment: .top) {
                    Text(self.model.selectedSense).font(.tujiBodySm)
                    Spacer()
                    Button("清除詞義") { self.model.selectedSense = "" }.font(.tujiLabel)
                }
            }
            if self.showingContext || !self.model.context.isEmpty {
                TextField("貼上原句，讓解釋更貼近語境", text: self.$model.context, axis: .vertical)
                    .lineLimit(1...4).font(.tujiBodySm)
                    .padding(Space.s3).background(.tujiPaper2)
            }
            self.sendArea
            if self.model.query.count > 120 || self.model.context.count > 800 {
                Text("單字或短語限 120 字，原句限 800 字。").font(.tujiLabel)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .background(alignment: .top) {
            Rectangle().fill(.tujiRule).frame(height: Border.bw1)
        }
    }

    @ViewBuilder
    private var sendArea: some View {
        switch self.model.blocker {
        case .membership:
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("AI 查詞是會員功能").font(.tujiBody(.strong))
                Text("成為永久會員就能用罐頭點數查詞；既有紀錄仍可閱讀。")
                    .font(.tujiBodySm).foregroundStyle(.tujiInk2)
                BBtn(title: "了解會員", fullWidth: false) { self.presentPaywall() }
            }
            .accessibilityIdentifier("vocabulary-membership")
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
                .accessibilityIdentifier("vocabulary-insufficient")
            } else if let price = self.model.price, let offer = self.model.offer {
                Text(
                    "每次 \(price.minPoints)–\(price.maxPoints) 點，最多扣 \(price.maxPoints) 點；目前有 \(offer.available) 點。"
                )
                .font(.tujiLabel).foregroundStyle(.tujiInk3)
            } else if self.model.offer == nil, self.model.message != nil {
                Button("重新整理價格") { Task { await self.model.load() } }.font(.tujiBodySm)
            }
        }
    }

    private var field: some View {
        HStack(spacing: Space.s2) {
            TextField("輸入單字、短語或中文意思", text: Binding(
                get: { self.model.query }, set: { self.model.query = $0
                    self.model.editQuery()
                }
            ))
            .focused(self.$fieldFocused)
            // Return only closes the keyboard: spending is the arrow, beside its price.
            .submitLabel(.done)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .font(.tujiBody)
            .tint(.tujiInk)
            .padding(.horizontal, Space.s3)
            .frame(height: 52)
            .background(.tujiPaper2)
            .overlay {
                if self.fieldFocused { Rectangle().stroke(.tujiCurrent, lineWidth: Border.bw2) }
            }
            .accessibilityIdentifier("vocabulary-query")

            Button { self.showingContext.toggle() } label: {
                Image(systemName: "text.quote")
                    .font(.tujiIcon(17, weight: .semibold))
                    .foregroundStyle(self.showingContext || !self.model.context.isEmpty ? Color.tujiInk : .tujiInk3)
                    .frame(width: 44, height: 52)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("出現這個詞的原句（選填）"))

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
            .accessibilityIdentifier("vocabulary-generate")
        }
    }

    /// The free path, always in sight: 圖鑑 already has this word.
    @ViewBuilder
    private var catalogHint: some View {
        let matches = self.model.catalogMatches
        if let only = matches.first, matches.count == 1 {
            NavigationLink(value: NavRoute.wordDetail(id: only.id)) {
                self.hintLabel(Text("圖鑑裡有這個詞，免費看詳情"))
            }
            .accessibilityIdentifier("vocabulary-catalog-hint")
        } else if matches.count > 1 {
            NavigationLink(value: NavRoute
                .search(query: self.model.query.trimmingCharacters(in: .whitespacesAndNewlines)))
            {
                self.hintLabel(Text("圖鑑裡有 \(matches.count) 個相關詞，免費看詳情"))
            }
            .accessibilityIdentifier("vocabulary-catalog-hint")
        }
    }

    private func hintLabel(_ text: Text) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "books.vertical")
            text.font(.tujiBodySm(.strong))
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.tujiLabel)
        }
        .foregroundStyle(.tujiInk)
        .padding(.horizontal, Space.s3)
        .frame(minHeight: 44)
        .overlay(Rectangle().stroke(Color.tujiInk3, lineWidth: 1))
    }

    private var modes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(VocabularyMode.allCases) { mode in
                    Button { self.model.mode = mode } label: {
                        Text(mode.title).font(.tujiBodySm(.strong))
                            .padding(.horizontal, Space.s3).frame(minHeight: 40)
                            .background(self.model.mode == mode ? Color.tujiCurrent : .tujiPaper2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(self.model.mode == mode ? .isSelected : [])
                    .accessibilityHint(Text(mode.summary))
                    .accessibilityIdentifier("vocabulary-mode-\(mode.rawValue)")
                }
            }
        }
    }
}

// MARK: - 對話的兩邊

/// Moira's side: her face, and the words beside it rather than in a bubble —
/// a card is far longer than a bubble can hold.
private struct VocabularyMoiraRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Mascot(pose: .face, size: 36)
            VStack(alignment: .leading, spacing: Space.s3) { self.content }
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }
}

/// What was asked: the word, the mode, and the sense or sentence that narrowed it.
private struct VocabularyAskRow: View {
    let input: VocabularyInput

    var body: some View {
        VStack(alignment: .trailing, spacing: Space.s1) {
            Text(verbatim: self.input.query).font(.tujiBody(.strong))
            HStack(spacing: Space.s1) {
                Text(self.input.mode.title)
                if !self.input.selectedSense.isEmpty {
                    Text(verbatim: "· \(self.input.selectedSense)").lineLimit(1)
                }
            }
            .font(.tujiLabel).foregroundStyle(.tujiInk2)
            if !self.input.context.isEmpty {
                Text(verbatim: self.input.context).font(.tujiLabel).foregroundStyle(.tujiInk3).lineLimit(1)
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
