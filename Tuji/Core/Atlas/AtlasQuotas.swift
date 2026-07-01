// Pure quota math for the 自製圖鑑 capture flow. Mirrors the server's
// lib/atlas/entitlement.ts so the UI and backend agree on what "at the limit"
// means. Shared by AtlasCaptureView for capture gating and remaining-quota copy.
//
// A nil limit means unlimited (Pro). An absent entitlement (not yet fetched)
// resolves to "allow" — the server is the authority and rejects if truly over,
// so the UI stays permissive rather than blocking on a missing snapshot.

import Foundation

enum AtlasQuotas {
    /// Remaining item slots, clamped to ≥ 0. nil = unlimited or unknown.
    static func remainingItems(_ entitlement: AtlasEntitlement?) -> Int? {
        guard let entitlement, let max = entitlement.limits.maxItems else { return nil }
        return Swift.max(0, max - entitlement.usage.itemCount)
    }

    /// Whether another 自製圖鑑 item can be created right now.
    static func canCreateItem(_ entitlement: AtlasEntitlement?) -> Bool {
        guard let remaining = remainingItems(entitlement) else { return true }
        return remaining > 0
    }

    /// Remaining AI recognitions today, clamped to ≥ 0. nil = unlimited or unknown.
    static func remainingAi(_ entitlement: AtlasEntitlement?) -> Int? {
        guard let entitlement, let daily = entitlement.limits.dailyAiRecognitions else { return nil }
        return Swift.max(0, daily - entitlement.usage.aiRecognitionsToday)
    }
}
