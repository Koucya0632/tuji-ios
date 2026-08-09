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
    /// No bearer token required. `APIClient` skips the `AuthService` lookup.
    var isPublic = false
    /// Anonymous access is allowed, but a signed-in caller should still send its
    /// token so the server can reveal account-specific state.
    var usesOptionalAuth = false
    var timeout: TimeInterval = 15
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
    static let publicCached = EndpointPolicy(cachePolicy: .useProtocolCachePolicy, isPublic: true)

    /// Anonymous write (analytics) — nothing to cache.
    static let publicFresh = EndpointPolicy(
        cachePolicy: .reloadIgnoringLocalCacheData,
        isPublic: true
    )

    /// Anonymous read whose response depends on the caller when there is one.
    static let publicFreshOptionalAuth = EndpointPolicy(
        cachePolicy: .reloadIgnoringLocalCacheData,
        isPublic: true,
        usesOptionalAuth: true
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
