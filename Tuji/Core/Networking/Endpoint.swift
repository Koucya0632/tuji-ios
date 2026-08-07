// Single source of truth for backend endpoint paths.
//
// Adding an endpoint = adding a case + adding its path here. Don't
// fabricate URL strings at call sites — APIClient won't build them.

import Foundation

enum Endpoint {
    // MARK: - Auth-protected user endpoints

    case usersMe
    case usersProfile
    case usersSettings
    case usersFavorites
    case usersLearned
    case usersSync
    case usersProgress
    case usersMastery
    case usersCustomWords(lang: String, learning: String)
    /// Saved 公開圖鑑 items, shaped as words for the 圖鑑 page's 物見 theme.
    case usersSavedWords(lang: String, learning: String)
    case usersTopWords(type: String, limit: Int)
    case usersDeleteAccount
    case usersPushToken
    case usersPushTokenDelete(deviceId: String)
    case usersFeedback
    /// 封鎖名單 (GET) and 封鎖 (POST). Stored server-side so it follows the
    /// account across devices; applied client-side so the public 物見 feeds keep
    /// their shared CDN cache.
    case usersBlocks
    /// 解除封鎖 (DELETE).
    case usersBlock(handle: String)

    // MARK: - Study (auth-protected)

    case studyQueue(mode: String, limit: Int, new: Int, categories: [String], lang: String)
    case studyAnswer
    case studyStats
    case studyReports

    // MARK: - Custom Atlas (auth-protected)

    case atlasImages(limit: Int)
    case atlasImage(id: String)
    case atlasImageRecognize(id: String, lang: String, learning: String)
    case atlasImageConfirm(id: String, lang: String)
    case atlasItem(id: String)
    case atlasItemCards(id: String)
    case atlasItemEnrich(id: String)
    case atlasItemDetail(id: String)
    case atlasItemWithdraw(id: String)
    case atlasSync(since: String?, limit: Int)
    case atlasFriends(limit: Int)
    case atlasEntitlement

    // MARK: - Community collections 合集 (auth-protected authoring)

    /// GET the current user's collections / POST to create a draft.
    case atlasCollections
    /// GET (edit view) / PATCH / DELETE a single owned collection.
    case atlasCollection(id: String)
    /// POST a private, square collection avatar and receive its public color.
    case atlasCollectionAvatar(id: String)
    /// POST to add one of the owner's confirmed source items.
    case atlasCollectionItems(id: String)
    /// DELETE a member from a collection.
    case atlasCollectionItem(id: String, publicItemId: String)
    /// POST to submit a collection for review.
    case atlasCollectionPublish(id: String)
    /// POST to take an approved collection back off the browse feed.
    case atlasCollectionWithdraw(id: String)
    /// GET the user's confirmed public, pending and private items (add-member picker).
    case atlasCollectionCandidates(lang: String)

    // MARK: - Public 圖鑑 (community; no auth)

    /// Other users' approved public items for one lemma — the word detail
    /// page's 「大家的圖鑑」 section.
    case atlasPublicByLemma(lemma: String, lang: String, limit: Int)
    /// The community wall.
    case atlasPublicFeed(limit: Int)
    /// A community author's profile + their public items. `cacheBust` (a nonce
    /// the self-view always sends) makes the request a distinct edge-cache key,
    /// so an author who just edited their public identity sees the new one
    /// instead of Vercel's 30-minute copy. Visitors send nil and keep the cache.
    case atlasPublicAuthor(handle: String, cacheBust: String?)
    /// One public item by slug — the 圖鑑 page's 物見 cards open through this.
    case atlasPublicItem(slug: String, lang: String)
    /// Save / unsave a community item (auth required; consumption quota).
    case atlasPublicSave(slug: String)
    /// Report a community item (auth required).
    case atlasPublicReport(slug: String)
    /// Report a public 合集 — its title / 簡介 / 頭像, not its members.
    case atlasPublicCollectionReport(slug: String)
    /// Report an author identity — 暱稱 / 簽名 / 頭像.
    case atlasPublicAuthorReport(handle: String)
    /// Language-scoped public collection browse feed. `cacheBust` (a nonce on
    /// force-reload) makes the request a distinct edge-cache key so pull-to-refresh
    /// and post-publish bypass Vercel's CDN copy, not just the on-device cache.
    case atlasPublicCollections(lang: String, limit: Int, cacheBust: String?)
    /// A public collection's detail (meta + author + member items).
    case atlasPublicCollection(slug: String)
    /// Signed-in reader's saved collection shelf.
    case atlasSavedCollections(lang: String, limit: Int)
    /// Save state / save / unsave for one public collection.
    case atlasPublicCollectionSave(slug: String)
    /// Add every remaining unlocked collection item to the study queue.
    case atlasPublicCollectionLearn(slug: String)

    // MARK: - Billing (auth-protected)

    case billingVerify

    // MARK: - Public

    case search(q: String)
    case events
    case words(lang: String, learning: String)
    case word(id: String, lang: String, learning: String)
    case categories(lang: String)

    // MARK: - Smoke (temporary; delete with the backend endpoint)

    case smokeWhoami

    // MARK: -

    var path: String {
        switch self {
        case .usersMe: "/api/users/me"
        case .usersProfile: "/api/users/profile"
        case .usersSettings: "/api/users/settings"
        case .usersFavorites: "/api/users/favorites"
        case .usersLearned: "/api/users/learned"
        case .usersSync: "/api/users/sync"
        case .usersProgress: "/api/users/progress"
        case .usersMastery: "/api/users/mastery"
        case .usersCustomWords: "/api/users/custom-words"
        case .usersSavedWords: "/api/users/saved-words"
        case .usersTopWords: "/api/users/top-words"
        case .usersDeleteAccount: "/api/users/delete-account"
        case .usersBlocks: "/api/users/blocks"
        case let .usersBlock(handle): "/api/users/blocks/\(handle)"
        case .usersPushToken,
             .usersPushTokenDelete: "/api/users/push-token"
        case .usersFeedback: "/api/users/feedback"
        case .studyQueue: "/api/study/queue"
        case .studyAnswer: "/api/study/answer"
        case .studyStats: "/api/study/stats"
        case .studyReports: "/api/study/reports"
        case .atlasImages: "/api/atlas/images"
        case let .atlasImage(id): "/api/atlas/images/\(id)"
        case let .atlasImageRecognize(id, _, _): "/api/atlas/images/\(id)/recognize"
        case let .atlasImageConfirm(id, _): "/api/atlas/images/\(id)/confirm"
        case let .atlasItem(id): "/api/atlas/items/\(id)"
        case let .atlasItemCards(id): "/api/atlas/items/\(id)/cards"
        case let .atlasItemEnrich(id): "/api/atlas/items/\(id)/enrich"
        case let .atlasItemDetail(id): "/api/atlas/items/\(id)/detail"
        case let .atlasItemWithdraw(id): "/api/atlas/items/\(id)/withdraw"
        case .atlasSync: "/api/atlas/sync"
        case .atlasFriends: "/api/atlas/friends"
        case .atlasEntitlement: "/api/atlas/entitlement"
        case .atlasCollections: "/api/atlas/collections"
        case let .atlasCollection(id): "/api/atlas/collections/\(id)"
        case let .atlasCollectionAvatar(id): "/api/atlas/collections/\(id)/avatar"
        case let .atlasCollectionItems(id): "/api/atlas/collections/\(id)/items"
        case let .atlasCollectionItem(id, publicItemId): "/api/atlas/collections/\(id)/items/\(publicItemId)"
        case let .atlasCollectionPublish(id): "/api/atlas/collections/\(id)/publish"
        case let .atlasCollectionWithdraw(id): "/api/atlas/collections/\(id)/withdraw"
        case .atlasCollectionCandidates: "/api/atlas/collections/candidates"
        case .atlasPublicByLemma: "/api/atlas/public/by-lemma"
        case .atlasPublicFeed: "/api/atlas/public"
        case let .atlasPublicAuthor(handle, _): "/api/atlas/public/authors/\(handle)"
        case let .atlasPublicItem(slug, _): "/api/atlas/public/\(slug)"
        case let .atlasPublicSave(slug): "/api/atlas/public/\(slug)/save"
        case let .atlasPublicReport(slug): "/api/atlas/public/\(slug)/report"
        case let .atlasPublicCollectionReport(slug):
            "/api/atlas/public/collections/\(slug)/report"
        case let .atlasPublicAuthorReport(handle):
            "/api/atlas/public/authors/\(handle)/report"
        case .atlasPublicCollections: "/api/atlas/public/collections"
        case let .atlasPublicCollection(slug): "/api/atlas/public/collections/\(slug)"
        case .atlasSavedCollections: "/api/atlas/public/collections/saved"
        case let .atlasPublicCollectionSave(slug): "/api/atlas/public/collections/\(slug)/save"
        case let .atlasPublicCollectionLearn(slug): "/api/atlas/public/collections/\(slug)/learn"
        case .billingVerify: "/api/billing/verify"
        case .search: "/api/search"
        case .events: "/api/events"
        case .words: "/api/words"
        case let .word(id, _, _): "/api/words/\(id)"
        case .categories: "/api/categories"
        case .smokeWhoami: "/api/test_smoke/whoami"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case let .studyQueue(mode, limit, new, categories, lang):
            [
                URLQueryItem(name: "mode", value: mode),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "new", value: String(new)),
                // Comma-separated category ids; empty = no filter (study all).
                // Backend strips empty / "all" sentinels for us.
                URLQueryItem(name: "category", value: categories.joined(separator: ",")),
                // Gloss language follows the live UI language, not the
                // debounced server settings.
                URLQueryItem(name: "lang", value: lang)
            ]
        case let .search(q):
            [URLQueryItem(name: "q", value: q)]
        case let .usersPushTokenDelete(deviceId):
            [URLQueryItem(name: "deviceId", value: deviceId)]
        case let .usersTopWords(type, limit):
            [
                URLQueryItem(name: "type", value: type),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        case let .atlasImages(limit),
             let .atlasFriends(limit),
             let .atlasPublicFeed(limit):
            [URLQueryItem(name: "limit", value: String(limit))]
        case let .atlasSync(since, limit):
            [
                since.map { URLQueryItem(name: "since", value: $0) },
                URLQueryItem(name: "limit", value: String(limit))
            ].compactMap(\.self)
        case let .usersCustomWords(lang, learning),
             let .usersSavedWords(lang, learning):
            // ?lang= / ?learning= win over the server-stored setting right after
            // an in-app switch (the settings save is debounced). Without the
            // live learning direction the custom 圖鑑 comes back for the *old*
            // target language until the debounced POST lands.
            [
                URLQueryItem(name: "lang", value: lang),
                URLQueryItem(name: "learning", value: learning)
            ]
        case let .atlasImageRecognize(_, lang, learning):
            // Recognition's candidate gloss + target labels follow the user's
            // live UI language and learning direction, not the debounced
            // server settings — otherwise the meaning field comes back empty.
            [
                URLQueryItem(name: "lang", value: lang),
                URLQueryItem(name: "learning", value: learning)
            ]
        case let .atlasImageConfirm(_, lang):
            [URLQueryItem(name: "lang", value: lang)]
        case let .atlasPublicByLemma(lemma, lang, limit):
            // `lang` is required by the backend: the same spelling can exist in
            // both decks, so omitting it would mix languages into one list.
            [
                URLQueryItem(name: "lemma", value: lemma),
                URLQueryItem(name: "lang", value: lang),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        case let .atlasPublicCollections(lang, limit, cacheBust):
            // `lang` scopes the browse feed to the user's current learning
            // direction, so it's required (the backend 400s without it).
            [
                URLQueryItem(name: "lang", value: lang),
                URLQueryItem(name: "limit", value: String(limit))
            ] + (cacheBust.map { [URLQueryItem(name: "_cb", value: $0)] } ?? [])
        case let .atlasSavedCollections(lang, limit):
            [
                URLQueryItem(name: "lang", value: lang),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        case let .atlasPublicAuthor(_, cacheBust):
            cacheBust.map { [URLQueryItem(name: "_cb", value: $0)] } ?? []
        case let .atlasPublicItem(_, lang):
            [URLQueryItem(name: "lang", value: lang)]
        case let .atlasCollectionCandidates(lang):
            [URLQueryItem(name: "lang", value: lang)]
        case let .words(lang, learning),
             let .word(_, lang, learning):
            [
                URLQueryItem(name: "lang", value: lang),
                URLQueryItem(name: "learning", value: learning)
            ]
        case let .categories(lang):
            [URLQueryItem(name: "lang", value: lang)]
        default:
            []
        }
    }

    /// URLCache behavior for this endpoint. Public endpoints honor the
    /// server's Cache-Control headers; user / mutating endpoints bypass
    /// the cache so writes immediately reflect.
    var cachePolicy: URLRequest.CachePolicy {
        switch self {
        // Community reads are public and CDN-cached server-side; honor it.
        case .words, .word, .categories, .search,
             .atlasPublicByLemma, .atlasPublicFeed, .atlasPublicAuthor, .atlasPublicItem,
             .atlasPublicCollections:
            .useProtocolCachePolicy
        case .studyAnswer, .studyReports, .events, .usersSync, .usersMastery,
             .usersDeleteAccount, .usersPushToken, .usersPushTokenDelete,
             .usersFeedback, .usersCustomWords, .usersSavedWords,
             .usersBlocks, .usersBlock,
             .atlasImages, .atlasImage, .atlasImageRecognize, .atlasImageConfirm,
             .atlasItem, .atlasItemCards, .atlasItemEnrich, .atlasItemDetail,
             .atlasItemWithdraw, .atlasSync, .atlasFriends, .atlasEntitlement,
             .atlasCollections, .atlasCollection, .atlasCollectionAvatar, .atlasCollectionItems,
             .atlasCollectionItem, .atlasCollectionPublish, .atlasCollectionWithdraw,
             .atlasCollectionCandidates,
             .atlasPublicSave, .atlasPublicReport,
             .atlasPublicCollectionReport, .atlasPublicAuthorReport,
             .atlasPublicCollection, .atlasSavedCollections,
             .atlasPublicCollectionSave, .atlasPublicCollectionLearn,
             .billingVerify:
            .reloadIgnoringLocalCacheData
        default:
            .useProtocolCachePolicy
        }
    }

    /// Public endpoints that don't require a bearer token. APIClient
    /// skips the AuthService lookup for these.
    ///
    /// smokeWhoami is technically anonymous-friendly (returns null), but
    /// we keep it authed here so MainTabs' button actually exercises
    /// the Bearer path. The backend tolerates either.
    var isPublic: Bool {
        switch self {
        // Save / report stay authed — only the reads are anonymous.
        case .events, .search, .word, .words, .categories,
             .atlasPublicByLemma, .atlasPublicFeed, .atlasPublicAuthor, .atlasPublicItem,
             .atlasPublicCollections, .atlasPublicCollection: true
        default: false
        }
    }

    /// Anonymous access is allowed, but a signed-in request should include its
    /// bearer token so the server can reveal account-specific access state.
    var usesOptionalAuth: Bool {
        if case .atlasPublicCollection = self { return true }
        return false
    }

    /// Per-request timeout (seconds). AI endpoints — image recognition (Google
    /// Vision primary / OpenAI gpt-4o "高精度" escalate) and enrichment / detail
    /// (gpt-4o-mini, incl. lazy enrich on first open) — can take far longer than
    /// a normal call, so they override the short default upward.
    var timeout: TimeInterval {
        switch self {
        case .atlasImages, .atlasCollectionAvatar, .atlasImageRecognize,
             .atlasItemEnrich, .atlasItemDetail:
            60
        default:
            15
        }
    }
}
