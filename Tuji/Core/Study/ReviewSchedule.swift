// Client-side "next review in …" formatting for mastery detail, plus a
// tolerant ISO8601 parser for the schedule timestamps.
//
// The countdown strings mirror the backend `humanizeWhen` / `humanizeInterval`
// (lib/srs.ts). They're returned as `LocalizedStringKey` so `Text(...)` resolves
// them against the SwiftUI environment locale (driven by uiLang) — the zh-Hans
// values live in the String Catalog and switch live with the interface language.
//
// Why timestamps are decoded as `String` and parsed: `JSONDecoder.tuji` used to
// carry `.iso8601`, whose formatter rejects the fractional seconds the server's
// `Date.toISOString()` always emits — so a `Date` field would throw and sink the
// payload. That strategy is `Wire.parseISO` now, so the constraint is lifted;
// the existing `String` fields are left as they are rather than re-typed.

import SwiftUI

enum ReviewSchedule {
    /// Due now or already past.
    static func isOverdue(_ date: Date, now: Date = .now) -> Bool {
        date <= now
    }

    /// "複習期" when due, else a relative countdown ("3 天後", "約 2 週後", …).
    static func countdownLabel(until date: Date, now: Date = .now) -> LocalizedStringKey {
        if self.isOverdue(date, now: now) { return "複習期" }
        return self.humanizeInterval(days: date.timeIntervalSince(now) / 86_400)
    }

    /// Port of lib/srs.ts `humanizeInterval`.
    private static func humanizeInterval(days: Double) -> LocalizedStringKey {
        if days < 1 {
            let mins = Int((days * 24 * 60).rounded())
            if mins < 60 { return "\(mins) 分鐘後" }
            let hours = Int((Double(mins) / 60).rounded())
            return "\(hours) 小時後"
        }
        if days < 7 { return "\(Int(days.rounded())) 天後" }
        if days < 30 { return "約 \(Int((days / 7).rounded())) 週後" }
        if days < 365 { return "約 \(Int((days / 30).rounded())) 個月後" }
        return "約 \(days / 365, specifier: "%.1f") 年後"
    }

    // MARK: - ISO parsing

    /// Kept as the name four call sites already use. The parser itself is
    /// `Wire.parseISO` — reading a timestamp off the wire is not 複習's
    /// business, and while it lived here the decoder next door still carried
    /// the strategy that rejects the fractional seconds this tolerates.
    static func parseISO(_ string: String) -> Date? {
        Wire.parseISO(string)
    }
}
