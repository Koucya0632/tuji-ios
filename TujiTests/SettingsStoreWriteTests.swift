import Foundation
import Testing
@testable import Tuji

/// A change made before the account's settings arrive — see `SettingsWrite`.
///
/// The save sends the whole object. Before the read lands, the whole object is
/// this device's defaults, so one tap in 設定 after a failed launch read wrote
/// an empty 學習主題 over the account on every device.
@Suite(.serialized)
@MainActor
struct SettingsStoreWriteTests {
    private let alice = SessionUser(id: UUID(), email: nil, username: "TJ00000001", nickname: nil, avatar: nil)
    private let bob = SessionUser(id: UUID(), email: nil, username: "TJ00000002", nickname: nil, avatar: nil)

    /// What the server holds for the account: themes someone chose.
    private var accountSettings: UserSettings {
        var settings = UserSettings.default
        settings.studyCategories = ["bathroom", "kitchen", "office"]
        settings.dailyGoal = 20
        return settings
    }

    private func harness(
        _ repository: SettingsWriteRepositoryFake,
        signedIn: @escaping @MainActor () -> SessionUser?
    ) throws
        -> SettingsWriteHarness
    {
        let suiteName = "SettingsStoreWriteTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = SettingsStore(
            repository: repository,
            defaults: defaults,
            signedInUserProvider: signedIn,
            directionRefresh: SettingsWriteInertRefresher(),
            saveDebounce: .zero
        )
        return SettingsWriteHarness(store: store, defaults: defaults, suiteName: suiteName)
    }

    @Test
    func aSignedInChangeBeforeTheSettingsArriveIsRefusedAndNeverSent() async throws {
        let repository = SettingsWriteRepositoryFake()
        let alice = self.alice
        let harness = try self.harness(repository) { alice }
        defer { harness.tearDown() }
        let store = harness.store
        let before = store.current

        store.update { $0.studyCategories = ["kitchen"] }
        await store.awaitPendingSave()

        #expect(!store.isEditable)
        #expect(store.current == before)
        #expect(repository.saved.isEmpty)
    }

    @Test
    func aFailedReadKeepsRefusingUntilARetrySucceeds() async throws {
        let repository = SettingsWriteRepositoryFake()
        let account = self.accountSettings
        repository.loadHandler = {
            if repository.loadCalls == 1 { throw SettingsWriteTestFailure.offline }
            return account
        }
        let alice = self.alice
        let harness = try self.harness(repository) { alice }
        defer { harness.tearDown() }
        let store = harness.store

        await store.loadIfNeeded(for: alice.id)
        store.update { $0.dailyGoal = 5 }
        await store.awaitPendingSave()
        #expect(!store.isEditable)
        #expect(repository.saved.isEmpty)

        await store.loadIfNeeded(for: alice.id)
        #expect(store.isEditable)
        store.update { $0.dailyGoal = 5 }
        await store.awaitPendingSave()

        // The account's themes ride along untouched: the object sent is the
        // account's, with only the one field changed.
        #expect(repository.saved.count == 1)
        #expect(repository.saved.last?.studyCategories == account.studyCategories)
        #expect(repository.saved.last?.dailyGoal == 5)
    }

    @Test
    func settingsLoadedForOneAccountDoNotLetAnotherAccountWrite() async throws {
        let repository = SettingsWriteRepositoryFake()
        let account = self.accountSettings
        repository.loadHandler = { account }
        let alice = self.alice
        var who: SessionUser? = alice
        let harness = try self.harness(repository) { who }
        defer { harness.tearDown() }
        let store = harness.store

        await store.loadIfNeeded(for: alice.id)
        #expect(store.isEditable)

        who = self.bob
        store.update { $0.dailyGoal = 5 }
        await store.awaitPendingSave()

        #expect(!store.isEditable)
        #expect(repository.saved.isEmpty)
    }

    @Test
    func aGuestChangesThisDeviceAndSendsNothing() async throws {
        // A guest's read never succeeds — there is no account to read — so
        // gating on it would lock a guest out of 設定 for good.
        let repository = SettingsWriteRepositoryFake()
        let harness = try self.harness(repository) { nil }
        defer { harness.tearDown() }
        let store = harness.store

        store.update { $0.dailyGoal = 5 }
        await store.awaitPendingSave()

        #expect(store.isEditable)
        #expect(store.current.dailyGoal == 5)
        #expect(repository.saved.isEmpty)
    }

    @Test
    func aLearningDirectionPickedBeforeTheSettingsArriveIsAppliedButNotSent() async throws {
        // The first-run picker must be able to move on, so this one is not
        // refused — but sending it would send the defaults with it.
        let repository = SettingsWriteRepositoryFake()
        let alice = self.alice
        let harness = try self.harness(repository) { alice }
        defer { harness.tearDown() }
        let store = harness.store
        let other: LearningDirection = store.current.learningDirection == .zhEn ? .zhJa : .zhEn

        store.setLearningDirection(other, persist: true)
        await store.awaitPendingSave()

        #expect(store.current.learningDirection == other)
        #expect(repository.saved.isEmpty)
    }

    /// Sign-out. The themes, goal and accent were the previous account's; the
    /// interface language and direction are the device's and stay.
    @Test
    func resetKeepsWhatBelongsToTheDeviceAndForgetsTheAccount() async throws {
        let repository = SettingsWriteRepositoryFake()
        let account = self.accountSettings
        repository.loadHandler = { account }
        let alice = self.alice
        var who: SessionUser? = alice
        let harness = try self.harness(repository) { who }
        defer { harness.tearDown() }
        let store = harness.store
        await store.loadIfNeeded(for: alice.id)
        #expect(store.loadedForCurrentAccount)
        let direction = store.current.learningDirection
        let uiLang = store.current.uiLang

        store.reset()
        who = nil

        #expect(!store.hasLoaded)
        #expect(!store.loadedForCurrentAccount)
        #expect(store.current.studyCategories == UserSettings.default.studyCategories)
        #expect(store.current.dailyGoal == UserSettings.default.dailyGoal)
        #expect(store.current.learningDirection == direction)
        #expect(store.current.uiLang == uiLang)

        // Bob signs in: nothing Alice loaded counts as his.
        who = self.bob
        #expect(!store.loadedForCurrentAccount)
        #expect(!store.isEditable)
    }

    @Test
    func theRuleItself() {
        #expect(SettingsWrite.decide(signedIn: true, loaded: false) == .refuse)
        #expect(SettingsWrite.decide(signedIn: true, loaded: true) == .applyAndSave)
        #expect(SettingsWrite.decide(signedIn: false, loaded: false) == .applyLocally)
        #expect(SettingsWrite.decide(signedIn: false, loaded: true) == .applyLocally)
    }
}

@MainActor
private struct SettingsWriteHarness {
    let store: SettingsStore
    let defaults: UserDefaults
    let suiteName: String

    func tearDown() {
        self.defaults.removePersistentDomain(forName: self.suiteName)
    }
}

@MainActor
private final class SettingsWriteRepositoryFake: UserRepository {
    var loadCalls = 0
    var loadHandler: @MainActor () async throws -> UserSettings = { throw SettingsWriteTestFailure.offline }
    private(set) var saved: [UserSettings] = []

    func loadSettings() async throws -> UserSettings {
        self.loadCalls += 1
        return try await self.loadHandler()
    }

    func saveSettings(_ settings: UserSettings) async throws {
        self.saved.append(settings)
    }

    func deleteAccount() async throws {}
    func syncLocalCache(_: SyncPayload) async throws {}

    func loadMe() async throws -> UserMeResponse {
        throw SettingsWriteTestFailure.unimplemented
    }

    func registerPushToken(_: PushTokenPayload) async throws {}
    func unregisterPushToken(deviceId _: String) async throws {}
    func submitFeedback(_: FeedbackPayload) async throws {}
}

@MainActor
private struct SettingsWriteInertRefresher: LearningDirectionRefreshing {
    func refresh(after _: LearningDirectionChangeOrigin) async {}
}

private enum SettingsWriteTestFailure: Error {
    case offline
    case unimplemented
}
