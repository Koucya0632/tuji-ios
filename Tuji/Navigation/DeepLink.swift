// Parses `tuji://...` URLs into a target (tab, route).
//
// Routes (per design book §I.9.3):
//
//   tuji://today                        →  Today tab root
//   tuji://cards                        →  Cards tab root
//   tuji://me                           →  Me tab root
//   tuji://community                    →  Community tab root
//   tuji://favorites                    →  Cards tab, 書籤 source filter
//   tuji://settings                     →  Me tab → Settings
//   tuji://search?q=word                →  Cards tab → Search (auto-fills q)
//   tuji://word/{id}                    →  Cards tab → WordDetail
//   tuji://category/{id}                →  Cards tab → CategoryDetail
//   tuji://study?mode=new|review        →  Today tab → StudyLanding
//
// Universal Links (`https://tuji.app/...`) hit the same matcher — see
// TujiApp.handleIncoming(_:).

import Foundation

enum TujiDeepLink: Hashable {
    case today
    case cards
    case me
    case community
    case favorites
    case settings
    case search(query: String?)
    case word(id: String)
    case category(id: String)
    case study(mode: StudyMode)
    case collection(slug: String, autoSave: Bool)

    /// Which tab should be foregrounded before pushing the route.
    var tab: MainTab {
        switch self {
        case .today, .study: .today
        case .me: .me
        case .cards, .search, .word, .category: .cards
        case .collection, .community: .community
        case .settings: .me
        // 我的收藏 stopped being a screen: bookmarks are a *source* of words,
        // so they are a filter value on 圖鑑 (D.6). The public link still has to
        // mean what it always meant, so it selects that filter rather than
        // dropping the user on an unfiltered grid.
        case .favorites: .cards
        }
    }

    /// Optional NavRoute to push onto the tab's NavigationStack after
    /// switching. nil = just switch tabs to the root.
    var route: NavRoute? {
        switch self {
        case .today, .cards, .me, .community, .favorites: nil
        case .settings: .settings
        case let .search(q): .search(query: q)
        case let .word(id): .wordDetail(id: id)
        case let .category(id): .categoryDetail(id: id)
        case let .study(mode): .studyLanding(mode: mode)
        case let .collection(slug, autoSave):
            .atlasCollectionDetail(slug: slug, autoSave: autoSave)
        }
    }

    /// Returns nil if the URL doesn't match a known route.
    static func from(_ url: URL) -> TujiDeepLink? {
        // Accept both tuji:// and https://tuji.app/ shells.
        let isTujiScheme = url.scheme == "tuji"
        let isUniversal = url.scheme == "https" && url.host == "tuji.app"
        guard isTujiScheme || isUniversal else { return nil }

        // For tuji://, url.host is the first path token. For https://,
        // url.host is "tuji.app" and the path provides everything.
        let segments: [String] = if isUniversal {
            url.pathComponents.filter { $0 != "/" }
        } else {
            ([url.host].compactMap(\.self) + url.pathComponents.filter { $0 != "/" })
        }
        guard let head = segments.first else { return nil }
        let qs = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return self.matchHead(head, segments: segments, queryItems: qs)
    }

    private static func matchHead(
        _ head: String,
        segments: [String],
        queryItems: [URLQueryItem]
    )
        -> TujiDeepLink?
    {
        let q = { (name: String) in queryItems.first { $0.name == name }?.value }
        switch head {
        case "today": return .today
        case "cards": return .cards
        case "me": return .me
        case "community": return .community
        case "favorites": return .favorites
        case "settings": return .settings
        case "search": return .search(query: q("q"))
        case "study":
            return .study(mode: q("mode") == "review" ? .review : .new)
        case "word":
            guard segments.count >= 2 else { return nil }
            return .word(id: segments[1])
        case "category":
            guard segments.count >= 2 else { return nil }
            return .category(id: segments[1])
        case "collection":
            guard segments.count >= 2 else { return nil }
            return .collection(slug: segments[1], autoSave: false)
        default:
            return nil
        }
    }
}
