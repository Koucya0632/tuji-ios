// 助手的四個能力，和它們的錢包入口。
//
// 這裡本來還有一個 `AssistantHomeView` —— 一整頁，上面一隻 236pt 的貓、一句
// 「嗨，我是 Moira」，底下四列。那一頁已經刪掉，四個入口搬到 今天。刪得掉是
// 因為那一頁除了這四列以外，剩下的全是重複的：今天 早就用名字跟使用者打過招呼，
// hero 右上也早就有一隻貓，所以兩句招呼和兩隻貓各留一份就夠。
//
// 留在這裡的是那一頁真正擁有的東西：能力清單、它的預熱，以及點數明細的入口。
// 全都不帶畫面，所以 今天 可以直接用。

import SwiftUI

/// Existing assistant capabilities, in the order offered on 今天.
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

    /// 一句話說這個能力做什麼。
    ///
    /// 今天 的橫帶不印它 —— 四格並排，一行說明會把格子撐成三倍高，而貓就坐在
    /// 它們正上方，已經說了這一區是誰的。留著是因為 VoiceOver 要唸，螢幕上省
    /// 掉的字不等於讀出來也該省。
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
        // Not text.book.closed: 情境故事 already has it, two cells over.
        case .grammar: "character.book.closed"
        case .story: "text.book.closed"
        case .topicChat: "bubble.left.and.text.bubble.right"
        }
    }

    /// 讓 情境故事 一進去就看得到選項、AI 查詞 和 AI 語法 一進去就看得到價格，
    /// 而不是先看到轉圈。
    ///
    /// 本來掛在助手首頁的 `.task` 上。那一頁沒了，所以它改掛在 今天 的預熱
    /// 流程後面（`TodayView.prefetchAssistantOffers`）—— 入口在哪，預熱就該在哪。
    @MainActor
    static func prefetchOffers() async {
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
}

/// 四個入口，一條滿版的橫帶。
///
/// 併進 今天 之前它們是四列 —— 圖示、標題、一行說明、一個 chevron。改成並排
/// 之後說明印不下（一行說明會把格子撐成三倍高），而貓就坐在正上方，已經說了
/// 這一區是誰的。說明沒有丟，它在 `accessibilityHint` 裡，螢幕上省掉的字不等
/// 於讀出來也該省。
///
/// 自己一個型別而不是埋在 `TodayView` 裡，是因為四格並排是全 app 最會被大字級
/// 和日文撐爆的版面之一，而快照測試需要抓得到它。
struct MoiraFeatureBand: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(AssistantHomeFeature.allCases.enumerated()), id: \.element.id) { index, feature in
                if index > 0 {
                    Rectangle().fill(.tujiRule).frame(width: Border.bw1)
                }
                NavigationLink(value: feature.route) {
                    VStack(spacing: Space.s2) {
                        Image(systemName: feature.symbol)
                            .font(.tujiIcon(22, weight: .medium))
                            .accessibilityHidden(true)
                        Text(feature.title)
                            .font(.tujiLabel)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(.tujiInk)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 88)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("assistant-feature-\(feature.id)")
                .accessibilityLabel(Text(feature.title))
                .accessibilityHint(Text(feature.detail))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(.tujiPaper2)
        .overlay(alignment: .top) { Rectangle().fill(.tujiRule).frame(height: Border.bw1) }
        .overlay(alignment: .bottom) { Rectangle().fill(.tujiRule).frame(height: Border.bw1) }
        .accessibilityIdentifier("moira-feature-band")
    }
}

/// 點數明細的入口。
///
/// 本來是助手首頁導覽列上的一塊晶片，併進 今天 之後先掛在「和 Moira 一起」
/// 那行標題右邊。那行標題後來整排拿掉了 —— 一隻 236pt 的貓正坐在四個寫著
/// 名字的入口上面，不需要再有一行字說這一區是誰的，而且那 48pt 正是四格
/// 被 tab bar 蓋掉的原因。
///
/// 所以罐頭搬到最上面那排，跟搜尋和打卡站一起：那一排本來就是「你的計數器」，
/// 火焰是連續天數，罐頭是點數。搜尋也是一個沒有字的圖示，所以這裡不是先例。
struct AssistantCreditLink: View {
    var body: some View {
        NavigationLink(value: NavRoute.creditStatement) {
            Image("CreditCan")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .padding(Space.s2 - 1)
                .background(.tujiPaper, in: .circle)
                .overlay(Circle().stroke(.tujiRule.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("點數明細"))
    }
}
