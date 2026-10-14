import SwiftUI

/// Existing assistant capabilities, in the order offered on its home.
enum AssistantHomeFeature: String, CaseIterable, Identifiable {
    case lookup, ask, story

    var id: String {
        self.rawValue
    }

    var route: NavRoute {
        switch self {
        case .lookup: .assistantChat(entry: .intent(.lookupPrompt))
        case .ask: .assistantChat(entry: .conversation)
        case .story: .assistantStory
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .lookup: "查單字"
        case .ask: "AI 問答"
        case .story: "情境故事"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .lookup: "查找圖鑑中的單字與意思"
        case .ask: "詢問語言學習問題，確認後使用罐頭點數"
        case .story: "選 1–3 個單字，生成情境對話"
        }
    }

    var symbol: String {
        switch self {
        case .lookup: "text.magnifyingglass"
        case .ask: "bubble.left.and.bubble.right"
        case .story: "text.book.closed"
        }
    }
}

struct AssistantHomeView: View {
    @Environment(StudyFocus.self) private var studyFocus
    @Environment(TabNavigator.self) private var navigator
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back, showsRule: true) {
                AssistantCreditLink()
            }
            ScrollView {
                VStack(spacing: Space.s4) {
                    self.introduction
                    self.questionField
                    self.features
                }
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s4)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.tujiPaper.ignoresSafeArea())
        .navigationTitle("助手")
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { self.studyFocus.enter() }
        .onDisappear { self.studyFocus.exit() }
        .accessibilityIdentifier("assistant-home")
    }

    private var introduction: some View {
        VStack(spacing: Space.s2) {
            AnimatedMascot()
                .frame(height: 236)
            Text("嗨，我是 Moira")
                .font(.tujiH2)
                .foregroundStyle(.tujiInk)
                .accessibilityAddTraits(.isHeader)
            Text("查單字、問問題，陪你一起學。")
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk2)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var questionField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                TextField("問問 Moira", text: self.$draft)
                    .focused(self.$fieldFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit(self.submit)
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk)
                    .tint(.tujiInk)
                    .padding(.horizontal, Space.s3)
                    .frame(minHeight: 52)
                    .background(.tujiPaper2)
                    .overlay {
                        if self.fieldFocused {
                            Rectangle().stroke(.tujiCurrent, lineWidth: Border.bw2)
                        }
                    }
                    .accessibilityIdentifier("assistant-home-question")
                Button(action: self.submit) {
                    Image(systemName: "arrow.up")
                        .font(.tujiIcon(17, weight: .bold))
                        .foregroundStyle(self.canSend ? Color.tujiInk : .tujiInk3)
                        .frame(width: 52, height: 52)
                        .background(self.canSend ? Color.tujiCurrent : .tujiPaper2)
                }
                .buttonStyle(.plain)
                .disabled(!self.canSend)
                .accessibilityLabel(Text("送出"))
                .accessibilityIdentifier("assistant-home-send")
            }
            Text("查圖鑑裡的詞不用點數；問 AI 才會扣罐頭點數。")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
        }
    }

    private var features: some View {
        VStack(spacing: 0) {
            ForEach(AssistantHomeFeature.allCases) { feature in
                NavigationLink(value: feature.route) {
                    HStack(spacing: Space.s3) {
                        Image(systemName: feature.symbol)
                            .font(.tujiIcon(22, weight: .medium))
                            .foregroundStyle(.tujiInk)
                            .frame(width: 44, height: 44)
                            .background(.tujiPaper2)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text(feature.title)
                                .font(.tujiBody(.strong))
                                .foregroundStyle(.tujiInk)
                            Text(feature.detail)
                                .font(.tujiBodySm)
                                .foregroundStyle(.tujiInk2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        TujiRowAccessory()
                    }
                    .padding(.vertical, Space.s3)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("assistant-feature-\(feature.id)")
                Rectangle().fill(.tujiRule).frame(height: Border.bw1)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(.tujiRule).frame(height: Border.bw1) }
    }

    private var canSend: Bool {
        AssistantChatEntry.question(self.draft) != nil
    }

    private func submit() {
        guard let entry = AssistantChatEntry.question(self.draft) else { return }
        self.fieldFocused = false
        self.draft = ""
        self.navigator.push(.assistantChat(entry: entry))
    }
}

/// The home and conversation both lead to the same wallet statement.
struct AssistantCreditLink: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationLink(value: NavRoute.creditStatement) {
            HStack(spacing: Space.s2) {
                Image("CreditCan")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                if !self.typeSize.isAccessibilitySize {
                    Text("點數明細").font(.tujiBodySm(.strong))
                }
            }
            .foregroundStyle(.tujiInk)
            .padding(.horizontal, Space.s3)
            .frame(minHeight: 44)
            .background(.tujiPaper2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("點數明細"))
    }
}
