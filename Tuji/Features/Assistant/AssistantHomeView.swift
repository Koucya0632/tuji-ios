import SwiftUI

/// Existing assistant capabilities, in the order offered on its home.
enum AssistantHomeFeature: String, CaseIterable, Identifiable {
    case lookup, grammar, story, topicChat

    var id: String {
        self.rawValue
    }

    var route: NavRoute {
        switch self {
        case .lookup: .vocabulary(query: "")
        case .grammar: .grammar
        case .story: .assistantStory
        case .topicChat: .topicChat(.choose)
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .lookup: "AI 查詞"
        case .grammar: "AI 語法"
        case .story: "情境故事"
        case .topicChat: "主題對話"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .lookup: "查詞、深入解析與助記"
        case .grammar: "解釋句型、比較用法與語法練習"
        case .story: "選 1–3 個單字，生成情境對話"
        case .topicChat: "選一個圖鑑主題，和 Moira 聊聊"
        }
    }

    var symbol: String {
        switch self {
        case .lookup: "text.magnifyingglass"
        // Not text.book.closed: 情境故事 already has it, two rows down.
        case .grammar: "character.book.closed"
        case .story: "text.book.closed"
        case .topicChat: "bubble.left.and.text.bubble.right"
        }
    }
}

struct AssistantHomeView: View {
    @Environment(StudyFocus.self) private var studyFocus
    /// So 情境故事 opens on its choices, and AI 查詞 and AI 語法 on their prices,
    /// rather than waiting for them.
    var prefetchOffers: @MainActor () async -> Void = {
        let owner = AuthService.shared.uid
        // Tasks, not `async let`: those run off the main actor, where the offers
        // cannot be decoded.
        let story = Task {
            await StoryOfferCache.shared.prefetch(uiLanguage: UILanguage(code: SettingsStore.shared.uiLang).rawValue)
        }
        let vocabulary = Task {
            await AssistantOfferCaches.vocabulary
                .prefetch(owner: owner) { try await LiveVocabularyRepository().offer() }
        }
        let grammar = Task {
            await AssistantOfferCaches.grammar.prefetch(owner: owner) { try await LiveGrammarRepository().offer() }
        }
        _ = await (story.value, vocabulary.value, grammar.value)
    }

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back, showsRule: true) {
                AssistantCreditLink()
            }
            ScrollView {
                VStack(spacing: Space.s4) {
                    self.introduction
                    self.features
                }
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s4)
            }
        }
        .background(Color.tujiPaper.ignoresSafeArea())
        .navigationTitle("助手")
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { self.studyFocus.enter() }
        .onDisappear { self.studyFocus.exit() }
        .task { await self.prefetchOffers() }
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
            Text("查單字、讀故事，陪你一起學。")
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk2)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
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
}

/// The home leads to the wallet statement.
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
