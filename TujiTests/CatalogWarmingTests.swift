// Pins what a launch actually loads.
//
// This was two closures in `TujiApp.init` carrying the same eight lines, so the
// difference between "preload for a guest" and "finalize for a signed-in user"
// — the two fields `CatalogContext`'s precondition exists to relate — was
// asserted by nothing. `LaunchCoordinator`'s own tests pass fakes for the whole
// thing and only ever check the *sequencing*.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct CatalogAudienceTests {
    /// The two fields that used to be spelled out once per closure.
    @Test
    func onlyASignedInAudienceIsPersonalized() {
        let userID = UUID()

        #expect(CatalogAudience.guest.userID == nil)
        #expect(!CatalogAudience.guest.includesPersonalization)

        #expect(CatalogAudience.signedIn(userID: userID).userID == userID)
        #expect(CatalogAudience.signedIn(userID: userID).includesPersonalization)
    }

    /// Two accounts are two audiences. The catalog generation handover keys on
    /// this, so a stale request for the previous account cannot publish.
    @Test
    func audiencesAreDistinctPerAccount() {
        let a = UUID()
        let b = UUID()
        #expect(CatalogAudience.signedIn(userID: a) != CatalogAudience.signedIn(userID: b))
        #expect(CatalogAudience.signedIn(userID: a) != .guest)
    }

    /// A guest's catalog carries no identity and no personalization. Asking for
    /// custom/saved words without an account is the combination
    /// `CatalogContext` traps on, which is why these two travel together.
    @Test
    func aGuestContextIsAnonymousAndUnpersonalized() {
        let context = CatalogAudience.guest.context(settings: .default)

        #expect(context.userID == nil)
        #expect(context.includePersonalization == false)
    }

    @Test
    func aSignedInContextCarriesTheAccountAndItsPersonalization() {
        let userID = UUID()
        let context = CatalogAudience.signedIn(userID: userID).context(settings: .default)

        #expect(context.userID == userID)
        #expect(context.includePersonalization == true)
    }

    /// Same language settings, different identity — and the two must never
    /// share an in-flight result. Launch begins the anonymous preload before
    /// authentication resolves and then asks again for the account.
    @Test
    func theTwoAudiencesAreTwoRequestsUnderIdenticalSettings() {
        let guest = CatalogAudience.guest.context(settings: .default)
        let signedIn = CatalogAudience.signedIn(userID: UUID()).context(settings: .default)

        #expect(guest != signedIn)
        #expect(guest.contentLanguageCode == signedIn.contentLanguageCode)
        #expect(guest.learningDirectionCode == signedIn.learningDirectionCode)
    }

    /// The language half comes from settings, so a warm after a 學習語言 switch
    /// is a different request even for the same audience.
    @Test
    func theContextFollowsTheLearningDirection() {
        var ja = UserSettings.default
        ja.learningDirection = .zhJa
        var en = UserSettings.default
        en.learningDirection = .zhEn

        #expect(
            CatalogAudience.guest.context(settings: ja)
                != CatalogAudience.guest.context(settings: en)
        )
    }
}

@MainActor
struct LiveCatalogWarmerTests {
    /// The three stores a warm reaches, plus the repository behind two of them.
    private struct Fixture {
        let settings: SettingsStore
        let words: WordsStore
        let categories: CategoriesStore
        let repo: WarmerCatalogRepository

        var warmer: LiveCatalogWarmer {
            LiveCatalogWarmer(
                settings: self.settings,
                words: self.words,
                categories: self.categories
            )
        }
    }

    private func fixture() throws -> Fixture {
        let repo = WarmerCatalogRepository()
        // A fresh suite per test: `SettingsStore` mirrors the learning direction
        // into defaults, and a shared suite would leak it into the next one.
        let suite = "CatalogWarmingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return Fixture(
            settings: SettingsStore(
                repository: WarmerUserRepository(),
                defaults: defaults,
                signedInUserProvider: { nil },
                directionRefresh: InertDirectionRefresher()
            ),
            words: WordsStore(repository: repo),
            categories: CategoriesStore(repository: repo),
            repo: repo
        )
    }

    /// Words *and* categories, together. They were loaded as a pair in both
    /// closures, and a pair is what the screens read.
    @Test
    func warmingLoadsWordsAndCategories() async throws {
        let f = try self.fixture()
        let warmer = f.warmer

        await warmer.warm(for: .guest)

        #expect(f.repo.wordsLoads == 1)
        #expect(f.repo.categoryLoads == 1)
    }

    /// A guest asks for the public list only. `loadCustomWords` on an account
    /// that does not exist is the request the anonymous preload must not make.
    @Test
    func aGuestWarmDoesNotAskForPersonalizedWords() async throws {
        let f = try self.fixture()
        let warmer = f.warmer

        await warmer.warm(for: .guest)

        #expect(f.repo.customLoads == 0)
    }

    @Test
    func aSignedInWarmAsksForPersonalizedWords() async throws {
        let f = try self.fixture()
        let warmer = f.warmer

        await warmer.warm(for: .signedIn(userID: UUID()))

        #expect(f.repo.customLoads == 1)
    }

    /// Repeating an audience is a no-op — the stores are context-keyed, so the
    /// coordinator can ask again without paying for it.
    @Test
    func repeatingTheSameAudienceCostsNothing() async throws {
        let f = try self.fixture()
        let warmer = f.warmer

        await warmer.warm(for: .guest)
        await warmer.warm(for: .guest)

        #expect(f.repo.wordsLoads == 1)
    }

    /// Signing in after the anonymous preload fetches the *overlay*, not the
    /// catalog again.
    ///
    /// The two audiences are two generations — `loadIfNeeded` runs for the
    /// second one rather than short-circuiting — but the public list is the
    /// same 480 words either way, so only the personalized half goes over the
    /// wire (`reusePublic`). This is the shape the two closures had between
    /// them and neither one stated.
    @Test
    func signingInFetchesTheOverlayNotThePublicListAgain() async throws {
        let f = try self.fixture()
        let warmer = f.warmer

        await warmer.warm(for: .guest)
        await warmer.warm(for: .signedIn(userID: UUID()))

        #expect(f.repo.wordsLoads == 1)
        #expect(f.repo.customLoads == 1)
    }
}

// MARK: - Fakes

@MainActor
final class WarmerCatalogRepository: CatalogRepository {
    private(set) var wordsLoads = 0
    private(set) var customLoads = 0
    private(set) var categoryLoads = 0

    struct NotImplemented: Error {}

    func loadWords(lang _: String, learning _: String) async throws -> WordsListResponse {
        self.wordsLoads += 1
        return WordsListResponse(words: [], total: 0)
    }

    func loadCustomWords(lang _: String, learning _: String) async throws -> WordsListResponse {
        self.customLoads += 1
        return WordsListResponse(words: [], total: 0)
    }

    func loadSavedWords(lang _: String, learning _: String) async throws -> WordsListResponse {
        WordsListResponse(words: [], total: 0)
    }

    func loadCategories(lang _: String) async throws -> CategoriesResponse {
        self.categoryLoads += 1
        return CategoriesResponse(categories: [])
    }

    func search(_: String) async throws -> SearchResponse {
        throw NotImplemented()
    }

    func word(id _: String, lang _: String, learning _: String) async throws -> Word {
        throw NotImplemented()
    }
}

private struct InertDirectionRefresher: LearningDirectionRefreshing {
    func refresh(after _: LearningDirectionChangeOrigin) async {}
}

/// Settings are loaded before the context is derived for a signed-in audience,
/// so this fake exists only to let a real `SettingsStore` stand up.
@MainActor
private final class WarmerUserRepository: UserRepository {
    func loadSettings() async throws -> UserSettings {
        .default
    }

    func saveSettings(_: UserSettings) async throws {}
    func deleteAccount() async throws {}
    func syncLocalCache(_: SyncPayload) async throws {}
    func loadMe() async throws -> UserMeResponse {
        throw WarmerCatalogRepository.NotImplemented()
    }

    func registerPushToken(_: PushTokenPayload) async throws {}
    func unregisterPushToken(deviceId _: String) async throws {}
    func submitFeedback(_: FeedbackPayload) async throws {}
}
