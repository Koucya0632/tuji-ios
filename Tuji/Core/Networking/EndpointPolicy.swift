import Foundation

/// Everything about a request that is not its path or its query — how it
/// authenticates, how it caches, how long it may take.
///
/// `cachePolicy` has **no default on purpose**. It used to be decided by a
/// `default:` arm, and ten endpoints reached it by omission — nine of them
/// authenticated private reads (`usersMe`, `usersSettings`, `usersProgress`,
/// `studyQueue`, …). Whether a user's own data may sit in `URLCache` is not a
/// question anyone should answer by forgetting to answer it. The other three
/// fields do default, because absent genuinely means "none / no / standard" and
/// getting them wrong fails loudly (a 401, not stale personal data).
struct EndpointPolicy {
    let cachePolicy: URLRequest.CachePolicy
    var access: EndpointAccess = .authenticated
    var timeout: TimeInterval = 15
}

/// How a request authenticates. One value, three cases — it used to be two
/// independent `Bool`s, which made two illegal states representable and one
/// word mean two things.
///
/// `usesOptionalAuth: true, isPublic: false` compiled and was silently ignored,
/// because `APIClient` only reached the optional branch inside `else`. And
/// `isPublic` answered *two* questions that part company on exactly one
/// endpoint: 「attach no bearer」 (`buildRequest`) and 「never retry a 401」
/// (`execute`). `.atlasPublicCollection` is `optionalToken`, so a signed-in
/// caller *does* send a token — and its 401 was the one 401 never retried,
/// leaving the user looking at the guest view of a collection they had saved.
enum EndpointAccess: Equatable {
    /// A bearer token is required; the request cannot be made without one.
    case authenticated
    /// No token, ever. The response is the same for everybody.
    case anonymous
    /// Usable signed out, but a signed-in caller sends its token so the server
    /// can reveal account-specific state (「已收藏」 and the like).
    case optionalToken

    /// `APIClient` must fetch a token before sending.
    var requiresToken: Bool {
        self == .authenticated
    }

    /// `APIClient` should attach a token if one happens to be available.
    var attachesTokenWhenAvailable: Bool {
        self == .optionalToken
    }

    /// A 401 is worth one refresh-and-retry. True wherever a token may have
    /// been attached — which includes `optionalToken`, the case the old
    /// `!isPublic` guard excluded.
    var mayRetryUnauthorized: Bool {
        self != .anonymous
    }

    /// Whether a response for this access level may sit in the shared
    /// `URLCache`. Anything that can vary by caller may not: the cache is
    /// disk-backed and shared across accounts on the device.
    var mayBeCachedAcrossCallers: Bool {
        self == .anonymous
    }
}

extension EndpointPolicy {
    /// Authenticated, never served from `URLCache` — user data and every write.
    static let privateFresh = EndpointPolicy(cachePolicy: .reloadIgnoringLocalCacheData)

    /// Authenticated, but honours the server's `Cache-Control`.
    ///
    /// This is what the ten formerly-defaulted endpoints were already getting.
    /// Pinned rather than changed: switching them to `privateFresh` would be a
    /// behaviour change (every 首頁 / 設定 / 進度 open goes to the network), and
    /// that is a product decision, not a refactor. Named so it now reads as a
    /// choice someone made.
    static let privateServerCached = EndpointPolicy(cachePolicy: .useProtocolCachePolicy)

    /// Anonymous read behind the CDN; honours `Cache-Control`.
    static let publicCached = EndpointPolicy(
        cachePolicy: .useProtocolCachePolicy,
        access: .anonymous
    )

    /// Anonymous write (analytics) — nothing to cache.
    static let publicFresh = EndpointPolicy(
        cachePolicy: .reloadIgnoringLocalCacheData,
        access: .anonymous
    )

    /// Anonymous read whose response depends on the caller when there is one.
    static let publicFreshOptionalAuth = EndpointPolicy(
        cachePolicy: .reloadIgnoringLocalCacheData,
        access: .optionalToken
    )

    /// Authenticated AI call — image recognition (Vision primary / gpt-4o 高精度)
    /// and enrichment / detail (gpt-4o-mini, incl. lazy enrich on first open).
    /// These take far longer than a normal call.
    static let privateFreshSlow = EndpointPolicy(
        cachePolicy: .reloadIgnoringLocalCacheData,
        timeout: 60
    )
}

/// One endpoint's complete description. Built once per request by `APIClient`.
struct EndpointDescriptor {
    let path: String
    var queryItems: [URLQueryItem] = []
    let policy: EndpointPolicy
}
