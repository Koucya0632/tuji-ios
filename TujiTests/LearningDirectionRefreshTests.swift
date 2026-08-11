// Pins what a 學習語言 switch costs.
//
// None of this was reachable before: the fan-out was written by hand at four
// write sites, two of them inside SwiftUI `View` bodies, and the four disagreed
// about which stores a switch even touches. The first-run picker dropped only
// the catalog, so a learner who chose 日文 kept the English mastery, progress and
// streak the default direction had already fetched.

import Foundation
import Testing
@testable import Tuji

@Suite(.serialized)
@MainActor
struct LearningDirectionRefreshTests {
    // MARK: - The policy

    @Test
    func everyDirectionChangeDropsTheCatalogTheQueueAndTheLearningStores() async {
        let log = RefreshLog()
        let refresher = log.refresher()

        await refresher.refresh(after: .userPicked)

        // Order is the point: nothing may be re-read before everything holding
        // the old direction's answers has been dropped.
        #expect(log.events.prefix(3) == ["invalidate:catalog", "invalidate:queue", "invalidate:stores"])
        #expect(log.events.contains("reload:stores"))
    }

    @Test
    func aServerDisagreementDropsTheCatalogWithoutRefetchingIt() async {
        let log = RefreshLog()
        let refresher = log.refresher()

        await refresher.refresh(after: .serverDisagreed)

        // LaunchCoordinator owns the context-aware catalog load on this path;
        // reloading here would race it and extend the splash gate. Dropping it
        // is not optional either way — a stale catalog must never be served.
        #expect(log.events.contains("invalidate:catalog"))
        #expect(!log.events.contains("reload:catalog"))
        #expect(log.events.contains("reload:stores"))
    }

    @Test
    func aUserPickedSwitchRefetchesTheCatalogToo() async {
        let log = RefreshLog()
        let refresher = log.refresher()

        await refresher.refresh(after: .userPicked)

        #expect(log.events.contains("reload:catalog"))
    }

    /// The prefetched queue survived all four of the old fan-outs. It only ever
    /// escaped serving the previous direction's words because its own cache
    /// signature carries the direction — a second guard for the same fact.
    @Test
    func theStudyQueueIsDroppedInBothDirections() async {
        for origin in [LearningDirectionChangeOrigin.userPicked, .serverDisagreed] {
            let log = RefreshLog()
            await log.refresher().refresh(after: origin)
            #expect(log.events.contains("invalidate:queue"))
        }
    }

    // MARK: - The store is the only place that notices

    @Test
    func pickingADirectionFiresThePolicyOnce() async throws {
        let spy = SpyLearningDirectionRefresher()
        let store = try self.store(refresh: spy)

        store.setLearningDirection(.zhJa, persist: false)
        await spy.settle()

        #expect(spy.origins == [.userPicked])
        #expect(store.current.learningDirection == .zhJa)
    }

    @Test
    func pickingTheDirectionAlreadyInUseCostsNothing() async throws {
        let spy = SpyLearningDirectionRefresher()
        let store = try self.store(refresh: spy)

        store.setLearningDirection(.zhEn, persist: false) // already the default
        await spy.settle()

        #expect(spy.origins.isEmpty)
    }

    @Test
    func aServerLoadThatDisagreesFiresThePolicy() async throws {
        let repository = DirectionUserRepositoryFake()
        var served = UserSettings.default
        served.learningDirection = .zhJa
        repository.settings = served
        let spy = SpyLearningDirectionRefresher()
        let store = try self.store(refresh: spy, repository: repository)

        await store.load()
        await spy.settle()

        #expect(spy.origins == [.serverDisagreed])
    }

    @Test
    func aServerLoadThatAgreesFiresNothing() async throws {
        let repository = DirectionUserRepositoryFake()
        repository.settings = .default // .zhEn, same as the store
        let spy = SpyLearningDirectionRefresher()
        let store = try self.store(refresh: spy, repository: repository)

        await store.load()
        await spy.settle()

        #expect(spy.origins.isEmpty)
    }

    /// Setup posts the direction the onboarding picker already applied, so this
    /// is normally a no-op. It is wired anyway because `adoptPersisted` is the
    /// third way `current` can change, and a fourth caller must not have to
    /// remember what a switch costs.
    @Test
    func adoptingPersistedSettingsNoticesADirectionItDidNotExpect() async throws {
        let spy = SpyLearningDirectionRefresher()
        let store = try self.store(refresh: spy)

        var adopted = UserSettings.default
        adopted.learningDirection = .zhJa
        store.adoptPersisted(adopted)
        await spy.settle()

        #expect(spy.origins == [.serverDisagreed])
    }

    @Test
    func adoptingTheSameDirectionFiresNothing() async throws {
        let spy = SpyLearningDirectionRefresher()
        let store = try self.store(refresh: spy)

        store.adoptPersisted(.default)
        await spy.settle()

        #expect(spy.origins.isEmpty)
    }

    // MARK: - Harness

    private func store(
        refresh: LearningDirectionRefreshing,
        repository: UserRepository = DirectionUserRepositoryFake()
    ) throws
        -> SettingsStore
    {
        let suiteName = "LearningDirectionRefreshTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return SettingsStore(
            repository: repository,
            defaults: defaults,
            signedInUserProvider: { nil },
            directionRefresh: refresh
        )
    }
}

/// Records what the live policy does to each store without standing any of them
/// up — the closures are the seam the adapter was built around.
@MainActor
private final class RefreshLog {
    private(set) var events: [String] = []

    func refresher() -> LiveLearningDirectionRefresher {
        LiveLearningDirectionRefresher(
            invalidateCatalog: { self.events.append("invalidate:catalog") },
            reloadCatalog: { self.events.append("reload:catalog") },
            invalidateQueue: { self.events.append("invalidate:queue") },
            learningStores: {
                self.events.append("invalidate:stores")
                return [SpyRefreshableStore { self.events.append("reload:stores") }]
            }
        )
    }
}

@MainActor
private final class SpyRefreshableStore: RefreshableStore {
    private let onReload: @MainActor () -> Void

    init(onReload: @escaping @MainActor () -> Void) {
        self.onReload = onReload
    }

    func invalidate() {}

    func reload() async {
        self.onReload()
    }
}

@MainActor
private final class SpyLearningDirectionRefresher: LearningDirectionRefreshing {
    private(set) var origins: [LearningDirectionChangeOrigin] = []

    func refresh(after origin: LearningDirectionChangeOrigin) async {
        self.origins.append(origin)
    }

    /// The store fires the policy from a detached `Task` so the picker can
    /// dismiss without waiting. Yield until it has run.
    func settle() async {
        for _ in 0..<100 {
            if !self.origins.isEmpty { return }
            await Task.yield()
        }
    }
}

@MainActor
private final class DirectionUserRepositoryFake: UserRepository {
    var settings: UserSettings = .default

    func loadSettings() async throws -> UserSettings {
        self.settings
    }

    func saveSettings(_: UserSettings) async throws {}
    func deleteAccount() async throws {}
    func syncLocalCache(_: SyncPayload) async throws {}

    func loadMe() async throws -> UserMeResponse {
        throw DirectionRefreshTestFailure.unimplemented
    }

    func registerPushToken(_: PushTokenPayload) async throws {}
    func unregisterPushToken(deviceId _: String) async throws {}
    func submitFeedback(_: FeedbackPayload) async throws {}
}

private enum DirectionRefreshTestFailure: Error {
    case unimplemented
}
