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
    /// 圖鑑管理 — opens on the current user's 圖鑑卡片.
    case atlasManage
    /// 公開圖鑑 — other users' shared 圖鑑 (community).
    case atlasPublic
    /// Compatibility/deep-link route into 圖鑑管理's 合集 section.
    case atlasMyCollections
    /// 編輯合集 — create/edit a single collection (add members, cover, submit).
    case atlasCollectionEdit(id: String)
    /// 公開合集詳情；autoSave is used only to resume a guest's interrupted save.
    case atlasCollectionDetail(slug: String, autoSave: Bool)
    case studyCategories
    case studyLanding(mode: StudyMode)
    case wordDetail(id: String)
    case categoryDetail(id: String)
}
