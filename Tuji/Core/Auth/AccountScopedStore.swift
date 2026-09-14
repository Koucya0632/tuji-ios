// What has to be forgotten when the account changes.
//
// `AuthService.signOut` reset several app-lifetime singletons by name, in a method
// whose own comment explained why each one mattered — and nothing anywhere said
// that a new account-scoped store would have to come here and enrol. The
// obligation existed only as prose inside the method that discharges it, which
// is the worst place for it: you have to already be editing sign-out to learn
// that sign-out is what you must edit.
//
// ADR-0001 §4 blesses this glue staying `.shared`. That is about *how* the
// reset reaches them, not about whether the list can name itself.

import Foundation

/// A store whose contents belong to one account and must not survive into the
/// next one.
///
/// Conform, add yourself to `AccountScopedStores.all`, and sign-out takes care
/// of itself. `AccountScopedStoreTests` asserts the roster, so a store that
/// conforms without enrolling fails rather than leaking.
@MainActor
protocol AccountScopedStore {
    /// Drop everything belonging to the signed-out account.
    func reset()
}

extension AtlasStore: AccountScopedStore {}
extension AtlasCaptureQueue: AccountScopedStore {}
extension MyCollectionsCache: AccountScopedStore {}
extension BlockStore: AccountScopedStore {}
extension StudyAnswerOutbox: AccountScopedStore {}
extension SettingsStore: AccountScopedStore {}
extension MasteryStore: AccountScopedStore {}
extension ProgressStore: AccountScopedStore {}
extension StudyStatsStore: AccountScopedStore {}
extension StudyQueueStore: AccountScopedStore {}
extension LocalCache: AccountScopedStore {}

@MainActor
enum AccountScopedStores {
    /// Everything sign-out clears, and why each one is on the list:
    ///
    /// - `AtlasStore` — its sync merge is additive, so without a wipe the next
    ///   account still sees this account's 自製圖鑑.
    /// - `AtlasCaptureQueue` — it journals its jobs to disk and would resume
    ///   them under the next account's session.
    /// - `MyCollectionsCache` — it is account-lifetime by design and would hand
    ///   the next account this one's 合集 list.
    /// - `BlockStore` — it would hide the next account's feed on this
    ///   account's behalf.
    /// - `StudyAnswerOutbox` — queued writes carry account state and must not
    ///   survive a sign-out even though each entry is also owner-tagged.
    ///
    /// The six below were missing until 2026-09-15, which is how the roster's
    /// own promise ("a store that conforms without enrolling fails rather than
    /// leaking") went unkept: they never conformed, so nothing failed.
    ///
    /// - `SettingsStore` — the themes, goal and accent in hand were the previous
    ///   account's; a guest after sign-out studied from them.
    /// - `MasteryStore` — once loaded it never re-fetched, so the next account
    ///   saw the previous one's scores until a study session ended.
    /// - `ProgressStore`, `StudyStatsStore` — streak, heatmap and due counts,
    ///   served from a 30-second cache that has no account in it.
    /// - `StudyQueueStore` — a prefetched queue whose signature has no account.
    /// - `LocalCache` — the device's bookmarks, uploaded into whichever account
    ///   signs in next.
    static var all: [any AccountScopedStore] {
        [
            AtlasStore.shared,
            AtlasCaptureQueue.shared,
            MyCollectionsCache.shared,
            BlockStore.shared,
            StudyAnswerOutbox.shared,
            SettingsStore.shared,
            MasteryStore.shared,
            ProgressStore.shared,
            StudyStatsStore.shared,
            StudyQueueStore.shared,
            LocalCache.shared
        ]
    }

    static func resetAll() {
        for store in self.all {
            store.reset()
        }
    }
}
