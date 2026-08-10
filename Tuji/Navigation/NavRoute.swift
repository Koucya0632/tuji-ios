// Routes pushed onto the MainTabsView NavigationStack. Adding a new
// destination = adding a case here + a switch arm in MainTabsView's
// .navigationDestination block.

import Foundation

// Four cases used to sit here — `cards`, `today`, `atlasPublic` and
// `atlasMyCollections` — each with a live arm in the shared destination table
// that stood up a whole screen. None was ever constructed. `cards` and `today`
// are tab roots, not pushes; `atlasPublic` became one too; and
// `atlasMyCollections` was documented as a deep-link target that no deep link
// ever produced. A route nothing routes to is a destination that cannot be
// reached and cannot be wrong.

enum NavRoute: Hashable {
    case search(query: String?)
    case settings
    /// 圖鑑管理 — opens on the current user's 圖鑑卡片.
    case atlasManage
    /// 編輯合集 — create/edit a single collection (add members, cover, submit).
    case atlasCollectionEdit(id: String)
    /// 公開合集詳情；autoSave is used only to resume a guest's interrupted save.
    ///
    /// `preview` carries the row the user tapped so the header renders
    /// instantly. It is the capability the three sites that bypassed this table
    /// were reaching `navigationDestination(item:)` for — two passed a preview
    /// and one did not, which is exactly the kind of divergence a single case
    /// makes impossible.
    case atlasCollectionDetail(slug: String, autoSave: Bool, preview: AtlasCollection?)
    /// 作者主頁. `isSelf` adds the edit entry point — 我的 pushes its own page
    /// with it set; 物見 opens other people's from the feed.
    case authorProfile(handle: String, isSelf: Bool)
    /// 物見 item detail. Carries the tapped item because the screen renders it
    /// immediately and refreshes in place; four sites used to construct this
    /// destination themselves.
    case atlasPublicItem(item: AtlasPublicItem)
    case studyCategories
    case studyLanding(mode: StudyMode)
    case wordDetail(id: String)
    /// 主題 — the index of every theme. Replaced 圖鑑's theme chip row.
    case categoryIndex
    case categoryDetail(id: String)
}
