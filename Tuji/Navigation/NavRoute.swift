// Routes pushed onto the MainTabsView NavigationStack. Adding a new
// destination = adding a case here + a switch arm in MainTabsView's
// .navigationDestination block.

import Foundation

enum NavRoute: Hashable {
    case cards
    case today
    case search(query: String?)
    case favorites
    case settings
    case atlasManage
    /// 公開圖鑑 — other users' shared 圖鑑 (community).
    case atlasPublic
    /// 我的合集 — the current user's own collections list.
    case atlasMyCollections
    /// 編輯合集 — create/edit a single collection (add members, cover, submit).
    case atlasCollectionEdit(id: String)
    case studyCategories
    case studyLanding(mode: StudyMode)
    case wordDetail(id: String)
    case categoryDetail(id: String)
}
