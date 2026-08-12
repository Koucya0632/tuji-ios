// What has to be forgotten when the account changes.
//
// `AuthService.signOut` reset four app-lifetime singletons by name, in a method
// whose own comment explained why each one mattered — and nothing anywhere said
// that a *fifth* account-scoped store would have to come here and enrol. The
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
    static var all: [any AccountScopedStore] {
        [
            AtlasStore.shared,
            AtlasCaptureQueue.shared,
            MyCollectionsCache.shared,
            BlockStore.shared
        ]
    }

    static func resetAll() {
        for store in self.all {
            store.reset()
        }
    }
}
