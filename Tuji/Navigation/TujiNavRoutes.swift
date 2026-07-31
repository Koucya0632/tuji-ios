// Shared NavRoute destination switch. Each tab's NavigationStack attaches
// this so any push of NavRoute resolves consistently.

import SwiftUI

extension View {
    func tujiNavDestinations(user: SessionUser?) -> some View {
        self.navigationDestination(for: NavRoute.self) { route in
            switch route {
            case .cards: CardsListView()
            case .today: TodayView(user: user)
            case let .search(query): SearchView(initialQuery: query)
            case .favorites: FavoritesView()
            case .settings: SettingsView()
            case .atlasManage: AtlasManageView(initialSection: .cards)
            case .atlasPublic: AtlasPublicFeedView()
            case .atlasMyCollections: AtlasManageView(initialSection: .collections)
            case let .atlasCollectionEdit(id): AtlasCollectionEditView(collectionId: id)
            case let .atlasCollectionDetail(slug, autoSave):
                AtlasCollectionDetailView(slug: slug, autoSave: autoSave)
            case let .authorProfile(handle, isSelf):
                AtlasAuthorProfileView(handle: handle, isSelf: isSelf)
            case .studyCategories: StudyCategoriesPickerView()
            case let .studyLanding(mode): StudyLauncherView(mode: mode)
            // The id says where it goes. `saved:` items are other people's
            // work, so they open on the public detail — author, 取消收藏,
            // 檢舉 — rather than the word screen, which has none of those.
            // Deciding here keeps every entry point (圖鑑, search, anything
            // later) on the same destination without each one re-checking.
            case let .wordDetail(id):
                if let slug = id.savedCommunitySlug {
                    AtlasSavedItemDetailView(slug: slug)
                } else {
                    WordDetailView(id: id)
                }
            case let .categoryDetail(id): CategoryView(id: id)
            }
        }
    }
}
