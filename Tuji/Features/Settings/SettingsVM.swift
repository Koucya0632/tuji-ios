// 設定's two writes: clear this account's learning progress, and delete the
// account itself.
//
// Both lived in `View`s, and neither could be tested.
//
//   * `deleteAccount()` was a private method on `SettingsView`, reaching a
//     `private let users = LiveUserRepository.shared` with no init seam — the
//     exact shape `ReportFlow` names as the defect it was carved out to fix.
//     It deletes the account.
//   * `clearProgress` was on `ProgressVM`, which lived in
//     `MeProgressSections.swift` — a file named after a screen that never calls
//     it; its only caller is 設定 → 帳號. Its three collaborators arrived as
//     *method parameters* rather than init seams, so a test would have had to
//     hand it the real singletons.
//
// The fan-out stays here rather than joining `SessionRefresh`: that one hangs
// off a finished study session and carries a `PendingWriteDraining` there is
// nothing to drain for. What clearing shares with it is the invalidate-then-
// reload shape, which is why both speak `RefreshableStore`.

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class SettingsVM {
    private(set) var clearing = false
    private(set) var clearError: Error?
    private(set) var deleting = false
    private(set) var deleteError: Error?

    private let users: UserRepository
    private let progressRepository: ProgressRepository
    private let entitlement: any EffectiveEntitlementReading
    private let log = Logger(subsystem: "app.tuji.ios", category: "settings")

    init(
        users: UserRepository = LiveUserRepository.shared,
        progressRepository: ProgressRepository = LiveProgressRepository.shared,
        entitlement: any EffectiveEntitlementReading = LiveEffectiveEntitlement.shared
    ) {
        self.users = users
        self.progressRepository = progressRepository
        self.entitlement = entitlement
    }

    /// Whether this account has Pro by any route — server entitlement first,
    /// device StoreKit flag only while that is unknown. 我 reads the same
    /// answer, so the account row cannot disagree with the paywall.
    var isPro: Bool {
        self.entitlement.isPro
    }

    /// 設定 → 帳號 → 清除學習進度.
    ///
    /// The server wipes `user_cards` too, so the stats store has to be
    /// invalidated alongside progress — otherwise 學習 shows the pre-wipe
    /// due/seen counts for up to 30s. The local learned set goes as well: 完成度
    /// and the category breakdown read it, and sync is union-only, so a stale
    /// local set would resurrect the cleared ids at the next sign-in.
    ///
    /// The stores are parameters because a screen holds them in its environment
    /// and this object does not; they are `RefreshableStore` so a test can pass
    /// spies.
    func clearProgress(learned: LearnedSetClearing, stores: [RefreshableStore]) async {
        self.clearing = true
        self.clearError = nil
        defer { self.clearing = false }
        do {
            try await self.progressRepository.clearProgress()
            learned.clearLearned()
            for store in stores {
                store.invalidate()
            }
            let reloads = stores.map { store in Task { await store.reload() } }
            for reload in reloads {
                await reload.value
            }
        } catch {
            self.clearError = error
            self.log.error("clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 設定 → 帳號 → 刪除帳號, behind two confirmations.
    ///
    /// Signing out only after the server accepts: a failed delete that had
    /// already signed the user out would look like it worked.
    func deleteAccount(signOut: @MainActor () async -> Void) async {
        self.deleting = true
        self.deleteError = nil
        defer { self.deleting = false }
        do {
            try await self.users.deleteAccount()
            await signOut()
        } catch {
            self.deleteError = error
            self.log.error("delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func dismissClearError() {
        self.clearError = nil
    }

    func dismissDeleteError() {
        self.deleteError = nil
    }
}

/// The local learned set, as the one thing clearing needs from `LocalCache`.
@MainActor
protocol LearnedSetClearing {
    func clearLearned()
}

extension LocalCache: LearnedSetClearing {}
