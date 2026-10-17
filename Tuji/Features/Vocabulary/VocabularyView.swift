import SwiftUI

struct VocabularyView: View {
    @Environment(StudyFocus.self) private var studyFocus
    @Environment(\.presentPaywall) private var presentPaywall
    @State private var model: VocabularyModel
    @State private var showingHistory = false

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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        self.input
                        self.modes
                        Text(self.model.mode.summary).font(.tujiBodySm).foregroundStyle(.tujiInk2)
                        self.sectionLinks(proxy)
                        self.generation
                        if let message = self.model.message {
                            Text(message).font(.tujiBodySm).foregroundStyle(.tujiInk2)
                                .accessibilityIdentifier("vocabulary-message")
                        }
                        if let record = self.model.current {
                            VStack(alignment: .leading, spacing: Space.s4) { self.result(record) }
                                .id("vocabulary-result")
                        }
                    }
                    .padding(Space.s4)
                }
                .scrollDismissesKeyboard(.interactively)
                // A new card lands below the form, off screen on most phones: bring it up.
                .onChange(of: self.model.current?.id) { _, id in
                    guard id != nil else { return }
                    withAnimation { proxy.scrollTo("vocabulary-result", anchor: .top) }
                }
            }
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

    private var input: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(self.model.target == .ja ? "學習語言：日文" : "學習語言：英文")
                .font(.tujiLabel).foregroundStyle(.tujiInk2)
            TextField("輸入單字、短語或中文意思", text: Binding(
                get: { self.model.query }, set: { self.model.query = $0
                    self.model.editQuery()
                }
            ), axis: .vertical)
                .font(.tujiH3).lineLimit(1...3)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(Space.s3).background(.tujiPaper2)
                .accessibilityIdentifier("vocabulary-query")
            DisclosureGroup("出現這個詞的原句（選填）") {
                TextField("貼上原句，讓解釋更貼近語境", text: self.$model.context, axis: .vertical)
                    .lineLimit(2...6).font(.tujiBodySm)
                    .padding(Space.s3).background(.tujiPaper2)
            }
            .font(.tujiBodySm)
            if !self.model.selectedSense.isEmpty {
                HStack(alignment: .top) {
                    Text(self.model.selectedSense).font(.tujiBodySm)
                    Spacer()
                    Button("清除詞義") { self.model.selectedSense = "" }.font(.tujiLabel)
                }
            }
            self.catalogHint
            if self.model.query.count > 120 || self.model.context.count > 800 {
                Text("單字或短語限 120 字，原句限 800 字。").font(.tujiLabel)
            }
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
        .padding(Space.s3)
        .frame(minHeight: 44)
        .overlay(Rectangle().stroke(Color.tujiInk3, lineWidth: 1))
    }

    private var modes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(VocabularyMode.allCases) { mode in
                    Button { self.model.mode = mode } label: {
                        Text(mode.title).font(.tujiBodySm(.strong))
                            .padding(.horizontal, Space.s3).frame(minHeight: 48)
                            .background(self.model.mode == mode ? Color.tujiCurrent : .tujiPaper2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(self.model.mode == mode ? .isSelected : [])
                    .accessibilityIdentifier("vocabulary-mode-\(mode.rawValue)")
                }
            }
        }
    }

    private func sectionLinks(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(Array(self.model.mode.sections.enumerated()), id: \.offset) { index, title in
                    Button(title) { proxy.scrollTo("vocabulary-section-\(index)", anchor: .top) }
                        .font(.tujiLabel).padding(Space.s2).background(.tujiPaper2)
                        .disabled(self.model.current?.result?.content == nil)
                }
            }
        }
    }

    private var generation: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if self.model.pending != nil {
                if self.model.busy {
                    ProgressView("正在生成，離開後可到紀錄查看。")
                } else {
                    Button("確認生成結果") { Task { await self.model.reconcile() } }
                        .font(.tujiBody(.strong)).padding(Space.s3).background(.tujiCurrent)
                }
            } else if self.model.blocker == .membership {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("AI 查詞是會員功能").font(.tujiBody(.strong))
                    Text("成為永久會員就能用罐頭點數查詞；既有紀錄仍可閱讀。")
                        .font(.tujiBodySm).foregroundStyle(.tujiInk2)
                    BBtn(title: "了解會員", fullWidth: false) { self.presentPaywall() }
                }
                .accessibilityIdentifier("vocabulary-membership")
            } else if self.model.blocker == .disabled {
                Text("目前無法使用 AI 生成，既有紀錄仍可閱讀。")
                    .font(.tujiLabel).foregroundStyle(.tujiInk2)
            } else if let price = self.model.price, let offer = self.model.offer {
                if !self.model.regenerationIsSecondary {
                    Text(
                        "每次 \(price.minPoints)–\(price.maxPoints) 點，最多扣 \(price.maxPoints) 點；目前有 \(offer.available) 點。"
                    )
                    .font(.tujiLabel).foregroundStyle(.tujiInk2)
                    Button { Task { await self.model.generate() } } label: {
                        HStack {
                            Text(self.generateTitle).font(.tujiBody(.strong))
                            Spacer()
                            Text("最多 \(price.maxPoints) 點").font(.tujiLabel)
                        }
                        .padding(Space.s3).frame(minHeight: 52)
                        .background(self.model.canGenerate ? Color.tujiCurrent : .tujiPaper2)
                    }
                    .buttonStyle(.plain).disabled(!self.model.canGenerate)
                    .accessibilityIdentifier("vocabulary-generate")
                }
                if self.model.blocker == .insufficientPoints {
                    HStack(spacing: Space.s3) {
                        Text("罐頭點數不足，請先補充點數。").font(.tujiLabel)
                        Spacer(minLength: 0)
                        BBtn(title: "補充點數", fullWidth: false) { self.presentPaywall() }
                    }
                    .accessibilityIdentifier("vocabulary-insufficient")
                }
            } else {
                Button("重新整理價格") { Task { await self.model.load() } }.font(.tujiBodySm)
            }
            Text("已生成的內容可免費重看；重新生成會再次使用點數。")
                .font(.tujiLabel).foregroundStyle(.tujiInk3)
        }
    }

    private var generateTitle: String {
        self.model.current?.status == .completed ? tujiLocalized("換個助記") : tujiLocalized("生成內容")
    }

    @ViewBuilder
    private func result(_ record: VocabularyRecord) -> some View {
        if let content = record.result?.content, record.status == .completed {
            HStack {
                Label("已保存到查詞紀錄", systemImage: "checkmark.circle").font(.tujiLabel)
                Spacer()
                Button { Task { await self.model.toggleFavorite(record) } } label: {
                    Image(systemName: record.favorite ? "bookmark.fill" : "bookmark").frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text(record.favorite ? "移除書籤" : "加入書籤"))
            }
            VocabularyResultView(content: content, target: self.model.target) { candidate, mode in
                self.model.choose(candidate, mode: mode)
            }
            .id(record.id)
            if self.model.regenerationIsSecondary, let price = self.model.price, self.model.blocker == nil {
                Button { Task { await self.model.generate() } } label: {
                    Text("內容不理想？重新生成（最多 \(price.maxPoints) 點）")
                        .font(.tujiBodySm).underline()
                        .foregroundStyle(.tujiInk2)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(!self.model.canGenerate)
                .accessibilityIdentifier("vocabulary-regenerate")
            }
        } else if let reply = record.result, record.status == .clarification {
            Text(reply.message).font(.tujiBody)
            ForEach(Array(reply.candidates.enumerated()), id: \.offset) { _, candidate in
                Button { self.model.choose(candidate, mode: self.model.mode) } label: {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text(verbatim: candidate.term).font(.tujiBody(.strong))
                        Text(verbatim: candidate.meaning).font(.tujiBodySm)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s3).background(.tujiPaper2)
                }
                .buttonStyle(.plain)
            }
            Text("先選擇詞義，再按生成。這次沒有扣點。").font(.tujiLabel)
        }
    }
}
