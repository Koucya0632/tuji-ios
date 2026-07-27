// Pins PublicFeedVM's language-scoped load state machine — the "don't clobber a
// good list on back" guard (the disappears-on-back bug), language-switch refetch,
// forced/pending-publish reloads that bypass the cache, and the rule that a failed
// forced reload keeps the list already on screen. Driven through a synchronous
// FakeCollectionsBrowsing (no timers — CI @MainActor suites starve on real waits).

import Foundation
import Testing
@testable import Tuji

@MainActor
struct PublicFeedVMTests {
    // MARK: - Fixtures

    private func collection(id: String, lang: TargetLanguage = .ja) -> AtlasCollection {
        AtlasCollection(
            id: id,
            slug: "slug-\(id)",
            title: "C\(id)",
            description: nil,
            targetLanguage: lang,
            author: AtlasAuthorRef(username: "u", displayName: "U", avatar: "face"),
            itemCount: 3,
            saveCount: 0,
            coverImageUrl: nil,
            publishedAt: nil
        )
    }

    // MARK: - Tests

    @Test
    func loadPopulatesAndMarksReady() async {
        let fake = FakeCollectionsBrowsing()
        fake.result = .success([self.collection(id: "a")])
        let vm = PublicFeedVM(repo: fake)

        await vm.load(lang: .ja)

        #expect(vm.collections.count == 1)
        #expect(vm.phase == .ready)
        #expect(vm.loadedLang == .ja)
    }

    @Test
    func skipsReloadReturningToSameLanguageList() async {
        let fake = FakeCollectionsBrowsing()
        fake.result = .success([self.collection(id: "a")])
        let vm = PublicFeedVM(repo: fake)

        await vm.load(lang: .ja) // fetch #1
        await vm.load(lang: .ja) // appearance load on back — must skip

        #expect(fake.calls.count == 1)
    }

    @Test
    func languageSwitchRefetches() async {
        let fake = FakeCollectionsBrowsing()
        fake.result = .success([self.collection(id: "a")])
        let vm = PublicFeedVM(repo: fake)

        await vm.load(lang: .ja)
        await vm.load(lang: .en)

        #expect(fake.calls.count == 2)
        #expect(fake.calls.last?.lang == .en)
    }

    @Test
    func forceReloadRefetchesEvenWithAList() async {
        let fake = FakeCollectionsBrowsing()
        fake.result = .success([self.collection(id: "a")])
        let vm = PublicFeedVM(repo: fake)

        await vm.load(lang: .ja)
        await vm.load(lang: .ja, forceReload: true)

        #expect(fake.calls.count == 2)
        #expect(fake.calls.last?.force == true)
    }

    @Test
    func pendingPublishSignalRefetchesAndBypassesCache() async {
        let fake = FakeCollectionsBrowsing()
        fake.result = .success([self.collection(id: "a")])
        let vm = PublicFeedVM(repo: fake)

        await vm.load(lang: .ja)
        await vm.load(lang: .ja, pendingForce: true) // a publish went live

        #expect(fake.calls.count == 2)
        // pendingForce reaches the repo as a cache-bypassing force.
        #expect(fake.calls.last?.force == true)
    }

    @Test
    func failedInitialLoadClearsListAndSurfacesError() async {
        let fake = FakeCollectionsBrowsing()
        fake.result = .failure(FakeError.boom)
        let vm = PublicFeedVM(repo: fake)

        await vm.load(lang: .ja)

        #expect(vm.collections.isEmpty)
        #expect(vm.errorMessage != nil)
        if case .failed = vm.phase {} else {
            Issue.record("expected phase == .failed, got \(vm.phase)")
        }
    }

    @Test
    func failedForceReloadKeepsExistingList() async {
        let fake = FakeCollectionsBrowsing()
        fake.result = .success([self.collection(id: "a"), self.collection(id: "b")])
        let vm = PublicFeedVM(repo: fake)

        await vm.load(lang: .ja) // good list of 2
        fake.result = .failure(FakeError.boom)
        await vm.load(lang: .ja, forceReload: true) // refresh fails

        // The list already on screen is preserved — no clobber.
        #expect(vm.collections.count == 2)
        #expect(vm.errorMessage != nil)
    }
}

// MARK: - Fake

private enum FakeError: Error {
    case boom
}

@MainActor
private final class FakeCollectionsBrowsing: CollectionsBrowsing {
    private(set) var calls: [(lang: TargetLanguage, force: Bool)] = []
    var result: Result<[AtlasCollection], Error> = .success([])

    func publicCollections(lang: TargetLanguage, forceReload: Bool) async throws -> [AtlasCollection] {
        self.calls.append((lang, forceReload))
        return try self.result.get()
    }
}
