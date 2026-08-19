// Pins 設定's two destructive writes.
//
// `deleteAccount()` was a private method on a 477-line `View`, reaching a
// hardcoded `private let users = LiveUserRepository.shared` — the shape
// `ReportFlow` names as the defect it was carved out to fix. It deletes the
// account, and nothing could reach it.
//
// `clearProgress` was on `ProgressVM`, which lived in `MeProgressSections.swift`
// — a file named after a screen that never calls it — and took its three
// collaborators as *method parameters*, so a test would have had to hand it the
// real singletons.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct SettingsVMTests {
    private struct Boom: Error {}

    private final class SpyUsers: UserRepository {
        var deleteCalls = 0
        var deleteResult: Result<Void, Error> = .success(())

        func deleteAccount() async throws {
            self.deleteCalls += 1
            try self.deleteResult.get()
        }

        /// Unused by these tests; the seam is the whole protocol.
        func loadSettings() async throws -> UserSettings {
            .default
        }

        func saveSettings(_: UserSettings) async throws {}
        func syncLocalCache(_: SyncPayload) async throws {}
        func loadMe() async throws -> UserMeResponse {
            throw Boom()
        }

        func registerPushToken(_: PushTokenPayload) async throws {}
        func unregisterPushToken(deviceId _: String) async throws {}
        func submitFeedback(_: FeedbackPayload) async throws {}
    }

    private final class SpyProgress: ProgressRepository {
        var clearCalls = 0
        var clearResult: Result<Void, Error> = .success(())

        func clearProgress() async throws {
            self.clearCalls += 1
            try self.clearResult.get()
        }

        func loadProgress() async throws -> ProgressResponse {
            throw Boom()
        }

        func loadMastery() async throws -> MasteryListResponse {
            throw Boom()
        }

        func loadTopWords(type _: String, limit _: Int) async throws -> TopWordsResponse {
            throw Boom()
        }

        func toggleFavorite(wordId _: String, isFavorite _: Bool) async {}
    }

    private final class SpyLearned: LearnedSetClearing {
        var cleared = 0
        func clearLearned() {
            self.cleared += 1
        }
    }

    private final class SpyStore: RefreshableStore {
        private(set) var order: [String] = []
        func invalidate() {
            self.order.append("invalidate")
        }

        func reload() async {
            self.order.append("reload")
        }
    }

    // MARK: - 清除學習進度

    /// The order is the rule: invalidate first, then reload. Reloading a store
    /// that still holds its pre-wipe copy just refills it with what was there.
    @Test
    func clearingInvalidatesEveryStoreBeforeReloadingIt() async {
        let vm = SettingsVM(progressRepository: SpyProgress())
        let a = SpyStore()
        let b = SpyStore()

        await vm.clearProgress(learned: SpyLearned(), stores: [a, b])

        #expect(a.order == ["invalidate", "reload"])
        #expect(b.order == ["invalidate", "reload"])
    }

    /// The local learned set goes too: 完成度 and the category breakdown read it,
    /// and sync is union-only — a stale local set would resurrect the cleared
    /// ids at the next sign-in.
    @Test
    func clearingAlsoDropsTheLocalLearnedSet() async {
        let learned = SpyLearned()
        await SettingsVM(progressRepository: SpyProgress())
            .clearProgress(learned: learned, stores: [])
        #expect(learned.cleared == 1)
    }

    /// A failed clear must not wipe anything locally — the account still has
    /// its progress, and a client that pretended otherwise would be lying.
    @Test
    func aFailedClearTouchesNothingLocally() async {
        let repo = SpyProgress()
        repo.clearResult = .failure(Boom())
        let learned = SpyLearned()
        let store = SpyStore()
        let vm = SettingsVM(progressRepository: repo)

        await vm.clearProgress(learned: learned, stores: [store])

        #expect(learned.cleared == 0)
        #expect(store.order.isEmpty)
        #expect(vm.clearError != nil)
        #expect(!vm.clearing)
    }

    @Test
    func clearErrorIsDismissible() async {
        let repo = SpyProgress()
        repo.clearResult = .failure(Boom())
        let vm = SettingsVM(progressRepository: repo)
        await vm.clearProgress(learned: SpyLearned(), stores: [])
        #expect(vm.clearError != nil)
        vm.dismissClearError()
        #expect(vm.clearError == nil)
    }

    // MARK: - 刪除帳號

    /// Sign out only after the server accepts. A failed delete that had already
    /// signed the user out would look exactly like one that worked.
    @Test
    func aFailedDeleteDoesNotSignTheUserOut() async {
        let users = SpyUsers()
        users.deleteResult = .failure(Boom())
        let vm = SettingsVM(users: users)
        var signedOut = false

        await vm.deleteAccount { signedOut = true }

        #expect(users.deleteCalls == 1)
        #expect(!signedOut)
        #expect(vm.deleteError != nil)
        #expect(!vm.deleting)
    }

    @Test
    func aSucceedingDeleteSignsTheUserOut() async {
        let vm = SettingsVM(users: SpyUsers())
        var signedOut = false

        await vm.deleteAccount { signedOut = true }

        #expect(signedOut)
        #expect(vm.deleteError == nil)
    }

    @Test
    func deleteErrorIsDismissible() async {
        let users = SpyUsers()
        users.deleteResult = .failure(Boom())
        let vm = SettingsVM(users: users)
        await vm.deleteAccount {}
        #expect(vm.deleteError != nil)
        vm.dismissDeleteError()
        #expect(vm.deleteError == nil)
    }

    // MARK: - Pro

    /// 我 and 設定 read the same answer, so the account row cannot disagree with
    /// the paywall. The seam that makes this assertable is the one the preview
    /// uses to show a Pro layout nobody could see before.
    @Test
    func proComesFromTheEntitlementSeam() {
        #expect(SettingsVM(entitlement: PreviewEntitlement(isPro: true)).isPro)
        #expect(!SettingsVM(entitlement: PreviewEntitlement(isPro: false)).isPro)
    }
}
