import Foundation
import Testing
@testable import Tuji

@Suite(.serialized)
@MainActor
struct SettingsStoreLoadingTests {
    @Test
    func firstSetupKeepsTheLocallySelectedDirectionAndLanguage() {
        var server = UserSettings.default
        server.uiLang = "zh-Hant"
        server.learningDirection = .zhEn
        var current = UserSettings.default
        current.uiLang = "ja"

        let reconciled = SettingsStore.reconcileServerSettings(
            server,
            current: current,
            selectedDirection: .zhJa,
            setupDone: false
        )

        #expect(reconciled.uiLang == "ja")
        #expect(reconciled.learningDirection == .zhJa)
    }

    @Test
    func completedSetupUsesTheServerSettings() {
        var server = UserSettings.default
        server.dailyGoal = 30
        var current = UserSettings.default
        current.dailyGoal = 5

        #expect(SettingsStore.reconcileServerSettings(
            server,
            current: current,
            selectedDirection: .zhJa,
            setupDone: true
        ) == server)
    }

    @Test
    func concurrentLoadIfNeededCallsShareOneRequest() async throws {
        let repository = SettingsUserRepositoryFake()
        let gate = SettingsResultGate<UserSettings>()
        repository.loadHandler = { try await gate.wait() }
        let suiteName = "SettingsStoreLoadingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = SettingsStore(
            repository: repository,
            defaults: defaults,
            signedInUserProvider: { nil },
            // These tests are about load coalescing, not the direction fan-out;
            // without this they would reach the real singletons.
            directionRefresh: InertLearningDirectionRefresher()
        )
        let userID = UUID()

        let first = Task { await store.loadIfNeeded(for: userID) }
        await settingsWaitUntil { repository.loadCalls == 1 }
        let second = Task { await store.loadIfNeeded(for: userID) }
        await Task.yield()

        #expect(repository.loadCalls == 1)
        var settings = UserSettings.default
        settings.dailyGoal = 25
        gate.succeed(settings)
        await first.value
        await second.value
        await store.loadIfNeeded(for: userID)

        #expect(repository.loadCalls == 1)
        #expect(store.current.dailyGoal == settings.dailyGoal)
        #expect(store.hasLoaded)
        #expect(!store.loading)
        #expect(store.lastError == nil)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func lateAccountAResponseCannotReplaceAccountBSettings() async throws {
        let repository = SettingsUserRepositoryFake()
        let accountAGate = SettingsResultGate<UserSettings>()
        let accountBGate = SettingsResultGate<UserSettings>()
        repository.loadHandler = {
            if repository.loadCalls == 1 {
                return try await accountAGate.wait()
            }
            return try await accountBGate.wait()
        }
        let suiteName = "SettingsStoreLoadingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = SettingsStore(
            repository: repository,
            defaults: defaults,
            signedInUserProvider: { nil },
            // These tests are about load coalescing, not the direction fan-out;
            // without this they would reach the real singletons.
            directionRefresh: InertLearningDirectionRefresher()
        )
        let accountA = UUID()
        let accountB = UUID()

        let accountALoad = Task { await store.loadIfNeeded(for: accountA) }
        await settingsWaitUntil { repository.loadCalls == 1 }
        let accountBLoad = Task { await store.loadIfNeeded(for: accountB) }
        await settingsWaitUntil { repository.loadCalls == 2 }

        var accountBSettings = UserSettings.default
        accountBSettings.dailyGoal = 30
        accountBGate.succeed(accountBSettings)
        await accountBLoad.value

        var accountASettings = UserSettings.default
        accountASettings.dailyGoal = 5
        accountAGate.succeed(accountASettings)
        await accountALoad.value

        #expect(repository.loadCalls == 2)
        #expect(store.current.dailyGoal == 30)
        #expect(store.hasLoaded)
        #expect(!store.loading)
        #expect(store.lastError == nil)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func failedSettingsAttemptCanRetry() async throws {
        let repository = SettingsUserRepositoryFake()
        repository.loadHandler = {
            if repository.loadCalls == 1 {
                throw SettingsLoadingTestFailure.requestFailed
            }
            var settings = UserSettings.default
            settings.dailyGoal = 25
            return settings
        }
        let suiteName = "SettingsStoreLoadingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = SettingsStore(
            repository: repository,
            defaults: defaults,
            signedInUserProvider: { nil },
            // These tests are about load coalescing, not the direction fan-out;
            // without this they would reach the real singletons.
            directionRefresh: InertLearningDirectionRefresher()
        )
        let userID = UUID()

        await store.loadIfNeeded(for: userID)
        #expect(!store.hasLoaded)
        #expect(store.lastError != nil)

        await store.loadIfNeeded(for: userID)
        #expect(repository.loadCalls == 2)
        #expect(store.hasLoaded)
        #expect(store.lastError == nil)
        #expect(store.current.dailyGoal == 25)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class SettingsResultGate<Value> {
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async throws -> Value {
        if let result = self.result {
            self.result = nil
            return try result.get()
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        guard let result = self.result else {
            throw SettingsLoadingTestFailure.gateMissingResult
        }
        self.result = nil
        return try result.get()
    }

    func succeed(_ value: Value) {
        self.result = .success(value)
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume()
    }
}

@MainActor
private final class SettingsUserRepositoryFake: UserRepository {
    var loadCalls = 0
    var loadHandler: @MainActor () async throws -> UserSettings = { .default }

    func loadSettings() async throws -> UserSettings {
        self.loadCalls += 1
        return try await self.loadHandler()
    }

    func saveSettings(_: UserSettings) async throws {}
    func deleteAccount() async throws {}
    func syncLocalCache(_: SyncPayload) async throws {}

    func loadMe() async throws -> UserMeResponse {
        throw SettingsLoadingTestFailure.unimplemented
    }

    func registerPushToken(_: PushTokenPayload) async throws {}
    func unregisterPushToken(deviceId _: String) async throws {}
    func submitFeedback(_: FeedbackPayload) async throws {}
}

@MainActor
private func settingsWaitUntil(
    _ predicate: @MainActor () -> Bool
) async {
    for _ in 0..<1000 {
        if predicate() { return }
        await Task.yield()
    }
    Issue.record("Timed out waiting for asynchronous test state")
}

private enum SettingsLoadingTestFailure: Error {
    case gateMissingResult
    case requestFailed
    case unimplemented
}

@MainActor
private struct InertLearningDirectionRefresher: LearningDirectionRefreshing {
    func refresh(after _: LearningDirectionChangeOrigin) async {}
}
