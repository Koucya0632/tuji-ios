// Shared NavRoute destination switch. Each tab's NavigationStack attaches
// this so any push of NavRoute resolves consistently.

import SwiftUI

extension View {
    func tujiNavDestinations(user: SessionUser?) -> some View {
        self.wordListDestinations()
            .travelDestinations()
            .navigationDestination(for: NavRoute.self) { route in
                switch route {
                case let .search(query): SearchView(initialQuery: query)
                case .creditStatement, .assistantStory, .topicChat, .topicChatHistory,
                     .vocabulary, .grammar:
                    AssistantDestination(route: route)
                case .settings: SettingsView()
                case .atlasManage: AtlasManageView(initialSection: .cards)
                case let .atlasCollectionEdit(id): AtlasCollectionEditView(collectionId: id)
                case let .atlasCollectionDetail(slug, preview):
                    AtlasCollectionDetailView(slug: slug, preview: preview)
                case let .authorProfile(handle, isSelf):
                    AtlasAuthorProfileView(handle: handle, isSelf: isSelf)
                case .studyCategories: StudyCategoriesPickerView()
                case .progressStats: ProgressStatsView()
                case let .studyLanding(mode): StudyLauncherView(mode: mode)
                case let .wordDetail(id): WordDestination(id: id)
                case let .atlasPublicItem(item): AtlasPublicDetailView(item: item)
                case .atlasSearch: AtlasSearchView()
                case let .categoryDetail(id): CategoryView(id: id)
                case .sceneList, .sceneDetail, .scenePractice, .sceneWord:
                    SceneDestination(route: route, user: user)
                }
            }
    }
}

/// The id says where it goes. `saved:` items are other people's work, so they
/// open on the public detail — author, 取消收藏, 檢舉 — rather than the word
/// screen, which has none of those. Deciding here keeps every entry point
/// (圖鑑, search, 助手, anything later) on the same destination without each one
/// re-checking.
private struct WordDestination: View {
    let id: String

    var body: some View {
        if let slug = self.id.savedCommunitySlug {
            AtlasSavedItemDetailView(slug: slug)
        } else {
            WordDetailView(id: self.id)
        }
    }
}

/// Moira 的四個能力，和它們連到的畫面。Grouped in one arm so the table above
/// stays within what one function can hold; the grouping is real — 它們全都從
/// 今天 的「和 Moira 一起」進來，點數明細也是（主題對話另外還能從主題頁開）。
///
/// 這一區本來有自己的首頁（`AssistantHomeView`），`.assistant` 就是它的路由。
/// 那一頁併進 今天 之後，路由和畫面一起刪了。
private struct AssistantDestination: View {
    let route: NavRoute

    var body: some View {
        switch self.route {
        case .creditStatement: CreditStatementView()
        case .assistantStory: StoryBuilderView()
        case let .vocabulary(query): VocabularyView(query: query)
        case .grammar: GrammarView()
        case let .topicChat(entry): TopicChatView(entry: entry)
        case .topicChatHistory: TopicChatHistoryView()
        // 上面那個 arm 就是這個 switch 的門：只有列出來的六個路由進得來。
        // 這裡寫 default 純粹是因為 switch 的對象是整個 NavRoute。
        default: EmptyView()
        }
    }
}

/// 場面練習's three screens, and a word page opened from one. Grouped for the same reason as `AssistantDestination`.
private struct SceneDestination: View {
    let route: NavRoute
    let user: SessionUser?

    var body: some View {
        switch self.route {
        case .sceneList: SceneListView(user: self.user)
        case let .sceneDetail(id): SceneDetailView(sceneId: id, user: self.user)
        case let .scenePractice(id, route): ScenePracticeView(sceneId: id, routeId: route, user: self.user)
        case let .sceneWord(id, scene): WordDetailView(id: id, fromScene: scene)
        default: EmptyView()
        }
    }
}
