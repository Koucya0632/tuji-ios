// Shared NavRoute destination switch. Each tab's NavigationStack attaches
// this so any push of NavRoute resolves consistently.

import SwiftUI

extension View {
    func tujiNavDestinations(user: SessionUser?) -> some View {
        self.wordListDestinations()
            .navigationDestination(for: NavRoute.self) { route in
                switch route {
                case let .search(query): SearchView(initialQuery: query)
                case .assistant, .assistantChat, .creditStatement, .assistantStory, .topicChat, .topicChatHistory:
                    AssistantDestination(route: route)
                case .settings: SettingsView()
                case .atlasManage: AtlasManageView(initialSection: .cards)
                case let .atlasCollectionEdit(id): AtlasCollectionEditView(collectionId: id)
                case let .atlasCollectionDetail(slug, preview):
                    AtlasCollectionDetailView(slug: slug, preview: preview)
                case let .authorProfile(handle, isSelf):
                    AtlasAuthorProfileView(handle: handle, isSelf: isSelf)
                case .studyCategories: StudyCategoriesPickerView()
                case let .studyLanding(mode): StudyLauncherView(mode: mode)
                case let .wordDetail(id): WordDestination(id: id)
                case let .atlasPublicItem(item): AtlasPublicDetailView(item: item)
                case let .categoryDetail(id): CategoryView(id: id)
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

/// 助手 and the screens it links to. Grouped in one arm so the table above
/// stays within what one function can hold; the grouping is real — 點數明細 and
/// 情境故事 are reached from 助手, and 主題對話 is Moira's too (though it is
/// opened from a category page).
private struct AssistantDestination: View {
    let route: NavRoute

    var body: some View {
        switch self.route {
        case let .assistantChat(entry): AssistantChatView(entry: entry)
        case .creditStatement: CreditStatementView()
        case .assistantStory: StoryBuilderView()
        case let .topicChat(entry): TopicChatView(entry: entry)
        case .topicChatHistory: TopicChatHistoryView()
        default: AssistantHomeView()
        }
    }
}
