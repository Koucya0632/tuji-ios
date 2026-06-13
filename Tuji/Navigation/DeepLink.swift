// Parses `tuji://...` URLs into a target (tab, route).
//
// Routes (per design book §I.9.3):
//
//   tuji://today                        →  Today tab root
//   tuji://cards                        →  Cards tab root
//   tuji://favorites                    →  Me tab → Favorites
//   tuji://settings                     →  Me tab → Settings
//   tuji://search?q=word                →  Cards tab → Search (auto-fills q
//                                          if the field listens; v1 just
//                                          opens the empty search)
//   tuji://word/{id}                    →  Cards tab → WordDetail
//   tuji://category/{id}                →  Cards tab → CategoryDetail
//   tuji://study?mode=new|review        →  Tuji center tab → StudyLanding
//
// Universal Links (`https://tuji.app/...`) hit the same matcher — see
// TujiApp.handleIncoming(_:).

import Foundation

enum TujiDeepLink: Hashable {
    case today
    case cards
    case favorites
    case settings
    case search(query: String?)
    case word(id: String)
    case category(id: String)
    case study(mode: StudyMode)

    /// Which tab should be foregrounded before pushing the route.
    var tab: MainTab {
        switch self {
        case .today: .today
        case .cards, .search, .word, .category: .cards
        case .study: .tuji
        case .favorites, .settings: .me
        }
    }

    /// Optional NavRoute to push onto the tab's NavigationStack after
    /// switching. nil = just switch tabs to the root.
    var route: NavRoute? {
        switch self {
        case .today, .cards: nil
        case .favorites: .favorites
        case .settings: .settings
        case .search: .search
        case let .word(id): .wordDetail(id: id)
        case let .category(id): .categoryDetail(id: id)
        case let .study(mode): .studyLanding(mode: mode)
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
        default:
            return nil
        }
    }
}
