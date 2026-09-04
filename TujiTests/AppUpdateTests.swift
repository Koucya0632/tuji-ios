import Foundation
import Testing
@testable import Tuji

struct AppVersionTests {
    @Test
    func comparesSegmentsNumericallyNotAsText() throws {
        // 字串比較會說 1.1.10 < 1.1.9，而那個錯誤的方向是「不提示」。
        #expect(try self.version("1.1.10") > self.version("1.1.9"))
        #expect(try self.version("1.2.0") > self.version("1.1.99"))
        #expect(try self.version("2.0") > self.version("1.9.9"))
    }

    @Test
    func treatsMissingTrailingSegmentsAsZero() throws {
        #expect(AppVersion("1.2") == AppVersion("1.2.0"))
        #expect(AppVersion("1.2.0.0") == AppVersion("1.2"))
        #expect(try self.version("1.2.1") > self.version("1.2"))
    }

    @Test
    func rejectsAnythingItCannotCompare() {
        #expect(AppVersion("1.2-beta") == nil)
        #expect(AppVersion("") == nil)
        #expect(AppVersion("1..2") == nil)
        #expect(AppVersion("v1.2") == nil)
        #expect(AppVersion("+1.2") == nil)
        #expect(AppVersion("１.２") == nil)
    }

    /// 解不開就當場失敗：這些字串都是這個測試自己寫死的，解不開表示規則變了。
    private func version(_ string: String) throws -> AppVersion {
        try #require(AppVersion(string))
    }
}

struct AppUpdatePolicyTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    // MARK: - 該不該去問 App Store

    @Test
    func checksOnceADayAndAlwaysOnAFirstLaunch() {
        #expect(AppUpdatePolicy.shouldCheck(lastCheckedAt: nil, now: self.now))
        #expect(!AppUpdatePolicy.shouldCheck(
            lastCheckedAt: self.now.addingTimeInterval(-3600),
            now: self.now
        ))
        #expect(AppUpdatePolicy.shouldCheck(
            lastCheckedAt: self.now.addingTimeInterval(-AppUpdatePolicy.checkInterval),
            now: self.now
        ))
    }

    @Test
    func aClockMovedBackwardsDoesNotDisableCheckingForever() {
        #expect(AppUpdatePolicy.shouldCheck(
            lastCheckedAt: self.now.addingTimeInterval(60 * 60 * 24 * 365),
            now: self.now
        ))
    }

    // MARK: - 該不該跳提示

    @Test
    func promptsOnlyWhenTheStoreIsActuallyAhead() {
        #expect(self.shouldPrompt(installed: "1.1.1", latest: "1.1.2"))
        #expect(!self.shouldPrompt(installed: "1.1.1", latest: "1.1.1"))
        // TestFlight 的包會比上架版新。不能叫他「更新」到比手上還舊的版本。
        #expect(!self.shouldPrompt(installed: "1.2.0", latest: "1.1.9"))
    }

    @Test
    func staysQuietWhenEitherVersionCannotBeParsed() {
        #expect(!self.shouldPrompt(installed: "?", latest: "1.1.2"))
        #expect(!self.shouldPrompt(installed: "1.1.1", latest: "next"))
    }

    @Test
    func snoozeSilencesOnlyThatVersionAndOnlyForAWhile() {
        let snoozed = SnoozedAppUpdate(version: "1.1.2", at: self.now)

        #expect(!self.shouldPrompt(
            installed: "1.1.1",
            latest: "1.1.2",
            snoozed: snoozed
        ))
        // 更新的版本出來了 —— 靜音只針對被按掉的那一版。
        #expect(self.shouldPrompt(
            installed: "1.1.1",
            latest: "1.1.3",
            snoozed: snoozed
        ))
        // 靜音會過期，而不是永久關掉。
        #expect(self.shouldPrompt(
            installed: "1.1.1",
            latest: "1.1.2",
            snoozed: snoozed,
            now: self.now.addingTimeInterval(AppUpdatePolicy.snoozeInterval)
        ))
    }

    @Test
    func snoozeMatchesOnTheVersionNotOnHowItIsWritten() {
        #expect(!self.shouldPrompt(
            installed: "1.1",
            latest: "1.2.0",
            snoozed: SnoozedAppUpdate(version: "1.2", at: self.now)
        ))
    }

    // MARK: - 該不該現在說

    @Test
    func holdsThePromptWhileTheUserIsInTheMiddleOfSomething() {
        #expect(AppUpdatePolicy.mayPresent(
            pendingVersion: "1.1.2",
            studyFocusActive: false,
            tourRunning: false
        ))
        #expect(!AppUpdatePolicy.mayPresent(
            pendingVersion: "1.1.2",
            studyFocusActive: true,
            tourRunning: false
        ))
        #expect(!AppUpdatePolicy.mayPresent(
            pendingVersion: "1.1.2",
            studyFocusActive: false,
            tourRunning: true
        ))
        #expect(!AppUpdatePolicy.mayPresent(
            pendingVersion: nil,
            studyFocusActive: false,
            tourRunning: false
        ))
    }

    private func shouldPrompt(
        installed: String,
        latest: String,
        snoozed: SnoozedAppUpdate? = nil,
        now: Date? = nil
    )
        -> Bool
    {
        AppUpdatePolicy.shouldPrompt(
            installed: installed,
            latest: latest,
            snoozed: snoozed,
            now: now ?? self.now
        )
    }
}

@MainActor
struct AppUpdateStoreTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    @Test
    func surfacesANewerStoreVersionAndKeepsItsLink() async throws {
        let suiteName = "AppUpdateStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = self.makeStore(
            installed: "1.1.1",
            defaults: defaults,
            lookup: FakeAppStoreLookup(outcome: .found("1.1.2"))
        )
        await store.checkIfNeeded(now: self.now)

        #expect(store.pendingVersion == "1.1.2")
        #expect(store.appStoreURL?.absoluteString == "https://apps.apple.com/app/id1")
    }

    @Test
    func saysNothingWhenTheLookupFails() async throws {
        let suiteName = "AppUpdateStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = self.makeStore(
            installed: "1.1.1",
            defaults: defaults,
            lookup: FakeAppStoreLookup(outcome: .failing)
        )
        await store.checkIfNeeded(now: self.now)

        #expect(store.pendingVersion == nil)
    }

    @Test
    func aFailedLookupDoesNotBurnTheDailyCheck() async throws {
        let suiteName = "AppUpdateStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let failing = FakeAppStoreLookup(outcome: .failing)
        await self.makeStore(installed: "1.1.1", defaults: defaults, lookup: failing)
            .checkIfNeeded(now: self.now)
        #expect(failing.calls == 1)

        // 離線那一次不能把接下來一整天的檢查都關掉。
        let recovered = FakeAppStoreLookup(outcome: .found("1.1.2"))
        let store = self.makeStore(
            installed: "1.1.1",
            defaults: defaults,
            lookup: recovered
        )
        await store.checkIfNeeded(now: self.now.addingTimeInterval(60))

        #expect(recovered.calls == 1)
        #expect(store.pendingVersion == "1.1.2")
    }

    @Test
    func doesNotAskTheStoreTwiceInOneDay() async throws {
        let suiteName = "AppUpdateStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let lookup = FakeAppStoreLookup(outcome: .found("1.1.2"))
        let store = self.makeStore(
            installed: "1.1.1",
            defaults: defaults,
            lookup: lookup
        )

        await store.checkIfNeeded(now: self.now)
        store.dismiss(now: self.now)
        await store.checkIfNeeded(now: self.now.addingTimeInterval(60))

        #expect(lookup.calls == 1)
    }

    @Test
    func dismissingSurvivesARelaunchAndKeepsTheStoreLinkUsable() async throws {
        let suiteName = "AppUpdateStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = self.makeStore(
            installed: "1.1.1",
            defaults: defaults,
            lookup: FakeAppStoreLookup(outcome: .found("1.1.2"))
        )
        await store.checkIfNeeded(now: self.now)

        store.dismiss(now: self.now)
        #expect(store.pendingVersion == nil)
        // 「前往更新」是在 isPresented 被設回 false *之後* 才跑的 —— 網址還要在。
        #expect(store.appStoreURL != nil)

        let relaunched = self.makeStore(
            installed: "1.1.1",
            defaults: defaults,
            lookup: FakeAppStoreLookup(outcome: .found("1.1.2"))
        )
        await relaunched.checkIfNeeded(
            now: self.now.addingTimeInterval(AppUpdatePolicy.checkInterval)
        )

        #expect(relaunched.pendingVersion == nil)
    }

    private func makeStore(
        installed: String,
        defaults: UserDefaults,
        lookup: FakeAppStoreLookup
    )
        -> AppUpdateStore
    {
        AppUpdateStore(
            installedVersion: installed,
            lookup: lookup,
            memory: AppUpdateMemory(defaults: defaults)
        )
    }
}

private final class FakeAppStoreLookup: AppStoreVersionLookup, @unchecked Sendable {
    enum Outcome {
        case found(String)
        case failing
    }

    private(set) var calls = 0
    private let outcome: Outcome

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func latestRelease() async throws -> AppStoreRelease? {
        self.calls += 1
        switch self.outcome {
        case let .found(version):
            return AppStoreRelease(
                version: version,
                url: URL(string: "https://apps.apple.com/app/id1")!
            )
        case .failing:
            throw URLError(.notConnectedToInternet)
        }
    }
}
