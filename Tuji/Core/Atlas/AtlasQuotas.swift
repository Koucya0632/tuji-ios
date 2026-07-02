// Pure quota math for the 自製圖鑑 capture flow. Mirrors the server's
// lib/atlas/entitlement.ts so the UI and backend agree on what "at the limit"
// means. Shared by AtlasCaptureView for capture gating and remaining-quota copy.
//
// A nil limit means unlimited (Pro). An absent entitlement (not yet fetched)
// resolves to "allow" — the server is the authority and rejects if truly over,
// so the UI stays permissive rather than blocking on a missing snapshot.

import Foundation

enum AtlasQuotas {
    /// Remaining 自製圖鑑 slots, clamped to ≥ 0. nil = unknown (allow).
    static func remainingSlots(_ entitlement: AtlasEntitlement?) -> Int? {
        guard let entitlement else { return nil }
        return Swift.max(0, entitlement.atlasSlotsLimit - entitlement.usage.atlasSlots)
    }

    /// Whether another 自製圖鑑 item can be created right now.
    static func canCreateItem(_ entitlement: AtlasEntitlement?) -> Bool {
        guard let remaining = remainingSlots(entitlement) else { return true }
        return remaining > 0
    }

    /// Remaining ordinary AI recognitions this month, clamped to ≥ 0.
    static func remainingPrimaryAi(_ entitlement: AtlasEntitlement?) -> Int? {
        guard let entitlement else { return nil }
        return Swift.max(0, entitlement.primaryAiSoftLimitMonthly - entitlement.usage.primaryAiThisMonth)
    }

    /// Whether 高精度 (precision) recognition is available at all — a nonzero
    /// monthly allowance means Pro. Unknown entitlement = allow (server enforces).
    static func precisionAvailable(_ entitlement: AtlasEntitlement?) -> Bool {
        guard let entitlement else { return true }
        return entitlement.precisionAiLimitMonthly > 0
    }

    /// Remaining precision recognitions this month, clamped to ≥ 0.
    static func remainingPrecisionAi(_ entitlement: AtlasEntitlement?) -> Int? {
        guard let entitlement else { return nil }
        return Swift.max(0, entitlement.precisionAiLimitMonthly - entitlement.usage.precisionAiThisMonth)
    }
}
