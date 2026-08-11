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

    case search(q: String, lang: String, learning: String)
    case events
    case words(lang: String, learning: String)
    case word(id: String, lang: String, learning: String)
    case categories(lang: String)

    // MARK: - Smoke (temporary; delete with the backend endpoint)

    case smokeWhoami

    // MARK: -

    /// One switch, one endpoint, every fact about it in one arm.
    ///
    /// This replaced six parallel exhaustive switches over the same 61 cases
    /// (`path`, `queryItems`, `cachePolicy`, `isPublic`, `usesOptionalAuth`,
    /// `timeout`). Adding an endpoint meant editing up to six of them, and one
    /// endpoint's facts were smeared across 354 lines — which is how ten
    /// endpoints came to have their cache policy decided by a `default:` arm.
    ///
    /// No `default:` here, and none in `EndpointPolicy.cachePolicy`: a new case
    /// does not compile until someone has answered every question about it.
    var descriptor: EndpointDescriptor {
        switch self {
        // MARK: Auth-protected user endpoints

        case .usersMe:
            EndpointDescriptor(path: "/api/users/me", policy: .privateServerCached)
        case .usersProfile:
            EndpointDescriptor(path: "/api/users/profile", policy: .privateServerCached)
        case .usersSettings:
            EndpointDescriptor(path: "/api/users/settings", policy: .privateServerCached)
        case .usersFavorites:
            EndpointDescriptor(path: "/api/users/favorites", policy: .privateServerCached)
        case .usersLearned:
            EndpointDescriptor(path: "/api/users/learned", policy: .privateServerCached)
        case .usersSync:
            EndpointDescriptor(path: "/api/users/sync", policy: .privateFresh)
        case .usersProgress:
            EndpointDescriptor(path: "/api/users/progress", policy: .privateServerCached)
        case .usersMastery:
            EndpointDescriptor(path: "/api/users/mastery", policy: .privateFresh)
        case let .usersCustomWords(lang, learning):
            // ?lang= / ?learning= win over the server-stored setting right after
            // an in-app switch (the settings save is debounced). Without the
            // live learning direction the custom 圖鑑 comes back for the *old*
            // target language until the debounced POST lands.
            EndpointDescriptor(
                path: "/api/users/custom-words",
                queryItems: [
                    URLQueryItem(name: "lang", value: lang),
                    URLQueryItem(name: "learning", value: learning)
                ],
                policy: .privateFresh
            )
        case let .usersSavedWords(lang, learning):
            EndpointDescriptor(
                path: "/api/users/saved-words",
                queryItems: [
                    URLQueryItem(name: "lang", value: lang),
                    URLQueryItem(name: "learning", value: learning)
                ],
                policy: .privateFresh
            )
        case let .usersTopWords(type, limit):
            EndpointDescriptor(
                path: "/api/users/top-words",
                queryItems: [
                    URLQueryItem(name: "type", value: type),
                    URLQueryItem(name: "limit", value: String(limit))
                ],
                policy: .privateServerCached
            )
        case .usersDeleteAccount:
            EndpointDescriptor(path: "/api/users/delete-account", policy: .privateFresh)
        case .usersPushToken:
            EndpointDescriptor(path: "/api/users/push-token", policy: .privateFresh)
        case let .usersPushTokenDelete(deviceId):
            EndpointDescriptor(
                path: "/api/users/push-token",
                queryItems: [URLQueryItem(name: "deviceId", value: deviceId)],
                policy: .privateFresh
            )
        case .usersFeedback:
            EndpointDescriptor(path: "/api/users/feedback", policy: .privateFresh)
        case .usersBlocks:
            EndpointDescriptor(path: "/api/users/blocks", policy: .privateFresh)
        case let .usersBlock(handle):
            EndpointDescriptor(path: "/api/users/blocks/\(handle)", policy: .privateFresh)

        // MARK: Study
        case let .studyQueue(mode, limit, new, categories, lang):
            EndpointDescriptor(
                path: "/api/study/queue",
                queryItems: [
                    URLQueryItem(name: "mode", value: mode),
                    URLQueryItem(name: "limit", value: String(limit)),
                    URLQueryItem(name: "new", value: String(new)),
                    // Comma-separated category ids; empty = no filter (study all).
                    // Backend strips empty / "all" sentinels for us.
                    URLQueryItem(name: "category", value: categories.joined(separator: ",")),
                    // Gloss language follows the live UI language, not the
                    // debounced server settings.
                    URLQueryItem(name: "lang", value: lang)
                ],
                policy: .privateServerCached
            )
        case .studyAnswer:
            EndpointDescriptor(path: "/api/study/answer", policy: .privateFresh)
        case .studyStats:
            EndpointDescriptor(path: "/api/study/stats", policy: .privateServerCached)
        case .studyReports:
            EndpointDescriptor(path: "/api/study/reports", policy: .privateFresh)

        // MARK: Custom Atlas
        case let .atlasImages(limit):
            EndpointDescriptor(
                path: "/api/atlas/images",
                queryItems: [URLQueryItem(name: "limit", value: String(limit))],
                policy: .privateFreshSlow
            )
        case let .atlasImage(id):
            EndpointDescriptor(path: "/api/atlas/images/\(id)", policy: .privateFresh)
        case let .atlasImageRecognize(id, lang, learning):
            // Recognition's candidate gloss + target labels follow the user's
            // live UI language and learning direction, not the debounced
            // server settings — otherwise the meaning field comes back empty.
            EndpointDescriptor(
                path: "/api/atlas/images/\(id)/recognize",
                queryItems: [
                    URLQueryItem(name: "lang", value: lang),
                    URLQueryItem(name: "learning", value: learning)
                ],
                policy: .privateFreshSlow
            )
        case let .atlasImageConfirm(id, lang):
            EndpointDescriptor(
                path: "/api/atlas/images/\(id)/confirm",
                queryItems: [URLQueryItem(name: "lang", value: lang)],
                policy: .privateFresh
            )
        case let .atlasItem(id):
            EndpointDescriptor(path: "/api/atlas/items/\(id)", policy: .privateFresh)
        case let .atlasItemCards(id):
            EndpointDescriptor(path: "/api/atlas/items/\(id)/cards", policy: .privateFresh)
        case let .atlasItemEnrich(id):
            EndpointDescriptor(path: "/api/atlas/items/\(id)/enrich", policy: .privateFreshSlow)
        case let .atlasItemDetail(id):
            EndpointDescriptor(path: "/api/atlas/items/\(id)/detail", policy: .privateFreshSlow)
        case let .atlasItemWithdraw(id):
            EndpointDescriptor(path: "/api/atlas/items/\(id)/withdraw", policy: .privateFresh)
        case let .atlasSync(since, limit):
            EndpointDescriptor(
                path: "/api/atlas/sync",
                queryItems: [
                    since.map { URLQueryItem(name: "since", value: $0) },
                    URLQueryItem(name: "limit", value: String(limit))
                ].compactMap(\.self),
                policy: .privateFresh
            )
        case let .atlasFriends(limit):
            EndpointDescriptor(
                path: "/api/atlas/friends",
                queryItems: [URLQueryItem(name: "limit", value: String(limit))],
                policy: .privateFresh
            )
        case .atlasEntitlement:
            EndpointDescriptor(path: "/api/atlas/entitlement", policy: .privateFresh)

        // MARK: Community collections 合集 (authoring)
        case .atlasCollections:
            EndpointDescriptor(path: "/api/atlas/collections", policy: .privateFresh)
        case let .atlasCollection(id):
            EndpointDescriptor(path: "/api/atlas/collections/\(id)", policy: .privateFresh)
        case let .atlasCollectionAvatar(id):
            EndpointDescriptor(
                path: "/api/atlas/collections/\(id)/avatar",
                policy: .privateFreshSlow
            )
        case let .atlasCollectionItems(id):
            EndpointDescriptor(path: "/api/atlas/collections/\(id)/items", policy: .privateFresh)
        case let .atlasCollectionItem(id, publicItemId):
            EndpointDescriptor(
                path: "/api/atlas/collections/\(id)/items/\(publicItemId)",
                policy: .privateFresh
            )
        case let .atlasCollectionPublish(id):
            EndpointDescriptor(path: "/api/atlas/collections/\(id)/publish", policy: .privateFresh)
        case let .atlasCollectionWithdraw(id):
            EndpointDescriptor(path: "/api/atlas/collections/\(id)/withdraw", policy: .privateFresh)
        case let .atlasCollectionCandidates(lang):
            EndpointDescriptor(
                path: "/api/atlas/collections/candidates",
                queryItems: [URLQueryItem(name: "lang", value: lang)],
                policy: .privateFresh
            )

        // MARK: Public 圖鑑 (community)
        case let .atlasPublicByLemma(lemma, lang, limit):
            // `lang` is required by the backend: the same spelling can exist in
            // both decks, so omitting it would mix languages into one list.
            EndpointDescriptor(
                path: "/api/atlas/public/by-lemma",
                queryItems: [
                    URLQueryItem(name: "lemma", value: lemma),
                    URLQueryItem(name: "lang", value: lang),
                    URLQueryItem(name: "limit", value: String(limit))
                ],
                policy: .publicCached
            )
        case let .atlasPublicFeed(limit):
            EndpointDescriptor(
                path: "/api/atlas/public",
                queryItems: [URLQueryItem(name: "limit", value: String(limit))],
                policy: .publicCached
            )
        case let .atlasPublicAuthor(handle, cacheBust):
            EndpointDescriptor(
                path: "/api/atlas/public/authors/\(handle)",
                queryItems: cacheBust.map { [URLQueryItem(name: "_cb", value: $0)] } ?? [],
                policy: .publicCached
            )
        case let .atlasPublicItem(slug, lang):
            EndpointDescriptor(
                path: "/api/atlas/public/\(slug)",
                queryItems: [URLQueryItem(name: "lang", value: lang)],
                policy: .publicCached
            )
        case let .atlasPublicSave(slug):
            EndpointDescriptor(path: "/api/atlas/public/\(slug)/save", policy: .privateFresh)
        case let .atlasPublicReport(slug):
            EndpointDescriptor(path: "/api/atlas/public/\(slug)/report", policy: .privateFresh)
        case let .atlasPublicCollectionReport(slug):
            EndpointDescriptor(
                path: "/api/atlas/public/collections/\(slug)/report",
                policy: .privateFresh
            )
        case let .atlasPublicAuthorReport(handle):
            EndpointDescriptor(
                path: "/api/atlas/public/authors/\(handle)/report",
                policy: .privateFresh
            )
        case let .atlasPublicCollections(lang, limit, cacheBust):
            // `lang` scopes the browse feed to the user's current learning
            // direction, so it's required (the backend 400s without it).
            EndpointDescriptor(
                path: "/api/atlas/public/collections",
                queryItems: [
                    URLQueryItem(name: "lang", value: lang),
                    URLQueryItem(name: "limit", value: String(limit))
                ] + (cacheBust.map { [URLQueryItem(name: "_cb", value: $0)] } ?? []),
                policy: .publicCached
            )
        case let .atlasPublicCollection(slug):
            EndpointDescriptor(
                path: "/api/atlas/public/collections/\(slug)",
                policy: .publicFreshOptionalAuth
            )
        case let .atlasSavedCollections(lang, limit):
            EndpointDescriptor(
                path: "/api/atlas/public/collections/saved",
                queryItems: [
                    URLQueryItem(name: "lang", value: lang),
                    URLQueryItem(name: "limit", value: String(limit))
                ],
                policy: .privateFresh
            )
        case let .atlasPublicCollectionSave(slug):
            EndpointDescriptor(
                path: "/api/atlas/public/collections/\(slug)/save",
                policy: .privateFresh
            )
        case let .atlasPublicCollectionLearn(slug):
            EndpointDescriptor(
                path: "/api/atlas/public/collections/\(slug)/learn",
                policy: .privateFresh
            )

        // MARK: Billing
        case .billingVerify:
            EndpointDescriptor(path: "/api/billing/verify", policy: .privateFresh)

        // MARK: Public
        case let .search(q, lang, learning):
            // The response is direction-scoped — 搜尋日文/假名 and 搜尋英文 return
            // different rows for the same query — and the policy is
            // `.publicCached`, so leaving the direction out of the URL gave both
            // directions one cache entry: switching 學習語言 and repeating a
            // search could be served the other language's results out of
            // URLCache. Identity, not a hint.
            EndpointDescriptor(
                path: "/api/search",
                queryItems: [
                    URLQueryItem(name: "q", value: q),
                    URLQueryItem(name: "lang", value: lang),
                    URLQueryItem(name: "learning", value: learning)
                ],
                policy: .publicCached
            )
        case .events:
            EndpointDescriptor(path: "/api/events", policy: .publicFresh)
        case let .words(lang, learning):
            EndpointDescriptor(
                path: "/api/words",
                queryItems: [
                    URLQueryItem(name: "lang", value: lang),
                    URLQueryItem(name: "learning", value: learning)
                ],
                policy: .publicCached
            )
        case let .word(id, lang, learning):
            EndpointDescriptor(
                path: "/api/words/\(id)",
                queryItems: [
                    URLQueryItem(name: "lang", value: lang),
                    URLQueryItem(name: "learning", value: learning)
                ],
                policy: .publicCached
            )
        case let .categories(lang):
            EndpointDescriptor(
                path: "/api/categories",
                queryItems: [URLQueryItem(name: "lang", value: lang)],
                policy: .publicCached
            )

        // MARK: Smoke
        // Technically anonymous-friendly (returns null), but kept authed so the
        // 我的 debug button actually exercises the Bearer path. The backend
        // tolerates either.
        case .smokeWhoami:
            EndpointDescriptor(path: "/api/test_smoke/whoami", policy: .privateServerCached)
        }
    }

    /// Forwards kept because they read better at the two call sites that want
    /// one fact — logging (`path`) and the 401-retry guard (`isPublic`).
    /// `APIClient.buildRequest` reads the whole descriptor once instead.
    var path: String {
        self.descriptor.path
    }

    var isPublic: Bool {
        self.descriptor.policy.isPublic
    }
}
