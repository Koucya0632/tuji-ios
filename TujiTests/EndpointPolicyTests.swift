// Characterisation net for the Endpoint descriptor refactor.
//
// The refactor collapsed six parallel switches into one and removed the
// `default:` arm that was deciding cache policy for ten endpoints by omission.
// It was meant to change *nothing* about what goes on the wire, so these tests
// pin the table — especially the ten that used to be defaulted, whose current
// behaviour (`.useProtocolCachePolicy`) is now written down rather than
// inherited from a fall-through.
//
// NOTE: `Endpoint` has associated values so it cannot be `CaseIterable`; the
// sample list below is maintained by hand. The compiler already forces a new
// case to declare its own descriptor (no `default:` arm), so the risk a missing
// sample carries is a missing *assertion*, not a missing policy.

import Foundation
import Testing
@testable import Tuji

struct EndpointPolicyTests {
    /// One value per case, in declaration order.
    private static let all: [Endpoint] = [
        .usersMe, .usersProfile, .usersSettings, .usersFavorites,
        .usersSync, .usersProgress(learning: "zh-en"), .usersProgressClear,
        .usersMastery(learning: "zh-en"),
        .usersCustomWords(lang: "zh-Hant", learning: "en"),
        .usersSavedWords(lang: "zh-Hant", learning: "en"),
        .usersTopWords(type: "weak", limit: 3),
        .usersDeleteAccount, .usersPushToken,
        .usersPushTokenDelete(deviceId: "d1"), .usersFeedback,
        .usersBlocks, .usersBlock(handle: "TJ1"),
        .studyQueue(mode: "review", limit: 10, new: 0, categories: [], lang: "zh-Hant", learning: "zh-en"),
        .studyAnswer, .studyStats(learning: "zh-en"), .studyReports,
        .atlasImages(limit: 20), .atlasImage(id: "i1"),
        .atlasImageRecognize(id: "i1", lang: "zh-Hant", learning: "en"),
        .atlasImageConfirm(id: "i1", lang: "zh-Hant"),
        .atlasItemCards(id: "t1"), .atlasItemEnrich(id: "t1"),
        .atlasItemDetail(id: "t1"), .atlasItemWithdraw(id: "t1"),
        .atlasSync(since: nil, limit: 50), .atlasEntitlement,
        .atlasCollections, .atlasCollection(id: "c1"), .atlasCollectionAvatar(id: "c1"),
        .atlasCollectionItems(id: "c1"), .atlasCollectionItem(id: "c1", publicItemId: "p1"),
        .atlasCollectionPublish(id: "c1"), .atlasCollectionWithdraw(id: "c1"),
        .atlasCollectionCandidates(lang: "en"),
        .atlasPublicByLemma(lemma: "cup", lang: "en", limit: 5),
        .atlasPublicFeed(limit: 20),
        .atlasPublicAuthor(handle: "TJ1", cacheBust: nil),
        .atlasPublicItem(slug: "s1", lang: "en"),
        .atlasPublicSave(slug: "s1"), .atlasPublicReport(slug: "s1"),
        .atlasPublicCollectionReport(slug: "s1"), .atlasPublicAuthorReport(handle: "TJ1"),
        .atlasPublicCollections(lang: "en", limit: 20, cacheBust: nil),
        .atlasPublicCollection(slug: "s1"),
        .atlasSavedCollections(lang: "en", limit: 20),
        .atlasPublicCollectionSave(slug: "s1"), .atlasPublicCollectionLearn(slug: "s1"),
        .billingVerify,
        .search(q: "cup", lang: "zh-Hant", learning: "en"), .events,
        .words(lang: "zh-Hant", learning: "en"),
        .word(id: "w1", lang: "zh-Hant", learning: "en"),
        .categories(lang: "zh-Hant"),
        .smokeWhoami
    ]

    @Test("every endpoint is accounted for")
    func sampleCoversEveryCase() {
        #expect(Self.all.count == 59)
        // …and no path appears twice. The count alone cannot tell a missing
        // sample from a duplicated one, and a *missing* sample is exempt from
        // every invariant below — including 「no authenticated endpoint may be
        // served from URLCache」. Swift cannot derive `CaseIterable` for an enum
        // with associated values, so the list stays hand-maintained; this at
        // least makes the count mean what it looks like it means.
        let identities = Self.all.map { ep -> String in
            let d = ep.descriptor
            let query = d.queryItems.map { "\($0.name)=\($0.value ?? "")" }.sorted().joined(separator: "&")
            return "\(d.path)?\(query)"
        }
        #expect(Set(identities).count == identities.count)
    }

    @Test("every path is rooted at /api and carries no query string")
    func pathsAreWellFormed() {
        for ep in Self.all {
            let path = ep.descriptor.path
            #expect(path.hasPrefix("/api/"), "\(path) must be an /api path")
            #expect(!path.contains("?"), "\(path) must not smuggle a query string")
        }
    }

    /// The ten that used to reach `.useProtocolCachePolicy` through a `default:`
    /// arm. Their behaviour is deliberately unchanged — this test is what makes
    /// "pinned, not changed" checkable.
    @Test("the formerly-defaulted endpoints still honour the server's Cache-Control")
    func formerlyDefaultedAreUnchanged() {
        let formerlyDefaulted: [Endpoint] = [
            .usersMe, .usersProfile, .usersSettings, .usersFavorites,
            .usersProgress(learning: "zh-en"), .usersTopWords(type: "weak", limit: 3),
            .studyQueue(mode: "review", limit: 10, new: 0, categories: [], lang: "zh-Hant", learning: "zh-en"),
            .studyStats(learning: "zh-en"), .smokeWhoami
        ]
        for ep in formerlyDefaulted {
            #expect(
                ep.descriptor.policy.cachePolicy == .useProtocolCachePolicy,
                "\(ep.descriptor.path) changed cache policy — this refactor must not"
            )
        }
    }

    @Test("exactly the eleven anonymous endpoints are public")
    func publicSetIsExact() {
        let publicPaths = Set(
            Self.all.filter { !$0.descriptor.policy.access.requiresToken }.map(\.descriptor.path)
        )
        #expect(publicPaths == [
            "/api/events",
            "/api/search",
            "/api/words",
            "/api/words/w1",
            "/api/categories",
            "/api/atlas/public/by-lemma",
            "/api/atlas/public",
            "/api/atlas/public/authors/TJ1",
            "/api/atlas/public/s1",
            "/api/atlas/public/collections",
            "/api/atlas/public/collections/s1"
        ])
    }

    @Test("optional auth is used by exactly one endpoint")
    func optionalAuthIsNarrow() {
        // A public read that reveals account-specific save state when a token
        // happens to be available. Widening this silently would leak
        // personalised responses into the shared CDN cache.
        let optional = Self.all.filter { $0.descriptor.policy.access == .optionalToken }
        #expect(optional.count == 1)
        #expect(optional.first?.descriptor.path == "/api/atlas/public/collections/s1")
    }

    /// The illegal state the two `Bool`s allowed: a response that can vary by
    /// caller, sitting in the shared, disk-backed `URLCache`. `EndpointAccess`
    /// makes the *pair* unrepresentable in intent; this pins that no endpoint
    /// pairs them anyway.
    @Test("nothing that can vary by caller is cached across callers")
    func callerVaryingResponsesAreNeverSharedCached() {
        for ep in Self.all {
            let d = ep.descriptor
            guard d.policy.cachePolicy == .useProtocolCachePolicy else { continue }
            #expect(
                d.policy.access.mayBeCachedAcrossCallers || d.policy.access.requiresToken,
                "\(d.path) may vary by caller yet honours the shared cache"
            )
        }
    }

    /// `isPublic` used to answer both 「attach no bearer」 and 「never retry a
    /// 401」. They part company on exactly the optional-auth endpoint: a
    /// signed-in caller *does* send a token there, so a 401 means the token was
    /// stale and is worth one retry — which the old guard refused, leaving the
    /// user on the guest view of a collection they had saved.
    @Test("a 401 is retried wherever a token may have been attached")
    func optionalAuthEndpointsRetryUnauthorized() {
        let optional = EndpointAccess.optionalToken
        #expect(optional.mayRetryUnauthorized)
        #expect(!optional.requiresToken)
        #expect(EndpointAccess.authenticated.mayRetryUnauthorized)
        // Anonymous is the only one where a 401 says nothing about a token.
        #expect(!EndpointAccess.anonymous.mayRetryUnauthorized)
    }

    @Test("only the AI endpoints get the long timeout")
    func slowEndpointsAreExactlyTheAiOnes() {
        let slow = Set(
            Self.all.filter { $0.descriptor.policy.timeout > 15 }.map(\.descriptor.path)
        )
        #expect(slow == [
            "/api/atlas/images",
            "/api/atlas/images/i1/recognize",
            "/api/atlas/items/t1/enrich",
            "/api/atlas/items/t1/detail",
            "/api/atlas/collections/c1/avatar"
        ])
        for ep in Self.all where !slow.contains(ep.descriptor.path) {
            #expect(ep.descriptor.policy.timeout == 15)
        }
    }

    @Test("no authenticated endpoint is served from the local cache except the pinned reads")
    func privateWritesNeverCache() {
        // Everything authenticated is `.reloadIgnoringLocalCacheData` apart from
        // the ten pinned reads above. Stated as a rule so a new private endpoint
        // that picks the cached profile has to be a deliberate, visible choice.
        let pinnedPaths: Set = [
            "/api/users/me", "/api/users/profile", "/api/users/settings",
            "/api/users/favorites", "/api/users/progress",
            "/api/users/top-words", "/api/study/queue", "/api/study/stats",
            "/api/test_smoke/whoami"
        ]
        for ep in Self.all {
            let d = ep.descriptor
            guard d.policy.access.requiresToken, !pinnedPaths.contains(d.path) else { continue }
            #expect(
                d.policy.cachePolicy == .reloadIgnoringLocalCacheData,
                "\(d.path) is authenticated but may be served from URLCache"
            )
        }
    }

    @Test("query items carry the values they were built from")
    func queryItemsAreCarried() {
        let queue = Endpoint.studyQueue(
            mode: "review", limit: 7, new: 2, categories: ["a", "b"], lang: "ja", learning: "zh-ja"
        )
        let items = Dictionary(
            uniqueKeysWithValues: queue.descriptor.queryItems.map { ($0.name, $0.value) }
        )
        #expect(items["mode"] == "review")
        #expect(items["limit"] == "7")
        #expect(items["new"] == "2")
        #expect(items["category"] == "a,b")
        #expect(items["lang"] == "ja")
        #expect(items["learning"] == "zh-ja")
    }

    /// The four per-user reads whose answer the server derives from a learning
    /// direction. They used to send none, so the server fell back to the stored
    /// setting — which, right after a switch, is still the old one: the client
    /// re-fetches these immediately and the settings POST is debounced 400ms
    /// behind. 圖鑑 熟練度, 完成度 and 連勝 all answered for the deck the user had
    /// just left, and stuck there for the stores' 30s freshness window.
    @Test("every direction-scoped read states its direction")
    func directionScopedReadsCarryLearning() {
        let scoped: [Endpoint] = [
            .usersProgress(learning: "zh-ja"),
            .usersMastery(learning: "zh-ja"),
            .studyStats(learning: "zh-ja"),
            .studyQueue(mode: "new", limit: 10, new: 5, categories: [], lang: "ja", learning: "zh-ja")
        ]
        for ep in scoped {
            let items = Dictionary(
                uniqueKeysWithValues: ep.descriptor.queryItems.map { ($0.name, $0.value) }
            )
            #expect(
                items["learning"] == "zh-ja",
                "\(ep.descriptor.path) must not leave its direction to the server's stored setting"
            )
        }
    }

    @Test("clearing progress names no direction, because it clears them all")
    func clearingProgressIsDirectionless() {
        #expect(Endpoint.usersProgressClear.descriptor.queryItems.isEmpty)
        #expect(Endpoint.usersProgressClear.descriptor.path == "/api/users/progress")
    }

    @Test("an absent cache-bust nonce adds no query item")
    func cacheBustIsOptional() {
        #expect(Endpoint.atlasPublicAuthor(handle: "TJ1", cacheBust: nil)
            .descriptor.queryItems.isEmpty)
        #expect(Endpoint.atlasPublicAuthor(handle: "TJ1", cacheBust: "n1")
            .descriptor.queryItems.map(\.name) == ["_cb"])
    }

    @Test("an absent sync cursor drops its query item rather than sending empty")
    func syncCursorIsOptional() {
        #expect(Endpoint.atlasSync(since: nil, limit: 50)
            .descriptor.queryItems.map(\.name) == ["limit"])
        #expect(Endpoint.atlasSync(since: "2026-01-01", limit: 50)
            .descriptor.queryItems.map(\.name) == ["since", "limit"])
    }
}
