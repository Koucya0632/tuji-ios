// How much 自製圖鑑 room the account has, as the capture flow must ask it.
//
// Two things consume a slot: a confirmed item, and a capture already committed
// to 生成佇列 that has not confirmed yet. The gate counted only the first. The
// server's usage snapshot is the authority on confirmed items and cannot know
// about the second, so at capacity − 1 two quick captures both passed — and the
// second died inside the queue as an untyped failure whose tile said
// 「生成失敗，點一下重試」, offering a retry that could only fail the same way.
//
// `AtlasQuotas` stays the pure mirror of the server's own arithmetic
// (lib/atlas/entitlement.ts). This module is the *reading* built on it: same
// math, plus the half of the truth only the client knows.

import Foundation

struct AtlasCapacityReadout: Equatable {
    /// nil = unknown. An absent entitlement resolves to "allow" throughout —
    /// the server is the authority and rejects if truly over, so the UI stays
    /// permissive rather than blocking on a snapshot that has not arrived.
    let remaining: Int?
    let limit: Int?
    /// Captures the server has not counted yet, already subtracted from
    /// `remaining`. Kept for the copy, which reads differently when the slots
    /// are spoken for rather than spent.
    let inFlight: Int

    static func of(_ entitlement: AtlasEntitlement?, inFlight: Int) -> Self {
        AtlasCapacityReadout(
            remaining: AtlasQuotas.remainingSlots(entitlement).map { max(0, $0 - inFlight) },
            limit: entitlement?.atlasSlotsLimit,
            inFlight: inFlight
        )
    }

    var canCapture: Bool {
        self.remaining.map { $0 > 0 } ?? true
    }

    /// Why capture is blocked, *before* it becomes a sentence — nil when it
    /// isn't. Separated from the rendering below so the decision can be
    /// asserted without pinning a test to one language's wording; the string is
    /// resolved through `tujiLocalized`, so what it says depends on the running
    /// device's interface language.
    enum Blocker: Equatable {
        /// Every free slot is claimed by a capture still being made. Not a dead
        /// end — waiting works, and telling this user to delete something would
        /// be wrong advice.
        case waitingOnQueue(Int)
        /// At a ceiling we can name.
        case atLimit(Int)
        /// At a ceiling we cannot name: no entitlement snapshot has arrived.
        case atUnknownLimit
    }

    var blocker: Blocker? {
        guard !self.canCapture else { return nil }
        if self.inFlight > 0 { return .waitingOnQueue(self.inFlight) }
        guard let limit = self.limit else { return .atUnknownLimit }
        return .atLimit(limit)
    }

    /// `isPro` comes from `EffectiveEntitlementReading` rather than from the
    /// snapshot above, so 拍照 cannot disagree with 設定 about who is Pro
    /// (CONTEXT.md → 生效權限). Only the ceiling case is sold to; being told to
    /// wait is not an upgrade prompt.
    func message(isPro: Bool) -> String {
        switch self.blocker ?? .atUnknownLimit {
        case let .waitingOnQueue(count):
            tujiLocalized("還有 \(count) 張卡片正在生成，完成後再新增。")
        case .atUnknownLimit:
            tujiLocalized("自製圖鑑已達上限，刪除一些後再新增。")
        case let .atLimit(limit):
            isPro
                ? tujiLocalized("自製圖鑑已達上限（\(limit)），刪除一些後再新增。")
                : tujiLocalized("自製圖鑑已達免費上限（\(limit)），升級 Pro 可擴充，或刪除一些。")
        }
    }
}
